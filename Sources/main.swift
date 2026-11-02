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

// MARK: - Lock symbol

extension View {
    /// Apple's own lock/unlock morph on macOS 14+.
    @ViewBuilder
    func lockMorph() -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
        #else
        self
        #endif
    }
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
            Image(systemName: controller.isOn ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(controller.isOn ? .accentColor : .secondary)
                .lockMorph()
        }
        .frame(width: 64, height: 64)
        .help(controller.isOn ? "Locked in. The ring shows the time left." : "Unlocked: Claude stops when the lid closes")
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
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var host: NSHostingController<PanelView>!

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
        let image = NSImage(systemSymbolName: controller.isOn ? "lock.fill" : "lock.open.fill",
                            accessibilityDescription: "DontStopClaude")
        image?.isTemplate = true
        button.image = image
        button.title = ""
        button.toolTip = "DontStopClaude: " + controller.statusText
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
