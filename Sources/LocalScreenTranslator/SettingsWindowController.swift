import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private let settings: AppSettings
    private let onHotKeysChanged: () -> Void
    private var window: NSWindow?
    private var translatePopup: NSPopUpButton?
    private var screenshotPopup: NSPopUpButton?
    private var inputTranslationPopup: NSPopUpButton?
    private var translationEnginePopup: NSPopUpButton?
    private var baseURLField: NSTextField?
    private var modelPopup: NSPopUpButton?
    private var apiKeyField: NSSecureTextField?
    private var timeoutField: NSTextField?
    private var fallbackCheckbox: NSButton?
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

        let size = NSSize(width: 500, height: 520)
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

        addSectionLabel("快捷键", at: NSPoint(x: 28, y: 474), to: contentView)

        addLabel("截图翻译快捷键", at: NSPoint(x: 28, y: 434), to: contentView)
        let translatePopup = makeShortcutPopup(frame: NSRect(x: 180, y: 428, width: 280, height: 32))
        translatePopup.target = self
        translatePopup.action = #selector(shortcutChanged)
        contentView.addSubview(translatePopup)
        self.translatePopup = translatePopup

        addLabel("截图快捷键", at: NSPoint(x: 28, y: 388), to: contentView)
        let screenshotPopup = makeShortcutPopup(frame: NSRect(x: 180, y: 382, width: 280, height: 32))
        screenshotPopup.target = self
        screenshotPopup.action = #selector(shortcutChanged)
        contentView.addSubview(screenshotPopup)
        self.screenshotPopup = screenshotPopup

        addLabel("输入翻译快捷键", at: NSPoint(x: 28, y: 342), to: contentView)
        let inputTranslationPopup = makeShortcutPopup(frame: NSRect(x: 180, y: 336, width: 280, height: 32))
        inputTranslationPopup.target = self
        inputTranslationPopup.action = #selector(shortcutChanged)
        contentView.addSubview(inputTranslationPopup)
        self.inputTranslationPopup = inputTranslationPopup

        addSeparator(at: 312, to: contentView)
        addSectionLabel("翻译引擎", at: NSPoint(x: 28, y: 282), to: contentView)

        addLabel("模式", at: NSPoint(x: 28, y: 244), to: contentView)
        let translationEnginePopup = makeTranslationEnginePopup(frame: NSRect(x: 180, y: 238, width: 280, height: 32))
        translationEnginePopup.target = self
        translationEnginePopup.action = #selector(translationSettingsChanged)
        contentView.addSubview(translationEnginePopup)
        self.translationEnginePopup = translationEnginePopup

        addLabel("Base URL", at: NSPoint(x: 28, y: 202), to: contentView)
        let baseURLField = makeTextField(frame: NSRect(x: 180, y: 198, width: 280, height: 24))
        contentView.addSubview(baseURLField)
        self.baseURLField = baseURLField

        addLabel("Model", at: NSPoint(x: 28, y: 164), to: contentView)
        let modelPopup = NSPopUpButton(frame: NSRect(x: 180, y: 156, width: 280, height: 32), pullsDown: false)
        modelPopup.target = self
        modelPopup.action = #selector(translationSettingsChanged)
        contentView.addSubview(modelPopup)
        self.modelPopup = modelPopup

        addLabel("API Key", at: NSPoint(x: 28, y: 126), to: contentView)
        let apiKeyField = NSSecureTextField(frame: NSRect(x: 180, y: 122, width: 280, height: 24))
        apiKeyField.delegate = self
        apiKeyField.target = self
        apiKeyField.action = #selector(translationSettingsChanged)
        contentView.addSubview(apiKeyField)
        self.apiKeyField = apiKeyField

        addLabel("超时（秒）", at: NSPoint(x: 28, y: 88), to: contentView)
        let timeoutField = makeTextField(frame: NSRect(x: 180, y: 84, width: 84, height: 24))
        contentView.addSubview(timeoutField)
        self.timeoutField = timeoutField

        let fallbackCheckbox = NSButton(checkboxWithTitle: "本地 AI 失败时使用 Apple 机翻备用", target: self, action: #selector(translationSettingsChanged))
        fallbackCheckbox.frame = NSRect(x: 276, y: 84, width: 220, height: 24)
        contentView.addSubview(fallbackCheckbox)
        self.fallbackCheckbox = fallbackCheckbox

        addSeparator(at: 62, to: contentView)
        let loginItemCheckbox = NSButton(checkboxWithTitle: "开机启动", target: self, action: #selector(launchAtLoginChanged))
        loginItemCheckbox.frame = NSRect(x: 24, y: 30, width: 180, height: 24)
        contentView.addSubview(loginItemCheckbox)
        self.loginItemCheckbox = loginItemCheckbox

        let note = NSTextField(labelWithString: "开机启动请先用安装脚本生成“虎译.app”，并从 App 启动后开启；swift run 不适合开机启动。")
        note.frame = NSRect(x: 180, y: 20, width: 280, height: 34)
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

    private func addSectionLabel(_ text: String, at point: NSPoint, to view: NSView) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: point.x, y: point.y, width: 180, height: 22)
        label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        view.addSubview(label)
    }

    private func addSeparator(at y: CGFloat, to view: NSView) {
        let separator = NSBox(frame: NSRect(x: 24, y: y, width: 452, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
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

    private func makeTranslationEnginePopup(frame: NSRect) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: frame, pullsDown: false)
        for preference in TranslationEnginePreference.allCases {
            let item = NSMenuItem(title: preference.title, action: nil, keyEquivalent: "")
            item.representedObject = preference.rawValue
            popup.menu?.addItem(item)
        }
        return popup
    }

    private func makeTextField(frame: NSRect) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.delegate = self
        field.target = self
        field.action = #selector(translationSettingsChanged)
        return field
    }

    private func refreshControls() {
        select(settings.translateShortcut, in: translatePopup)
        select(settings.screenshotShortcut, in: screenshotPopup)
        select(settings.inputTranslationShortcut, in: inputTranslationPopup)
        select(settings.translationEngine, in: translationEnginePopup)
        baseURLField?.stringValue = settings.localAIBaseURL
        refreshModelPopup()
        apiKeyField?.stringValue = settings.localAIAPIKey
        timeoutField?.stringValue = String(Int(settings.localAITimeout))
        fallbackCheckbox?.state = settings.appleTranslationFallbackEnabled ? .on : .off
        loginItemCheckbox?.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    private func refreshModelPopup() {
        guard let modelPopup else { return }

        let savedModel = settings.localAIModel
        var models = OMLXModelStore.availableModels()
        if !savedModel.isEmpty, !models.contains(savedModel) {
            models.insert(savedModel, at: 0)
        }
        if models.isEmpty {
            models = [savedModel.isEmpty ? "gemma-4-e4b-it-4bit" : savedModel]
        }

        modelPopup.removeAllItems()
        for model in models {
            modelPopup.addItem(withTitle: model)
            modelPopup.lastItem?.representedObject = model
        }

        let selectedModel = models.contains(savedModel) ? savedModel : models[0]
        selectModel(selectedModel)
        settings.localAIModel = selectedModel
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

    private func select(_ preference: TranslationEnginePreference, in popup: NSPopUpButton?) {
        guard let popup,
              let item = popup.itemArray.first(where: { $0.representedObject as? String == preference.rawValue })
        else { return }
        popup.select(item)
    }

    private func selectedTranslationEngine() -> TranslationEnginePreference? {
        guard let rawValue = translationEnginePopup?.selectedItem?.representedObject as? String else { return nil }
        return TranslationEnginePreference(rawValue: rawValue)
    }

    private func selectModel(_ model: String) {
        guard let modelPopup,
              let item = modelPopup.itemArray.first(where: { $0.representedObject as? String == model })
        else { return }
        modelPopup.select(item)
    }

    private func selectedModel() -> String {
        modelPopup?.selectedItem?.representedObject as? String ?? settings.localAIModel
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

    @objc private func translationSettingsChanged() {
        guard let translationEngine = selectedTranslationEngine() else {
            refreshControls()
            return
        }

        settings.translationEngine = translationEngine
        settings.localAIBaseURL = baseURLField?.stringValue ?? ""
        settings.localAIModel = selectedModel()
        settings.localAIAPIKey = apiKeyField?.stringValue ?? ""

        let timeout = TimeInterval(timeoutField?.stringValue ?? "") ?? 20
        settings.localAITimeout = timeout
        settings.appleTranslationFallbackEnabled = fallbackCheckbox?.state == .on
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        translationSettingsChanged()
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
