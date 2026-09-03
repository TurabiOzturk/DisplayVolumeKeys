import AppKit
import ApplicationServices
import CoreGraphics
import OSDPrivate
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let mediaKeys = MediaKeyController()
    private let monitorVolume = MonitorVolumeController()
    private let volumeHUD = VolumeHUDController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var currentStatus = MonitorVolumeStatus(
        available: false,
        monitorName: nil,
        level: nil,
        muted: false,
        message: "Starting…"
    )
    private var permissionTimer: Timer?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureControllers()
        configureSystemObservers()
        enableLaunchAtLoginIfPossible()
        beginMediaKeyCapture()
        monitorVolume.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        mediaKeys.stop()
        permissionTimer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Display volume")
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func configureControllers() {
        mediaKeys.shouldIntercept = { [weak self] in self?.currentStatus.available == true }
        mediaKeys.onKey = { [weak self] key in self?.monitorVolume.handle(key) }

        monitorVolume.onStatusChange = { [weak self] status in
            self?.currentStatus = status
            self?.updateStatusIcon()
        }
        monitorVolume.onOSD = { [weak self] level, muted, monitorName in
            let screen = Self.screen(named: monitorName) ?? NSScreen.main
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
                self?.volumeHUD.show(level: level, muted: muted, monitorName: monitorName, on: screen)
            } else {
                let displayID = Self.displayID(for: screen) ?? CGMainDisplayID()
                DVKShowVolumeOSD(displayID, level, muted)
            }
        }
    }

    private func configureSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.monitorVolume.refresh() })

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.monitorVolume.refresh() })
    }

    private func beginMediaKeyCapture() {
        if mediaKeys.start() { return }
        _ = mediaKeys.requestAccessibilityPermission(prompt: true)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return }
            if self.mediaKeys.start() { timer.invalidate() }
        }
    }

    private func enableLaunchAtLoginIfPossible() {
        let preferenceKey = "didAttemptAutomaticLoginRegistration"
        guard !UserDefaults.standard.bool(forKey: preferenceKey) else { return }

        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            UserDefaults.standard.set(true, forKey: preferenceKey)
        default:
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: preferenceKey)
            } catch {
                NSLog("Could not enable launch at login: \(error.localizedDescription)")
            }
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if currentStatus.muted {
            symbol = "speaker.slash"
        } else if let level = currentStatus.level, level < 0.34 {
            symbol = "speaker.wave.1"
        } else {
            symbol = "speaker.wave.2"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: currentStatus.message)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let heading = NSMenuItem(title: currentStatus.monitorName ?? "DisplayVolumeKeys", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        let statusText: String
        if let level = currentStatus.level {
            let percent = Int((level * 100).rounded())
            statusText = currentStatus.muted ? "Muted" : "Volume: \(percent)%"
        } else {
            statusText = currentStatus.message
        }
        let status = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !mediaKeys.hasAccessibilityPermission {
            let permission = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }

        menu.addItem(.separator())
        let refresh = NSMenuItem(title: "Reconnect to Monitor", action: #selector(refreshMonitor), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DisplayVolumeKeys", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func refreshMonitor() {
        monitorVolume.refresh()
    }

    @objc private func openAccessibilitySettings() {
        _ = mediaKeys.requestAccessibilityPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static func screen(named name: String) -> NSScreen? {
        NSScreen.screens.first { $0.localizedName.caseInsensitiveCompare(name) == .orderedSame }
    }

    private static func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}

@main
enum DisplayVolumeKeysApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
