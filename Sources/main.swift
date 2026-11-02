// DontStopClaude: a menu bar switch that keeps your Mac awake with the lid
// closed, so Claude (or any long job) keeps running.
import AppKit
import Combine
import SwiftUI

// MARK: - System

enum System {
    @discardableResult
    static func run(_ path: String, _ args: [String]) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    /// Uses the no-password rule the installer adds; falls back to the admin prompt.
    static func setSleepDisabled(_ on: Bool) -> Bool {
        let value = on ? "1" : "0"
        if run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]).code == 0 {
            return true
        }
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges")?
            .executeAndReturnError(&error)
        return error == nil
    }

    static func isSleepDisabled() -> Bool {
        run("/usr/bin/pmset", ["-g"]).output.range(of: #"SleepDisabled\s+1"#, options: .regularExpression) != nil
    }

    static func batteryBelow(_ percent: Int) -> Bool {
        let out = run("/usr/bin/pmset", ["-g", "batt"]).output
        guard out.contains("Battery Power"),
              let r = out.range(of: #"\d+%"#, options: .regularExpression),
              let level = Int(out[r].dropLast()) else { return false }
        return level < percent
    }

    static func lidClosed() -> Bool {
        run("/usr/sbin/ioreg", ["-r", "-k", "AppleClamshellState", "-d", "4"]).output
            .contains("\"AppleClamshellState\" = Yes")
    }

    static func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }
}

// MARK: - Key and lock art

/// Heart outline in a unit square, scaled into `r`.
func heartPath(in r: CGRect) -> Path {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
    var path = Path()
    path.move(to: p(0.5, 1.0))
    path.addCurve(to: p(0.0, 0.34), control1: p(0.14, 0.78), control2: p(0.0, 0.58))
    path.addCurve(to: p(0.5, 0.20), control1: p(0.0, 0.02), control2: p(0.40, -0.02))
    path.addCurve(to: p(1.0, 0.34), control1: p(0.60, -0.02), control2: p(1.0, 0.02))
    path.addCurve(to: p(0.5, 1.0), control1: p(1.0, 0.58), control2: p(0.86, 0.78))
    path.closeSubpath()
    return path
}

/// A key lying flat, pointing right: heart-shaped bow, shaft, two teeth.
struct KeyShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = heartPath(in: CGRect(x: r.minX, y: r.minY, width: r.height * 1.05, height: r.height))
        p.addRect(CGRect(x: r.minX + r.height * 0.95, y: r.midY - 1.1, width: r.width - r.height * 0.95, height: 2.2))
        p.addRect(CGRect(x: r.maxX - 4, y: r.midY, width: 2.4, height: r.height * 0.42))
        p.addRect(CGRect(x: r.maxX - 8, y: r.midY, width: 2.4, height: r.height * 0.30))
        return p
    }
}

/// The lock's arched shackle.
struct ShackleShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.width / 2))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.width / 2),
                   control1: CGPoint(x: r.minX, y: r.minY - r.width * 0.15),
                   control2: CGPoint(x: r.maxX, y: r.minY - r.width * 0.15))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// A heart-shaped lock with a keyhole cut out of it. Fill with `eoFill: true`.
struct HeartLockShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = heartPath(in: r)
        let d = r.width * 0.24
        let cx = r.midX, top = r.minY + r.height * 0.34
        p.addEllipse(in: CGRect(x: cx - d / 2, y: top, width: d, height: d))
        p.addRoundedRect(in: CGRect(x: cx - d * 0.22, y: top + d * 0.6, width: d * 0.44, height: d * 1.15),
                         cornerSize: CGSize(width: d * 0.22, height: d * 0.22))
        return p
    }
}

/// One loop of the key: slides in, jolts the lock, slides out. Returns (0...1 how far in, 0...1 jolt).
func keyMotion(at time: TimeInterval, period: Double = 0.9) -> (inset: Double, jolt: Double) {
    let phase = time.truncatingRemainder(dividingBy: period) / period
    func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    if phase < 0.38 { return (ease(phase / 0.38), 0) }                       // in
    if phase < 0.55 { return (1, sin((phase - 0.38) / 0.17 * .pi)) }        // jolt
    return (1 - ease((phase - 0.55) / 0.45), 0)                              // out
}

/// Menu bar icon: an open heart lock when off; shut, with the key going in, when on.
func lockImage(on: Bool, inserted: Bool, size: CGFloat) -> NSImage {
    let width = on ? size * 1.6 : size * 0.9
    let image = NSImage(size: NSSize(width: width, height: size), flipped: true) { rect in
        let s = rect.height
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        NSColor.black.set()
        let line = max(1.3, s * 0.10)

        // Heart lock (right side when on, alone when off).
        let hx: CGFloat = on ? 0.74 : 0.06, hy: CGFloat = 0.34, hw: CGFloat = 0.76, hh: CGFloat = 0.64
        func h(_ x: CGFloat, _ y: CGFloat) -> NSPoint { p(hx + x * hw, hy + y * hh) }

        // Shackle: shut, or lifted with one leg out.
        let left = hx + 0.26 * hw, right = hx + 0.74 * hw
        let shackle = NSBezierPath()
        if on {
            shackle.move(to: p(left, hy + 0.12)); shackle.line(to: p(left, 0.20))
            shackle.curve(to: p(right, 0.20), controlPoint1: p(left, 0.02), controlPoint2: p(right, 0.02))
            shackle.line(to: p(right, hy + 0.12))
        } else {
            shackle.move(to: p(left - 0.06, 0.24)); shackle.line(to: p(left - 0.02, 0.12))
            shackle.curve(to: p(right, 0.08), controlPoint1: p(left + 0.02, -0.06), controlPoint2: p(right, -0.08))
            shackle.line(to: p(right, hy + 0.12))
        }
        shackle.lineWidth = line
        shackle.lineCapStyle = .round
        shackle.stroke()

        let heart = NSBezierPath()
        heart.move(to: h(0.5, 1.0))
        heart.curve(to: h(0.0, 0.34), controlPoint1: h(0.14, 0.78), controlPoint2: h(0.0, 0.58))
        heart.curve(to: h(0.5, 0.20), controlPoint1: h(0.0, 0.02), controlPoint2: h(0.40, -0.02))
        heart.curve(to: h(1.0, 0.34), controlPoint1: h(0.60, -0.02), controlPoint2: h(1.0, 0.02))
        heart.curve(to: h(0.5, 1.0), controlPoint1: h(1.0, 0.58), controlPoint2: h(0.86, 0.78))
        heart.close()
        let d = 0.26 * hw
        heart.append(NSBezierPath(ovalIn: NSRect(x: (hx + 0.5 * hw - d / 2) * s, y: (hy + 0.32 * hh) * s, width: d * s, height: d * s)))
        heart.append(NSBezierPath(rect: NSRect(x: (hx + 0.5 * hw - d * 0.22) * s, y: (hy + 0.32 * hh + d * 0.6) * s,
                                               width: d * 0.44 * s, height: d * 1.0 * s)))
        heart.windingRule = .evenOdd
        heart.fill()

        // Key, only when on: points right into the lock.
        if on {
            let y = hy + 0.42 * hh
            let tip: CGFloat = inserted ? hx + 0.30 : hx - 0.10
            let bow: CGFloat = 0.28
            let key = NSBezierPath(ovalIn: NSRect(x: (tip - 0.62) * s, y: (y - bow / 2) * s, width: bow * s, height: bow * s))
            key.move(to: p(tip - 0.62 + bow, y)); key.line(to: p(min(tip, hx + 0.02), y))
            key.lineWidth = line
            key.stroke()
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - State

final class Controller: ObservableObject {
    /// When the hold ends. `.distantFuture` means "until I turn it off"; nil means off.
    @Published private(set) var endDate: Date?
    /// Chosen duration in hours; 0 means "until I turn it off".
    @Published private(set) var hours: Int
    @Published var now = Date()

    var onChange: (() -> Void)?
    private var ticker: Timer?

    /// When the current hold began, for the running total.
    private var sessionStart: Date? {
        get { UserDefaults.standard.object(forKey: "sessionStart") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "sessionStart") }
    }
    private var totalSeconds: Double {
        get { UserDefaults.standard.double(forKey: "totalSeconds") }
        set { UserDefaults.standard.set(newValue, forKey: "totalSeconds") }
    }

    var isOn: Bool { endDate != nil }

    init() {
        let defaults = UserDefaults.standard
        endDate = defaults.object(forKey: "endDate") as? Date
        hours = defaults.object(forKey: "hours") == nil ? 2 : defaults.integer(forKey: "hours")

        // Clean up a hold left over from a previous run.
        if let end = endDate, end <= Date() { turnOff() }
        let disabled = System.isSleepDisabled()
        if endDate != nil && !disabled { setEnd(nil) }
        // Sleep was turned off some other way (e.g. by hand in Terminal): show it, so it can be turned off here.
        if endDate == nil && disabled {
            sessionStart = Date()
            setEnd(.distantFuture)
        }

        ticker = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func start(hours h: Int) {
        hours = h
        UserDefaults.standard.set(h, forKey: "hours")
        guard System.setSleepDisabled(true) else { return }
        now = Date()
        if sessionStart == nil { sessionStart = now }
        setEnd(h == 0 ? .distantFuture : now.addingTimeInterval(Double(h) * 3600))
    }

    func turnOff() {
        _ = System.setSleepDisabled(false)
        if let started = sessionStart {
            totalSeconds += max(0, Date().timeIntervalSince(started))
            sessionStart = nil
        }
        setEnd(nil)
    }

    private func setEnd(_ date: Date?) {
        endDate = date
        UserDefaults.standard.set(date, forKey: "endDate")
        onChange?()
    }

    private func tick() {
        now = Date()
        guard let end = endDate else { return }
        if now >= end || System.batteryBelow(10) {
            turnOff()
            // macOS won't sleep again on its own if the lid is already shut.
            if System.lidClosed() { System.sleepNow() }
        } else {
            onChange?()
        }
    }

    /// "1h 45m", "12m", or nil when off or unlimited.
    var remaining: String? {
        guard let end = endDate, end != .distantFuture else { return nil }
        let secs = max(0, Int(end.timeIntervalSince(now)))
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(max(m, 1))m"
    }

    var statusText: String {
        guard isOn else { return "Lid down, Claude stops" }
        if let left = remaining { return "Still going · \(left) left" }
        return "Going all night"
    }

    /// How much of the hold is left, 0...1. Unlimited shows a full ring.
    var progress: Double {
        guard let end = endDate else { return 0 }
        if end == .distantFuture || hours == 0 { return 1 }
        return min(1, max(0, end.timeIntervalSince(now) / (Double(hours) * 3600)))
    }

    /// Lifetime time kept awake, including the current hold.
    var stamina: String {
        var secs = totalSeconds
        if let started = sessionStart { secs += max(0, now.timeIntervalSince(started)) }
        let total = Int(secs), h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Panel

struct Option: Identifiable {
    let hours: Int
    let label: String
    let tease: String
    var id: Int { hours }
}

extension View {
    /// Liquid Glass on macOS 26+, a soft tinted card before that.
    @ViewBuilder
    func glass(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint),
                in: shape
            )
        } else {
            self.background(shape.fill(tint ?? Color.primary.opacity(0.07)))
        }
        #else
        self.background(shape.fill(tint ?? Color.primary.opacity(0.07)))
        #endif
    }
}

struct PanelView: View {
    @ObservedObject var controller: Controller
    @State private var breathe = false

    private let options = [
        Option(hours: 1, label: "1h", tease: "A quickie"),
        Option(hours: 2, label: "2h", tease: "Just warming up"),
        Option(hours: 4, label: "4h", tease: "Stamina"),
        Option(hours: 8, label: "8h", tease: "All night long"),
        Option(hours: 0, label: "∞", tease: "Don't. Stop."),
    ]

    private var isOn: Binding<Bool> {
        Binding(
            get: { controller.isOn },
            set: { $0 ? controller.start(hours: controller.hours) : controller.turnOff() }
        )
    }

    private var tease: String {
        options.first { $0.hours == controller.hours }?.tease ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
            durations
            footer
        }
        .padding(20)
        .frame(width: 340)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.isOn)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: controller.hours)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            face

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.isOn ? "Don't stop" : "DontStopClaude")
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                Text(controller.statusText)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle())
                .controlSize(.large)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
    }

    private var face: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(controller.progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(controller.isOn ? 1 : 0)
            TimelineView(.animation(paused: !controller.isOn)) { timeline in
                let motion = controller.isOn
                    ? keyMotion(at: timeline.date.timeIntervalSinceReferenceDate)
                    : (inset: 0.0, jolt: 0.0)
                ZStack {
                    // Key first, so it slides in behind the heart and disappears into it.
                    KeyShape()
                        .frame(width: 24, height: 10)
                        .offset(x: -16 + 13 * motion.inset, y: 3)
                        .opacity(controller.isOn ? 1 : 0)

                    ZStack {
                        // Shackle: shut when on, sprung open like Apple's unlock when off.
                        ShackleShape()
                            .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .frame(width: 11, height: 10)
                            .rotationEffect(.degrees(controller.isOn ? 0 : -28), anchor: .bottomTrailing)
                            .offset(y: controller.isOn ? -12 : -16)
                        HeartLockShape()
                            .fill(style: FillStyle(eoFill: true))
                            .frame(width: 22, height: 20)
                    }
                    .offset(x: controller.isOn ? 9 : 0, y: 2)
                    .rotationEffect(.degrees(4 * motion.jolt))
                    .scaleEffect(1 + 0.12 * motion.jolt)
                }
            }
            .foregroundColor(controller.isOn ? .accentColor : .secondary)
            if !controller.isOn {
                Text("z")
                    .font(.system(size: 11, weight: .light))
                    .foregroundColor(.secondary)
                    .offset(x: 24, y: breathe ? -30 : -20)
                    .opacity(breathe ? 0 : 0.9)
            }
        }
        .frame(width: 64, height: 64)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { breathe = true }
        }
        .help(controller.isOn ? "Ring shows the time left" : "Unlocked: Claude stops when the lid closes")
    }

    private var durations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How long can Claude go?")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                Spacer()
                Text(tease)
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(controller.isOn ? .accentColor : .secondary)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = controller.hours == option.hours
                    Button(action: { controller.start(hours: option.hours) }) {
                        Text(option.label)
                            .font(.system(size: 14, weight: selected ? .medium : .light))
                            .foregroundColor(selected && controller.isOn ? .white : .primary)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .glass(cornerRadius: 12, tint: pillTint(selected), interactive: true)
                    .help(option.tease)
                }
            }
        }
    }

    private func pillTint(_ selected: Bool) -> Color? {
        guard selected else { return nil }
        return controller.isOn ? Color.accentColor : Color.primary.opacity(0.18)
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Total stamina: \(controller.stamina)")
                Text("Taps out at 10% battery")
            }
            Spacer()
            Button("I'm done") { NSApp.terminate(nil) }
                .buttonStyle(PlainButtonStyle())
                .help("Quit, and let the Mac sleep again")
        }
        .font(.system(size: 11, weight: .light))
        .foregroundColor(.secondary)
        .padding(.horizontal, 4)
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = Controller()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var host: NSHostingController<PanelView>!
    private var frameTimer: Timer?
    private var keyIn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.animates = true
        host = NSHostingController(rootView: PanelView(controller: controller))
        if #available(macOS 13.0, *) { host.sizingOptions = [.preferredContentSize] }
        popover.contentViewController = host

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        controller.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()

        // While it's on, the menu bar key goes in and out.
        frameTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            guard let self = self, self.controller.isOn else { return }
            self.keyIn.toggle()
            self.statusItem.button?.image = lockImage(on: true, inserted: self.keyIn, size: 16)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if controller.isOn { controller.turnOff() }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            controller.now = Date()
            host.view.layoutSubtreeIfNeeded()
            popover.contentSize = host.view.fittingSize
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = lockImage(on: controller.isOn, inserted: keyIn, size: 16)
        button.imagePosition = .imageLeading
        let left = controller.remaining.map { " " + $0 } ?? ""
        button.attributedTitle = NSAttributedString(string: left, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
        ])
        button.toolTip = "DontStopClaude: " + controller.statusText
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
