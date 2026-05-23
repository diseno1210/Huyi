import AppKit
import Carbon
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController!
    private var hotKeyController: HotKeyController!
    private var translationRouter: TranslationRouter!
    private let ocrService = OCRService()
    private let screenCaptureService = ScreenCaptureService()
    private let overlayController = TranslationOverlayController()
    private let pinnedImageController = PinnedImageController()
    private let appSettings = AppSettings()
    private var screenshotController: ScreenshotController!
    private var settingsWindowController: SettingsWindowController!
    private var inputTranslationController: InputTranslationController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        translationRouter = TranslationRouter(settings: appSettings)
        screenshotController = ScreenshotController(
            screenCaptureService: screenCaptureService,
            ocrService: ocrService,
            pinnedImageController: pinnedImageController,
            translationRouter: translationRouter,
            overlayController: overlayController
        )

        settingsWindowController = SettingsWindowController(settings: appSettings) { [weak self] in
            self?.configureHotKeys()
        }
        inputTranslationController = InputTranslationController(
            translationRouter: translationRouter
        )

        statusController = StatusBarController(
            onTranslateArea: { [weak self] in self?.translateScreenArea() },
            onCaptureScreenshot: { [weak self] in self?.captureScreenshot() },
            onInputTranslation: { [weak self] in self?.showInputTranslation() },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onClearOverlay: { [weak self] in self?.overlayController.clear() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )

        configureHotKeys()
    }

    private func configureHotKeys() {
        if appSettings.translateShortcut == appSettings.screenshotShortcut {
            appSettings.translateShortcut = .f4
            appSettings.screenshotShortcut = .f1
        }
        if appSettings.inputTranslationShortcut == appSettings.translateShortcut ||
            appSettings.inputTranslationShortcut == appSettings.screenshotShortcut {
            appSettings.inputTranslationShortcut = .f5
        }

        let translateShortcut = appSettings.translateShortcut
        let screenshotShortcut = appSettings.screenshotShortcut
        let inputTranslationShortcut = appSettings.inputTranslationShortcut
        hotKeyController = HotKeyController(hotKeys: [
            GlobalHotKey(
                id: 1,
                keyCode: translateShortcut.keyCode,
                modifiers: translateShortcut.modifiers,
                handler: { [weak self] in
                    DispatchQueue.main.async { self?.translateScreenArea() }
                }
            ),
            GlobalHotKey(
                id: 2,
                keyCode: screenshotShortcut.keyCode,
                modifiers: screenshotShortcut.modifiers,
                handler: { [weak self] in
                    DispatchQueue.main.async { self?.captureScreenshot() }
                }
            ),
            GlobalHotKey(
                id: 3,
                keyCode: inputTranslationShortcut.keyCode,
                modifiers: inputTranslationShortcut.modifiers,
                handler: { [weak self] in
                    DispatchQueue.main.async { self?.showInputTranslation() }
                }
            )
        ])
        hotKeyController.register()
    }

    private func captureScreenshot() {
        screenshotController.captureScreenshot()
    }

    private func showInputTranslation() {
        inputTranslationController.toggle()
    }

    private func openSettings() {
        settingsWindowController.show()
    }

    private func translateScreenArea() {
        guard screenCaptureService.ensureScreenCapturePermission() else {
            showAlert(
                title: "需要屏幕录制权限",
                message: "请在系统设置中允许屏幕录制权限，然后重新运行工具。"
            )
            return
        }

        overlayController.clear()
        Task { @MainActor in
            let snapshot = try? await screenCaptureService.captureSnapshot()
            SelectionWindowController.beginSelection(
                instruction: "拖拽选择要翻译的区域，按 Esc 取消",
                backgroundImage: snapshot?.displayImage
            ) { [weak self] rect in
                guard let self else { return }
                Task { @MainActor in
                    await self.processSelection(rect, snapshot: snapshot)
                }
            }
        }
    }

    @MainActor
    private func processSelection(_ rect: CGRect, snapshot: ScreenSnapshot?) async {
        do {
            let image: CGImage?
            if let croppedImage = snapshot?.crop(appKitRect: rect) {
                image = croppedImage
            } else {
                try await Task.sleep(nanoseconds: 120_000_000)
                image = try await screenCaptureService.capture(rect: rect)
            }

            guard let image else {
                showAlert(title: "截图失败", message: "无法截取所选屏幕区域。")
                return
            }

            let lines = try ocrService.recognizeLines(in: image, screenRect: rect)
            guard !lines.isEmpty else {
                showAlert(title: "未识别到文字", message: "所选区域没有识别到英文文字。")
                return
            }

            let translations = try await translationRouter.translate(lines.map(\.text), direction: .englishToChinese)
            let items = zip(lines, translations).map { line, translated in
                TranslationOverlayItem(sourceText: line.text, targetText: translated, rect: line.rect)
            }
            overlayController.show(items: items)
        } catch {
            showAlert(title: "翻译失败", message: error.localizedDescription)
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let quitItem = NSMenuItem(title: "退出虎译", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApplication.shared
        appMenu.addItem(quitItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        NSApplication.shared.mainMenu = mainMenu
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
