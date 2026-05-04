import AppKit
import CoreGraphics
import UniformTypeIdentifiers

@MainActor
final class ScreenshotPreviewController: NSObject, NSWindowDelegate {
    private let id: UUID
    private let image: NSImage
    private let cgImage: CGImage
    private let screenRect: CGRect
    private let ocrService: OCRService
    private let pinnedImageController: PinnedImageController
    private let onClose: (UUID) -> Void
    private var panel: NSPanel?
    private var textPanel: OCRTextPanelController?
    private weak var imageView: ScreenshotPreviewImageView?
    private var colorPanel: NSPanel?
    private var appResignObserver: NSObjectProtocol?
    private var activeTool: AnnotationTool = .none
    private var selectedColor = NSColor.systemRed
    private var paletteTool: AnnotationTool = .none
    private let colors: [AnnotationColor] = [
        AnnotationColor(name: "红色", color: .systemRed),
        AnnotationColor(name: "橙色", color: .systemOrange),
        AnnotationColor(name: "黄色", color: NSColor(calibratedRed: 1, green: 0.82, blue: 0.08, alpha: 1)),
        AnnotationColor(name: "绿色", color: .systemGreen),
        AnnotationColor(name: "青色", color: .systemCyan),
        AnnotationColor(name: "蓝色", color: .systemBlue),
        AnnotationColor(name: "紫色", color: .systemPurple),
        AnnotationColor(name: "粉色", color: .systemPink),
        AnnotationColor(name: "白色", color: .white),
        AnnotationColor(name: "黑色", color: .black)
    ]

    init(
        id: UUID,
        image: NSImage,
        cgImage: CGImage,
        screenRect: CGRect,
        ocrService: OCRService,
        pinnedImageController: PinnedImageController,
        initialTool: AnnotationTool = .none,
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.image = image
        self.cgImage = cgImage
        self.screenRect = screenRect
        self.ocrService = ocrService
        self.pinnedImageController = pinnedImageController
        self.activeTool = initialTool
        self.onClose = onClose
    }

    func show(runOCRImmediately: Bool = false) {
        let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(screenRect) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let toolbarHeight: CGFloat = 42
        let toolbarMinWidth: CGFloat = 282
        let maxImageSize = NSSize(width: screenFrame.width * 0.75, height: screenFrame.height * 0.65)
        let displaySize = image.size.scaledToFit(maxImageSize, allowUpscale: false)
        let windowSize = NSSize(width: max(displaySize.width, toolbarMinWidth), height: displaySize.height + toolbarHeight)
        let origin = CGPoint(
            x: min(max(screenRect.minX, screenFrame.minX + 16), screenFrame.maxX - windowSize.width - 16),
            y: min(max(screenRect.minY - toolbarHeight, screenFrame.minY + 16), screenFrame.maxY - windowSize.height - 16)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "截图"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = makeContentView(size: windowSize, toolbarHeight: toolbarHeight)
        panel.orderFrontRegardless()
        self.panel = panel
        beginAutoCloseMonitoring()
        if runOCRImmediately {
            runOCR()
        }
    }

    func windowWillClose(_ notification: Notification) {
        stopAutoCloseMonitoring()
        closeColorPanel()
        onClose(id)
    }

    func close() {
        stopAutoCloseMonitoring()
        closeColorPanel()
        panel?.close()
    }

    private func makeContentView(size: NSSize, toolbarHeight: CGFloat) -> NSView {
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))

        let toolbar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: size.width, height: toolbarHeight))
        toolbar.autoresizingMask = [.width, .maxYMargin]
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        contentView.addSubview(toolbar)

        var x: CGFloat = 12
        x = addToolbarButton(title: "文", symbolName: nil, iconColor: .systemRed, tooltip: "文字识别", action: #selector(runOCR), x: x, to: toolbar)
        x = addToolbarButton(title: "✎", symbolName: "pencil", iconColor: NSColor(calibratedRed: 0.95, green: 0.58, blue: 0.02, alpha: 1), tooltip: "画笔", action: #selector(selectPen), x: x, to: toolbar)
        x = addToolbarButton(title: "↗", symbolName: "arrow.up.right", iconColor: .systemBlue, tooltip: "箭头", action: #selector(selectArrow), x: x, to: toolbar)
        x = addToolbarButton(title: "⌖", symbolName: "pin.fill", iconColor: .systemGreen, tooltip: "钉图", action: #selector(pinImage), x: x, to: toolbar)
        x = addToolbarButton(title: "⧉", symbolName: "doc.on.doc", iconColor: .systemPurple, tooltip: "复制", action: #selector(copyImageAndClose), x: x, to: toolbar)
        x = addToolbarButton(title: "⇩", symbolName: "square.and.arrow.down", iconColor: .systemCyan, tooltip: "保存", action: #selector(saveImage), x: x, to: toolbar)
        _ = addToolbarButton(title: "×", symbolName: "xmark", iconColor: .systemPink, tooltip: "关闭", action: #selector(closeFromButton), x: x, to: toolbar)

        let imageView = ScreenshotPreviewImageView(frame: NSRect(x: 0, y: toolbarHeight, width: size.width, height: size.height - toolbarHeight), image: image)
        imageView.autoresizingMask = [.width, .height]
        imageView.onDoubleClick = { [weak self] in
            self?.copyImageAndClose()
        }
        imageView.tool = activeTool
        imageView.color = selectedColor
        contentView.addSubview(imageView)
        self.imageView = imageView

        return contentView
    }

    private func addToolbarButton(
        title: String,
        symbolName: String?,
        iconColor: NSColor,
        tooltip: String,
        action: Selector,
        x: CGFloat,
        to toolbar: NSView,
        configure: ((NSButton) -> Void)? = nil
    ) -> CGFloat {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .regularSquare
        button.frame = NSRect(x: x, y: 6, width: 30, height: 30)
        button.toolTip = tooltip
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.masksToBounds = true
        button.layer?.borderWidth = 1.5
        button.layer?.borderColor = iconColor.withAlphaComponent(0.95).previewCGColor
        button.layer?.backgroundColor = iconColor.withAlphaComponent(0.18).previewCGColor
        button.contentTintColor = iconColor
        if let symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip) {
            let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .bold)
            button.image = image.withSymbolConfiguration(configuration)
            button.imagePosition = .imageOnly
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: iconColor
            ]
            button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        }
        configure?(button)
        toolbar.addSubview(button)
        return x + 36
    }

    @objc private func runOCR() {
        closeColorPanel()
        do {
            let text = try ocrService.recognizeText(in: cgImage, mode: .chineseAndEnglish)
            let displayText = text.isEmpty ? "未识别到文字。" : text
            let textPanel = OCRTextPanelController(text: displayText) { [weak self] in
                self?.textPanel = nil
            }
            self.textPanel = textPanel
            textPanel.show(near: panel?.frame)
        } catch {
            showAlert(title: "文字识别失败", message: error.localizedDescription)
        }
    }

    @objc private func pinImage() {
        closeColorPanel()
        pinnedImageController.pin(image: annotatedImage(), near: panel?.frame)
        close()
    }

    @objc private func copyImageAndClose() {
        closeColorPanel()
        NSPasteboard.general.copy(image: annotatedImage())
        close()
    }

    @objc private func saveImage() {
        closeColorPanel()
        let panel = NSSavePanel()
        panel.title = "保存截图"
        panel.nameFieldStringValue = "截图.png"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = annotatedImage().pngData else {
                showAlert(title: "保存失败", message: "无法将截图编码为 PNG。")
                return
            }
            try data.write(to: url, options: .atomic)
        } catch {
            showAlert(title: "保存失败", message: error.localizedDescription)
        }
    }

    @objc private func selectPen() {
        showColorPalette(for: .pen)
    }

    @objc private func selectArrow() {
        showColorPalette(for: .arrow)
    }

    @objc private func chooseColor(_ sender: NSButton) {
        guard colors.indices.contains(sender.tag) else { return }
        selectedColor = colors[sender.tag].color
        activeTool = paletteTool
        imageView?.tool = activeTool
        imageView?.color = selectedColor
        closeColorPanel()
    }

    @objc private func closeFromButton() {
        close()
    }

    private func annotatedImage() -> NSImage {
        imageView?.annotatedImage() ?? image
    }

    private func showColorPalette(for tool: AnnotationTool) {
        paletteTool = tool
        closeColorPanel()

        let swatchSize: CGFloat = 24
        let gap: CGFloat = 8
        let padding: CGFloat = 10
        let panelSize = NSSize(
            width: padding * 2 + swatchSize * 5 + gap * 4,
            height: padding * 2 + swatchSize * 2 + gap
        )
        let screenFrame = screenFrameForPalette()
        let parentFrame = panel?.frame ?? NSRect(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        var origin = CGPoint(x: parentFrame.minX + 48, y: parentFrame.minY + 46)
        if origin.y + panelSize.height > screenFrame.maxY {
            origin.y = parentFrame.maxY - panelSize.height - 8
        }
        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - panelSize.width - 8)
        origin.y = min(max(origin.y, screenFrame.minY + 8), screenFrame.maxY - panelSize.height - 8)

        let colorPanel = NSPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        colorPanel.isReleasedWhenClosed = false
        colorPanel.isOpaque = false
        colorPanel.backgroundColor = .clear
        colorPanel.level = .floating
        colorPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        colorPanel.contentView = makeColorPaletteView(size: panelSize, swatchSize: swatchSize, gap: gap, padding: padding)
        colorPanel.orderFrontRegardless()
        self.colorPanel = colorPanel
    }

    private func makeColorPaletteView(size: NSSize, swatchSize: CGFloat, gap: CGFloat, padding: CGFloat) -> NSView {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        for (index, annotationColor) in colors.enumerated() {
            let column = index % 5
            let row = index / 5
            let button = NSButton(frame: NSRect(
                x: padding + CGFloat(column) * (swatchSize + gap),
                y: padding + CGFloat(1 - row) * (swatchSize + gap),
                width: swatchSize,
                height: swatchSize
            ))
            button.title = ""
            button.isBordered = false
            button.target = self
            button.action = #selector(chooseColor)
            button.tag = index
            button.toolTip = "\(annotationColor.name)\(paletteTool == .pen ? "画笔" : "箭头")"
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.backgroundColor = annotationColor.color.previewCGColor
            button.layer?.borderColor = annotationColor.color == .white
                ? NSColor.separatorColor.cgColor
                : NSColor.white.withAlphaComponent(0.35).cgColor
            button.layer?.borderWidth = annotationColor.color == selectedColor ? 2 : 1
            background.addSubview(button)
        }

        return background
    }

    private func closeColorPanel() {
        colorPanel?.close()
        colorPanel = nil
    }

    private func screenFrameForPalette() -> NSRect {
        if let frame = panel?.frame,
           let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.visibleFrame {
            return screenFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func beginAutoCloseMonitoring() {
        stopAutoCloseMonitoring()
        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func stopAutoCloseMonitoring() {
        if let appResignObserver {
            NotificationCenter.default.removeObserver(appResignObserver)
            self.appResignObserver = nil
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

enum AnnotationTool {
    case none
    case pen
    case arrow
}

private struct AnnotationColor {
    let name: String
    let color: NSColor
}

private enum ScreenshotAnnotation {
    case pen(points: [CGPoint], color: NSColor, lineWidth: CGFloat)
    case arrow(start: CGPoint, end: CGPoint, color: NSColor, lineWidth: CGFloat)
}

private final class ScreenshotPreviewImageView: NSView {
    private let image: NSImage
    var onDoubleClick: (() -> Void)?
    var tool: AnnotationTool = .none {
        didSet {
            NSCursor.crosshair.set()
        }
    }
    var color: NSColor = .systemRed

    private var annotations: [ScreenshotAnnotation] = []
    private var currentPenPoints: [CGPoint] = []
    private var currentArrowStart: CGPoint?
    private var currentArrowEnd: CGPoint?
    private var imageRect: NSRect = .zero

    init(frame frameRect: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()

        let drawRect = image.size.scaledToFit(bounds.size, allowUpscale: true).centered(in: bounds)
        imageRect = drawRect
        image.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        drawAnnotations(in: drawRect)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }

        guard let point = imagePoint(for: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }

        switch tool {
        case .none:
            super.mouseDown(with: event)
        case .pen:
            currentPenPoints = [point]
        case .arrow:
            currentArrowStart = point
            currentArrowEnd = point
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let point = imagePoint(for: convert(event.locationInWindow, from: nil)) else { return }

        switch tool {
        case .none:
            super.mouseDragged(with: event)
        case .pen:
            currentPenPoints.append(point)
            needsDisplay = true
        case .arrow:
            currentArrowEnd = point
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .none:
            super.mouseUp(with: event)
        case .pen:
            if currentPenPoints.count > 1 {
                annotations.append(.pen(points: currentPenPoints, color: color, lineWidth: 4))
            }
            currentPenPoints = []
            needsDisplay = true
        case .arrow:
            if let start = currentArrowStart, let end = currentArrowEnd, start.distance(to: end) > 6 {
                annotations.append(.arrow(start: start, end: end, color: color, lineWidth: 4))
            }
            currentArrowStart = nil
            currentArrowEnd = nil
            needsDisplay = true
        }
    }

    func annotatedImage() -> NSImage {
        let rendered = NSImage(size: image.size)
        rendered.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        drawAnnotationsForImageExport(in: NSRect(origin: .zero, size: image.size))
        rendered.unlockFocus()
        return rendered
    }

    private func imagePoint(for viewPoint: CGPoint) -> CGPoint? {
        guard imageRect.contains(viewPoint), imageRect.width > 0, imageRect.height > 0 else { return nil }
        return CGPoint(
            x: (viewPoint.x - imageRect.minX) / imageRect.width * image.size.width,
            y: (viewPoint.y - imageRect.minY) / imageRect.height * image.size.height
        )
    }

    private func viewPoint(for imagePoint: CGPoint, in drawRect: NSRect) -> CGPoint {
        CGPoint(
            x: drawRect.minX + imagePoint.x / image.size.width * drawRect.width,
            y: drawRect.minY + imagePoint.y / image.size.height * drawRect.height
        )
    }

    private func exportPoint(for imagePoint: CGPoint, in rect: NSRect) -> CGPoint {
        CGPoint(
            x: rect.minX + imagePoint.x / image.size.width * rect.width,
            y: rect.maxY - imagePoint.y / image.size.height * rect.height
        )
    }

    private func drawAnnotations(in drawRect: NSRect) {
        for annotation in annotations {
            draw(annotation, in: drawRect, exportMode: false)
        }
        if currentPenPoints.count > 1 {
            draw(.pen(points: currentPenPoints, color: color, lineWidth: 4), in: drawRect, exportMode: false)
        }
        if let start = currentArrowStart, let end = currentArrowEnd {
            draw(.arrow(start: start, end: end, color: color, lineWidth: 4), in: drawRect, exportMode: false)
        }
    }

    private func drawAnnotationsForImageExport(in rect: NSRect) {
        for annotation in annotations {
            draw(annotation, in: rect, exportMode: true)
        }
    }

    private func draw(_ annotation: ScreenshotAnnotation, in rect: NSRect, exportMode: Bool) {
        switch annotation {
        case let .pen(points, color, lineWidth):
            guard points.count > 1 else { return }
            color.setStroke()
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: mappedPoint(points[0], in: rect, exportMode: exportMode))
            for point in points.dropFirst() {
                path.line(to: mappedPoint(point, in: rect, exportMode: exportMode))
            }
            path.stroke()
        case let .arrow(start, end, color, lineWidth):
            color.setStroke()
            color.setFill()
            let mappedStart = mappedPoint(start, in: rect, exportMode: exportMode)
            let mappedEnd = mappedPoint(end, in: rect, exportMode: exportMode)
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.move(to: mappedStart)
            path.line(to: mappedEnd)
            path.stroke()
            drawArrowHead(from: mappedStart, to: mappedEnd, color: color, lineWidth: lineWidth)
        }
    }

    private func mappedPoint(_ point: CGPoint, in rect: NSRect, exportMode: Bool) -> CGPoint {
        exportMode ? exportPoint(for: point, in: rect) : viewPoint(for: point, in: rect)
    }

    private func drawArrowHead(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(14, lineWidth * 5)
        let wingAngle = CGFloat.pi / 7
        let left = CGPoint(
            x: end.x - cos(angle - wingAngle) * length,
            y: end.y - sin(angle - wingAngle) * length
        )
        let right = CGPoint(
            x: end.x - cos(angle + wingAngle) * length,
            y: end.y - sin(angle + wingAngle) * length
        )
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: left)
        head.line(to: right)
        head.close()
        color.setFill()
        head.fill()
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(x - point.x, y - point.y)
    }
}

@MainActor
final class OCRTextPanelController: NSObject, NSWindowDelegate {
    private let text: String
    private let onClose: () -> Void
    private var panel: NSPanel?
    private weak var textView: NSTextView?

    init(text: String, onClose: @escaping () -> Void) {
        self.text = text
        self.onClose = onClose
    }

    func show(near parentFrame: NSRect?) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: 480, height: 320)
        let origin = CGPoint(
            x: min(max((parentFrame?.maxX ?? screenFrame.midX) + 12, screenFrame.minX + 16), screenFrame.maxX - size.width - 16),
            y: min(max(parentFrame?.minY ?? screenFrame.midY, screenFrame.minY + 16), screenFrame.maxY - size.height - 16)
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "识别文字"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.delegate = self
        panel.contentView = makeContentView(size: size)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    private func makeContentView(size: NSSize) -> NSView {
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        let buttonHeight: CGFloat = 44

        let scrollView = NSScrollView(frame: NSRect(x: 12, y: buttonHeight, width: size.width - 24, height: size.height - buttonHeight - 12))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 13)
        scrollView.documentView = textView
        self.textView = textView
        contentView.addSubview(scrollView)

        let copyButton = NSButton(title: "复制文字", target: self, action: #selector(copyText))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: 12, y: 8, width: 104, height: 28)
        contentView.addSubview(copyButton)

        return contentView
    }

    @objc private func copyText() {
        let copiedText = textView?.string ?? text
        ClipboardTranslationSuppression.suppress(text: copiedText)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)
        panel?.close()
    }
}

private extension NSSize {
    func scaledToFit(_ maxSize: NSSize, allowUpscale: Bool) -> NSSize {
        guard width > 0, height > 0 else { return NSSize(width: 1, height: 1) }
        var scale = min(maxSize.width / width, maxSize.height / height)
        if !allowUpscale {
            scale = min(scale, 1)
        }
        scale = max(scale, 0.1)
        return NSSize(width: width * scale, height: height * scale)
    }
}

private extension NSSize {
    func centered(in rect: NSRect) -> NSRect {
        NSRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension NSColor {
    var previewCGColor: CGColor {
        usingColorSpace(.deviceRGB)?.cgColor ?? cgColor
    }
}
