import AppKit
import Carbon.HIToolbox

/// A key combination for the global hot key, stored as a Carbon key code and modifiers.
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: Int

    /// ⌘ + the key left of 1 (§ on ISO keyboards).
    static let `default` = Shortcut(keyCode: kVK_ISO_Section, modifiers: cmdKey)

    private static let keyCodeKey = "shortcutKeyCode"
    private static let modifiersKey = "shortcutModifiers"

    static var saved: Shortcut {
        get {
            let d = UserDefaults.standard
            guard d.object(forKey: keyCodeKey) != nil else { return .default }
            return Shortcut(keyCode: d.integer(forKey: keyCodeKey), modifiers: d.integer(forKey: modifiersKey))
        }
        set {
            UserDefaults.standard.set(newValue.keyCode, forKey: keyCodeKey)
            UserDefaults.standard.set(newValue.modifiers, forKey: modifiersKey)
        }
    }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        self.init(keyCode: Int(event.keyCode), modifiers: m)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & cmdKey != 0 { f.insert(.command) }
        if modifiers & optionKey != 0 { f.insert(.option) }
        if modifiers & controlKey != 0 { f.insert(.control) }
        if modifiers & shiftKey != 0 { f.insert(.shift) }
        return f
    }

    /// Plain keys would swallow normal typing, so require ⌘, ⌃ or ⌥ (function keys excepted).
    var isValid: Bool {
        modifiers & (cmdKey | optionKey | controlKey) != 0 || Self.functionKeys.contains(keyCode)
    }

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + keyName
    }

    /// The key's character in the current layout, for use as a menu key equivalent.
    var character: String? {
        Self.specialNames[keyCode] == nil ? Self.translate(keyCode)?.lowercased() : nil
    }

    var keyName: String {
        Self.specialNames[keyCode] ?? Self.translate(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_ANSI_KeypadEnter: "⌤",
        ]
        let f = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                 kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        for (i, code) in f.enumerated() { names[code] = "F\(i + 1)" }
        return names
    }()

    private static func translate(_ keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}

/// A field that records the next key combination pressed while it's focused.
final class ShortcutRecorder: NSView {
    private(set) var shortcut: Shortcut { didSet { label.stringValue = shortcut.display } }
    private let label = NSTextField(labelWithString: "")

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.alignment = .center
        label.stringValue = shortcut.display
        label.frame = NSRect(x: 0, y: (bounds.height - 20) / 2, width: bounds.width, height: 20)
        addSubview(label)
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { defer { updateAppearance() }; return true }
    override func resignFirstResponder() -> Bool { defer { updateAppearance() }; return true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func viewDidChangeEffectiveAppearance() { updateAppearance() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        return record(event)
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    /// Plain keys (Return, Esc) fall through so the alert's buttons still work.
    private func record(_ event: NSEvent) -> Bool {
        let s = Shortcut(event: event)
        guard s.isValid else { return false }
        shortcut = s
        return true
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let focused = window?.firstResponder === self
            layer?.borderColor = (focused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
}
