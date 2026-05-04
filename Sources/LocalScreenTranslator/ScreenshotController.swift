import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotController {
    private let screenCaptureService: ScreenCaptureService
    private let ocrService: OCRService
    private let pinnedImageController: PinnedImageController
    private let translationRouter: TranslationRouter
    private let overlayController: TranslationOverlayController
    private var previewControllers: [UUID: ScreenshotPreviewController] = [:]
    private var textPanel: OCRTextPanelController?

    init(
        screenCaptureService: ScreenCaptureService,
        ocrService: OCRService,
        pinnedImageController: PinnedImageController,
        translationRouter: TranslationRouter,
        overlayController: TranslationOverlayController
    ) {
        self.screenCaptureService = screenCaptureService
        self.ocrService = ocrService
        self.pinnedImageController = pinnedImageController
        self.translationRouter = translationRouter
        self.overlayController = overlayController
    }

    func captureScreenshot() {
        closePreviews()

        guard screenCaptureService.ensureScreenCapturePermission() else {
            showAlert(
                title: "需要屏幕录制权限",
                message: "请在系统设置中允许屏幕录制权限，然后重新运行工具。"
            )
            return
        }

        Task { @MainActor in
            await beginScreenshotSelection()
        }
    }

    private func beginScreenshotSelection() async {
        SelectionWindowController.beginSelection(
            instruction: "拖拽选择截图区域，调整锚点后点击下方按钮执行操作",
            allowsAdjustment: true,
            showsActionToolbar: true
        ) { [weak self] action, rect in
            guard let self else { return }
            Task { @MainActor in
                await self.processSelection(rect, action: action)
            }
        }
    }

    private func closePreviews() {
        let previews = Array(previewControllers.values)
        previewControllers.removeAll()
        for preview in previews {
            preview.close()
        }
    }

    private func processSelection(_ rect: CGRect, action: SelectionAction) async {
        do {
            try await Task.sleep(nanoseconds: 120_000_000)
            guard let cgImage = try await screenCaptureService.capture(rect: rect) else {
                showAlert(title: "截图失败", message: "无法截取所选屏幕区域。")
                return
            }

            let image = NSImage(cgImage: cgImage, size: NSSize(width: rect.width, height: rect.height))
            switch action {
            case .preview:
                showPreview(image: image, cgImage: cgImage, rect: rect)
            case .annotatePen:
                showPreview(image: image, cgImage: cgImage, rect: rect, initialTool: .pen)
            case .annotateArrow:
                showPreview(image: image, cgImage: cgImage, rect: rect, initialTool: .arrow)
            case .ocr:
                runOCR(in: cgImage, near: rect)
            case .pin:
                pinnedImageController.pin(image: image, near: rect)
            case .copy:
                NSPasteboard.general.copy(image: image)
            case .save:
                save(image: image)
            }
        } catch {
            showAlert(title: "截图失败", message: error.localizedDescription)
        }
    }

    private func showPreview(
        image: NSImage,
        cgImage: CGImage,
        rect: CGRect,
        initialTool: AnnotationTool = .none,
        runOCRImmediately: Bool = false
    ) {
        let id = UUID()
        let preview = ScreenshotPreviewController(
            id: id,
            image: image,
            cgImage: cgImage,
            screenRect: rect,
            ocrService: ocrService,
            pinnedImageController: pinnedImageController,
            initialTool: initialTool,
            onClose: { [weak self] id in
                self?.previewControllers[id] = nil
            }
        )
        previewControllers[id] = preview
        preview.show(runOCRImmediately: runOCRImmediately)
    }

    private func runOCR(in image: CGImage, near rect: CGRect) {
        do {
            let text = try ocrService.recognizeText(in: image, mode: .chineseAndEnglish)
            let displayText = text.isEmpty ? "未识别到文字。" : text
            let textPanel = OCRTextPanelController(text: displayText) { [weak self] in
                self?.textPanel = nil
            }
            self.textPanel = textPanel
            textPanel.show(near: rect)
        } catch {
            showAlert(title: "文字识别失败", message: error.localizedDescription)
        }
    }

    private func translate(_ image: CGImage, screenRect: CGRect) async throws {
        overlayController.clear()
        let lines = try ocrService.recognizeLines(in: image, screenRect: screenRect)
        guard !lines.isEmpty else {
            showAlert(title: "未识别到文字", message: "所选区域没有识别到英文文字。")
            return
        }

        let translations = try await translationRouter.translate(lines.map(\.text), direction: .englishToChinese)
        let items = zip(lines, translations).map { line, translated in
            TranslationOverlayItem(sourceText: line.text, targetText: translated, rect: line.rect)
        }
        overlayController.show(items: items)
    }

    private func save(image: NSImage) {
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.nameFieldStringValue = "截图.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = image.pngData else {
                showAlert(title: "保存失败", message: "无法将截图编码为 PNG。")
                return
            }
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(title: "保存失败", message: error.localizedDescription)
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
