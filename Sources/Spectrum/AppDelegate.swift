import AppKit
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private let picker = PickerController()

    private let historyKey = "history"
    private let historyLimit = 10
    private var history: [String] {
        get { UserDefaults.standard.stringArray(forKey: historyKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(historyLimit)), forKey: historyKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Spectrum")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKey = HotKey(keyCode: kVK_ISO_Section, modifiers: cmdKey) { [weak self] in
            self?.togglePicker()
        }

        picker.onPick = { [weak self] color, point in self?.didPick(color, at: point) }
        picker.onError = { [weak self] _ in self?.showPermissionAlert() }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "launchedBefore") {
            defaults.set(true, forKey: "launchedBefore")
            Toast.show(title: "Spectrum is ready", detail: "Press ⌘§ to pick a color", duration: 3)
        }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePicker()
        return false
    }

    // MARK: - Picking

    @objc private func startPicking() {
        // Let the menu finish closing first.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.picker.isActive else { return }
            self.togglePicker()
        }
    }

    private func togglePicker() {
        if !picker.isActive && !CGPreflightScreenCaptureAccess() {
            showPermissionAlert()
            return
        }
        picker.toggle()
    }

    private func didPick(_ color: RGB, at point: NSPoint) {
        copy(color.hex)
        var h = history
        h.removeAll { $0 == color.hex }
        h.insert(color.hex, at: 0)
        history = h
        Toast.show(color: color, title: color.hex, detail: "Copied", at: point)
    }

    private func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let pickItem = NSMenuItem(title: "Pick Color", action: #selector(startPicking), keyEquivalent: "§")
        pickItem.keyEquivalentModifierMask = .command
        pickItem.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        pickItem.target = self
        menu.addItem(pickItem)

        let colors = history.compactMap(RGB.init(hex:))
        if !colors.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem.sectionHeader(title: "Recent")
            menu.addItem(header)
            for color in colors {
                let item = NSMenuItem(title: color.hex, action: #selector(copyRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = color.hex
                item.image = swatchImage(color)
                let title = NSMutableAttributedString(string: color.hex, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                ])
                title.append(NSAttributedString(string: "  " + ColorNames.name(for: color), attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
                item.attributedTitle = title
                item.toolTip = "Copy \(color.hex)"
                menu.addItem(item)
            }
            let clear = NSMenuItem(title: "Clear Recent", action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let quit = NSMenuItem(title: "Quit Spectrum", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func swatchImage(_ color: RGB) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            color.nsColor.setFill()
            path.fill()
            NSColor(white: color.luminance > 0.5 ? 0 : 1, alpha: 0.25).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
        return image
    }

    @objc private func copyRecent(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String, let color = RGB(hex: hex) else { return }
        copy(hex)
        Toast.show(color: color, title: hex, detail: "Copied")
    }

    @objc private func clearHistory() {
        history = []
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Couldn’t change login item"
            alert.informativeText = "Move Spectrum to your Applications folder and try again.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    // MARK: - Permission

    private func showPermissionAlert() {
        NSApp.activate()
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        alert.messageText = "Allow Screen Recording"
        alert.informativeText = "Spectrum needs Screen Recording access to read colors on your screen. Nothing is recorded or saved.\n\nTurn on Spectrum in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Relaunch Spectrum")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            CGRequestScreenCaptureAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            relaunch()
        default:
            break
        }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
