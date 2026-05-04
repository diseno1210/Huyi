import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private let onHotKeysChanged: () -> Void
    private var window: NSWindow?
    private var translatePopup: NSPopUpButton?
    private var screenshotPopup: NSPopUpButton?
    private var inputTranslationPopup: NSPopUpButton?
    private var loginItemCheckbox: NSButton?

    init(settings: AppSettings, onHotKeysChanged: @escaping () -> Void) {
        self.settings = settings
        self.onHotKeysChanged = onHotKeysChanged
    }

    func show() {
        if let window {
            refreshControls()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let size = NSSize(width: 440, height: 292)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = makeContentView(size: size)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
        refreshControls()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeContentView(size: NSSize) -> NSView {
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))

        addLabel("截图翻译快捷键", at: NSPoint(x: 28, y: 226), to: contentView)
        let translatePopup = makeShortcutPopup(frame: NSRect(x: 180, y: 220, width: 220, height: 32))
        translatePopup.target = self
        translatePopup.action = #selector(shortcutChanged)
        contentView.addSubview(translatePopup)
        self.translatePopup = translatePopup

        addLabel("截图快捷键", at: NSPoint(x: 28, y: 180), to: contentView)
        let screenshotPopup = makeShortcutPopup(frame: NSRect(x: 180, y: 174, width: 220, height: 32))
        screenshotPopup.target = self
        screenshotPopup.action = #selector(shortcutChanged)
        contentView.addSubview(screenshotPopup)
        self.screenshotPopup = screenshotPopup

        addLabel("输入翻译快捷键", at: NSPoint(x: 28, y: 134), to: contentView)
        let inputTranslationPopup = makeShortcutPopup(frame: NSRect(x: 180, y: 128, width: 220, height: 32))
        inputTranslationPopup.target = self
        inputTranslationPopup.action = #selector(shortcutChanged)
        contentView.addSubview(inputTranslationPopup)
        self.inputTranslationPopup = inputTranslationPopup

        let loginItemCheckbox = NSButton(checkboxWithTitle: "开机启动", target: self, action: #selector(launchAtLoginChanged))
        loginItemCheckbox.frame = NSRect(x: 24, y: 82, width: 180, height: 24)
        contentView.addSubview(loginItemCheckbox)
        self.loginItemCheckbox = loginItemCheckbox

        let note = NSTextField(labelWithString: "开机启动请先用安装脚本生成“虎译.app”，并从 App 启动后开启；swift run 不适合开机启动。")
        note.frame = NSRect(x: 28, y: 24, width: 384, height: 42)
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        contentView.addSubview(note)

        return contentView
    }

    private func addLabel(_ text: String, at point: NSPoint, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: point.x, y: point.y, width: 140, height: 20)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        view.addSubview(label)
    }

    private func makeShortcutPopup(frame: NSRect) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame, pullsDown: false)
        for preset in ShortcutPreset.allCases {
            let item = NSMenuItem(title: preset.title, action: nil, keyEquivalent: "")
            item.representedObject = preset.rawValue
            popup.menu?.addItem(item)
        }
        return popup
    }

    private func refreshControls() {
        select(settings.translateShortcut, in: translatePopup)
        select(settings.screenshotShortcut, in: screenshotPopup)
        select(settings.inputTranslationShortcut, in: inputTranslationPopup)
        loginItemCheckbox?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func select(_ preset: ShortcutPreset, in popup: NSPopUpButton?) {
        guard let popup,
              let item = popup.itemArray.first(where: { $0.representedObject as? String == preset.rawValue })
        else { return }
        popup.select(item)
    }

    private func selectedPreset(in popup: NSPopUpButton?) -> ShortcutPreset? {
        guard let rawValue = popup?.selectedItem?.representedObject as? String else { return nil }
        return ShortcutPreset(rawValue: rawValue)
    }

    @objc private func shortcutChanged() {
        guard let translateShortcut = selectedPreset(in: translatePopup),
              let screenshotShortcut = selectedPreset(in: screenshotPopup),
              let inputTranslationShortcut = selectedPreset(in: inputTranslationPopup)
        else {
            refreshControls()
            return
        }

        let shortcuts = [translateShortcut, screenshotShortcut, inputTranslationShortcut]
        guard Set(shortcuts.map(\.rawValue)).count == shortcuts.count else {
            showAlert(title: "快捷键冲突", message: "截图翻译、截图、输入翻译三个快捷键不能相同。")
            refreshControls()
            return
        }

        settings.translateShortcut = translateShortcut
        settings.screenshotShortcut = screenshotShortcut
        settings.inputTranslationShortcut = inputTranslationShortcut
        onHotKeysChanged()
    }

    @objc private func launchAtLoginChanged() {
        do {
            if loginItemCheckbox?.state == .on {
                try LaunchAtLogin.enable()
            } else {
                try LaunchAtLogin.disable()
            }
        } catch {
            showAlert(title: "开机启动失败", message: error.localizedDescription)
        }
        refreshControls()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
    }

    static func disable() throws {
        if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
