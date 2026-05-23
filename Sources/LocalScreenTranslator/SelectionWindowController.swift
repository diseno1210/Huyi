import AppKit
import CoreGraphics

enum SelectionAction: Equatable {
    case preview
    case annotatePen
    case annotateArrow
    case ocr
    case pin
    case copy
    case save
}

final class SelectionWindowController {
    private static var activeController: SelectionWindowController?

    private let instruction: String
    private let completion: (SelectionAction, CGRect) -> Void
    private var window: SelectionWindow?

    private init(instruction: String, completion: @escaping (SelectionAction, CGRect) -> Void) {
        self.instruction = instruction
        self.completion = completion
    }

    static func beginSelection(
        instruction: String = "拖拽选择区域，按 Esc 取消",
        candidateRects: [CGRect] = [],
        allowsAdjustment: Bool = false,
        backgroundImage: NSImage? = nil,
        completion: @escaping (CGRect) -> Void
    ) {
        beginSelection(
            instruction: instruction,
            candidateRects: candidateRects,
            allowsAdjustment: allowsAdjustment,
            backgroundImage: backgroundImage,
            showsActionToolbar: false
        ) { _, rect in
            completion(rect)
        }
    }

    static func beginSelection(
        instruction: String = "拖拽选择区域，按 Esc 取消",
        candidateRects: [CGRect] = [],
        allowsAdjustment: Bool = false,
        backgroundImage: NSImage? = nil,
        showsActionToolbar: Bool,
        completion: @escaping (SelectionAction, CGRect) -> Void
    ) {
        activeController?.cancel()
        let controller = SelectionWindowController(instruction: instruction, completion: completion)
        activeController = controller
        controller.show(
            candidateRects: candidateRects,
            allowsAdjustment: allowsAdjustment,
            backgroundImage: backgroundImage,
            showsActionToolbar: showsActionToolbar
        )
    }

    private func show(
        candidateRects: [CGRect],
        allowsAdjustment: Bool,
        backgroundImage: NSImage?,
        showsActionToolbar: Bool
    ) {
        let frame = NSScreen.allScreensFrame
        let window = SelectionWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = SelectionView(
            frame: NSRect(origin: .zero, size: frame.size),
            instruction: instruction,
            candidates: candidateRects
                .map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
                .filter { $0.width >= 8 && $0.height >= 8 },
            allowsAdjustment: allowsAdjustment,
            backgroundImage: backgroundImage,
            showsActionToolbar: showsActionToolbar
        )
        view.onCancel = { [weak self] in self?.cancel() }
        view.onComplete = { [weak self] action, rectInWindow in
            guard let self, let window = self.window else { return }
            let screenRect = CGRect(
                x: window.frame.minX + rectInWindow.minX,
                y: window.frame.minY + rectInWindow.minY,
                width: rectInWindow.width,
                height: rectInWindow.height
            )
            self.finish(action: action, rect: screenRect)
        }

        window.contentView = view
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        window.acceptsMouseMovedEvents = true
        NSCursor.crosshair.set()
        self.window = window
    }

    private func finish(action: SelectionAction, rect: CGRect) {
        close()
        completion(action, rect)
    }

    private func cancel() {
        close()
    }

    private func close() {
        NSCursor.arrow.set()
        window?.orderOut(nil)
        window = nil
        Self.activeController = nil
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class SelectionView: NSView {
    var onComplete: ((SelectionAction, CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let instruction: String
    private let candidates: [SelectionCandidate]
    private let allowsAdjustment: Bool
    private let backgroundImage: NSImage?
    private let showsActionToolbar: Bool
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var selectedRect: CGRect?
    private var hoverCandidate: SelectionCandidate?
    private var resizeHandle: ResizeHandle?
    private var resizeStartRect: CGRect?
    private var liveResizeRect: CGRect?
    private var moveStartPoint: CGPoint?
    private var moveStartRect: CGRect?
    private var actionToolbar: NSVisualEffectView?

    init(
        frame frameRect: NSRect,
        instruction: String,
        candidates: [CGRect],
        allowsAdjustment: Bool,
        backgroundImage: NSImage?,
        showsActionToolbar: Bool
    ) {
        self.instruction = instruction
        self.candidates = candidates.map(SelectionCandidate.init(rect:))
        self.allowsAdjustment = allowsAdjustment
        self.backgroundImage = backgroundImage
        self.showsActionToolbar = showsActionToolbar
        super.init(frame: frameRect)
        if showsActionToolbar {
            installActionToolbar()
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawFrozenBackground()

        guard let rect = activeRect else {
            NSColor.black.withAlphaComponent(0.24).setFill()
            bounds.fill()
            drawInstruction(at: CGPoint(x: 18, y: bounds.maxY - 42), text: instruction)
            return
        }

        drawMask(outside: rect)
        drawSelection(rect)

        if allowsAdjustment, startPoint == nil || selectedRect != nil {
            drawHandles(for: rect)
        }

        drawDimensionBadge(for: rect)
        if showsActionToolbar {
            updateActionToolbar(for: rect)
        }
    }

    private func drawFrozenBackground() {
        guard let backgroundImage else { return }
        backgroundImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
    }

    override func mouseMoved(with event: NSEvent) {
        guard startPoint == nil, resizeHandle == nil, moveStartPoint == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        let candidate = candidate(at: point)
        if hoverCandidate?.id != candidate?.id {
            hoverCandidate = candidate
            needsDisplay = true
        }
        if let selectedRect, selectedRect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if showsActionToolbar,
           event.clickCount >= 2,
           let rect = selectedRect,
           rect.contains(point) {
            onComplete?(.copy, rect)
            return
        }

        if allowsAdjustment, let rect = selectedRect, let handle = handle(at: point, in: rect) {
            resizeHandle = handle
            resizeStartRect = rect
            liveResizeRect = rect
            needsDisplay = true
            return
        }

        if showsActionToolbar, let rect = selectedRect, rect.contains(point) {
            moveStartPoint = point
            moveStartRect = rect
            actionToolbar?.isHidden = true
            NSCursor.closedHand.set()
            return
        }

        if let candidate = candidate(at: point) {
            hoverCandidate = candidate
            if allowsAdjustment, let handle = handle(at: point, in: candidate.rect) {
                resizeHandle = handle
                resizeStartRect = candidate.rect
                liveResizeRect = candidate.rect
                needsDisplay = true
                return
            }
            if !showsActionToolbar {
                onComplete?(.preview, candidate.rect)
                return
            }
            selectedRect = candidate.rect
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        startPoint = point
        currentPoint = startPoint
        selectedRect = nil
        hoverCandidate = nil
        actionToolbar?.isHidden = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let moveStartPoint, let moveStartRect {
            let movedRect = moveStartRect
                .offsetBy(dx: point.x - moveStartPoint.x, dy: point.y - moveStartPoint.y)
                .constrained(to: bounds)
                .integral
            selectedRect = movedRect
            needsDisplay = true
            return
        }

        if let resizeHandle, let resizeStartRect {
            liveResizeRect = resizeHandle
                .resized(resizeStartRect, to: point)
                .normalized(minSize: 24)
                .constrained(to: bounds)
                .integral
            needsDisplay = true
            return
        }

        currentPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if moveStartPoint != nil {
            clearMoveState()
            NSCursor.openHand.set()
            needsDisplay = true
            return
        }

        if resizeHandle != nil {
            let rect = (liveResizeRect ?? resizeStartRect ?? .zero).standardized
            clearResizeState()
            guard rect.width >= 8, rect.height >= 8 else { return }
            if !showsActionToolbar {
                onComplete?(.preview, rect)
                return
            }
            selectedRect = rect
            needsDisplay = true
            return
        }

        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width >= 8, rect.height >= 8 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }
        if !showsActionToolbar {
            onComplete?(.preview, rect)
            return
        }
        selectedRect = rect.integral
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var activeRect: CGRect? {
        selectionRect ?? liveResizeRect ?? selectedRect ?? hoverCandidate?.rect
    }

    private func candidate(at point: CGPoint) -> SelectionCandidate? {
        let containing = candidates.filter { $0.rect.contains(point) }
        if let candidate = containing.min(by: { $0.rect.area < $1.rect.area }) {
            return candidate
        }
        return candidates
            .filter { $0.hoverRect.contains(point) }
            .min { $0.rect.area < $1.rect.area }
    }

    private func handle(at point: CGPoint, in rect: CGRect) -> ResizeHandle? {
        if let handle = ResizeHandle.allCases.first(where: { $0.hitRect(in: rect).contains(point) }) {
            return handle
        }

        let edgeHitWidth: CGFloat = 8
        let nearLeft = abs(point.x - rect.minX) <= edgeHitWidth && point.y >= rect.minY && point.y <= rect.maxY
        let nearRight = abs(point.x - rect.maxX) <= edgeHitWidth && point.y >= rect.minY && point.y <= rect.maxY
        let nearBottom = abs(point.y - rect.minY) <= edgeHitWidth && point.x >= rect.minX && point.x <= rect.maxX
        let nearTop = abs(point.y - rect.maxY) <= edgeHitWidth && point.x >= rect.minX && point.x <= rect.maxX

        if nearLeft && nearTop { return .topLeft }
        if nearRight && nearTop { return .topRight }
        if nearRight && nearBottom { return .bottomRight }
        if nearLeft && nearBottom { return .bottomLeft }
        if nearTop { return .top }
        if nearRight { return .right }
        if nearBottom { return .bottom }
        if nearLeft { return .left }
        return nil
    }

    private func clearResizeState() {
        resizeHandle = nil
        resizeStartRect = nil
        liveResizeRect = nil
    }

    private func clearMoveState() {
        moveStartPoint = nil
        moveStartRect = nil
    }

    private func drawHandles(for rect: CGRect) {
        for handle in ResizeHandle.allCases {
            let dot = handle.handleRect(in: rect)
            let path = NSBezierPath(ovalIn: dot)
            NSColor.white.setFill()
            path.fill()
            NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 1).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawMask(outside rect: CGRect) {
        NSColor.black.withAlphaComponent(0.54).setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, rect.minY - bounds.minY)).fill()
        NSRect(x: bounds.minX, y: rect.maxY, width: bounds.width, height: max(0, bounds.maxY - rect.maxY)).fill()
        NSRect(x: bounds.minX, y: rect.minY, width: max(0, rect.minX - bounds.minX), height: rect.height).fill()
        NSRect(x: rect.maxX, y: rect.minY, width: max(0, bounds.maxX - rect.maxX), height: rect.height).fill()
    }

    private func drawSelection(_ rect: CGRect) {
        let fillPath = NSBezierPath(rect: rect)
        NSColor.systemBlue.withAlphaComponent(0.10).setFill()
        fillPath.fill()

        let path = NSBezierPath(rect: rect)
        NSColor(calibratedRed: 0.16, green: 0.51, blue: 1, alpha: 1).setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    private func drawDimensionBadge(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height)) PX"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        var badge = CGRect(
            x: rect.minX,
            y: min(rect.maxY + 10, bounds.maxY - size.height - 18),
            width: size.width + 18,
            height: size.height + 10
        )
        badge.origin.x = min(max(badge.minX, bounds.minX + 12), bounds.maxX - badge.width - 12)
        let path = NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.68).setFill()
        path.fill()
        text.draw(at: CGPoint(x: badge.minX + 9, y: badge.minY + 5), withAttributes: attrs)
    }

    private func drawInstruction(at point: CGPoint, text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55)
        ]
        text.draw(at: point, withAttributes: attrs)
    }

    private func installActionToolbar() {
        let toolbarHeight: CGFloat = 42
        let toolbarWidth: CGFloat = 264
        let toolbar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight))
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.isHidden = true
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 0
        toolbar.layer?.masksToBounds = true

        var x: CGFloat = 12
        x = addToolbarButton(
            title: "文",
            symbolName: nil,
            iconColor: .systemRed,
            tooltip: "文字识别",
            tag: SelectionToolbarTag.ocr.rawValue,
            x: x,
            to: toolbar
        )
        x = addToolbarButton(
            title: "✎",
            symbolName: "pencil",
            iconColor: NSColor(calibratedRed: 0.95, green: 0.58, blue: 0.02, alpha: 1),
            tooltip: "画笔",
            tag: SelectionToolbarTag.pen.rawValue,
            x: x,
            to: toolbar
        )
        x = addToolbarButton(
            title: "↗",
            symbolName: "arrow.up.right",
            iconColor: .systemBlue,
            tooltip: "箭头",
            tag: SelectionToolbarTag.arrow.rawValue,
            x: x,
            to: toolbar
        )
        x = addToolbarButton(
            title: "⌖",
            symbolName: "pin.fill",
            iconColor: .systemGreen,
            tooltip: "钉图",
            tag: SelectionToolbarTag.pin.rawValue,
            x: x,
            to: toolbar
        )
        x = addToolbarButton(
            title: "⧉",
            symbolName: "doc.on.doc",
            iconColor: .systemPurple,
            tooltip: "复制",
            tag: SelectionToolbarTag.copy.rawValue,
            x: x,
            to: toolbar
        )
        x = addToolbarButton(
            title: "⇩",
            symbolName: "square.and.arrow.down",
            iconColor: .systemCyan,
            tooltip: "保存",
            tag: SelectionToolbarTag.save.rawValue,
            x: x,
            to: toolbar
        )
        _ = addToolbarButton(
            title: "×",
            symbolName: "xmark",
            iconColor: .systemPink,
            tooltip: "关闭",
            tag: SelectionToolbarTag.cancel.rawValue,
            x: x,
            to: toolbar
        )

        addSubview(toolbar)
        actionToolbar = toolbar
    }

    private func addToolbarButton(
        title: String,
        symbolName: String?,
        iconColor: NSColor,
        tooltip: String,
        tag: Int,
        x: CGFloat,
        to toolbar: NSView
    ) -> CGFloat {
        let button = NSButton(title: title, target: self, action: #selector(actionToolbarButtonPressed(_:)))
        button.bezelStyle = .regularSquare
        button.frame = NSRect(x: x, y: 6, width: 30, height: 30)
        button.toolTip = tooltip
        button.tag = tag
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
        toolbar.addSubview(button)
        return x + 36
    }

    private func updateActionToolbar(for rect: CGRect) {
        guard let actionToolbar, selectedRect != nil, startPoint == nil, moveStartPoint == nil else {
            actionToolbar?.isHidden = true
            return
        }

        var origin = CGPoint(x: rect.minX, y: rect.minY - actionToolbar.frame.height - 8)
        if origin.y < bounds.minY + 12 {
            origin.y = min(rect.maxY + 8, bounds.maxY - actionToolbar.frame.height - 12)
        }
        origin.x = min(max(origin.x, bounds.minX + 12), bounds.maxX - actionToolbar.frame.width - 12)
        actionToolbar.frame.origin = origin
        actionToolbar.isHidden = false
    }

    @objc private func actionToolbarButtonPressed(_ sender: NSButton) {
        guard let rect = selectedRect,
              let tag = SelectionToolbarTag(rawValue: sender.tag) else { return }

        switch tag {
        case .ocr:
            onComplete?(.ocr, rect)
        case .pen:
            onComplete?(.annotatePen, rect)
        case .arrow:
            onComplete?(.annotateArrow, rect)
        case .pin:
            onComplete?(.pin, rect)
        case .copy:
            onComplete?(.copy, rect)
        case .save:
            onComplete?(.save, rect)
        case .cancel:
            onCancel?()
        }
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }
}

private struct SelectionCandidate: Equatable {
    let id = UUID()
    let rect: CGRect

    var hoverRect: CGRect {
        rect.insetBy(dx: -8, dy: -8)
    }
}

private enum SelectionToolbarTag: Int {
    case ocr = 1
    case pen
    case arrow
    case pin
    case copy
    case save
    case cancel
}

private enum ResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left

    func handleRect(in rect: CGRect) -> CGRect {
        let size: CGFloat = 8
        let center: CGPoint
        switch self {
        case .topLeft:
            center = CGPoint(x: rect.minX, y: rect.maxY)
        case .top:
            center = CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight:
            center = CGPoint(x: rect.maxX, y: rect.maxY)
        case .right:
            center = CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight:
            center = CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom:
            center = CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft:
            center = CGPoint(x: rect.minX, y: rect.minY)
        case .left:
            center = CGPoint(x: rect.minX, y: rect.midY)
        }
        return CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    }

    func hitRect(in rect: CGRect) -> CGRect {
        handleRect(in: rect).insetBy(dx: -8, dy: -8)
    }

    func resized(_ rect: CGRect, to point: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch self {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .top:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .right:
            maxX = point.x
        case .bottomRight:
            maxX = point.x
            minY = point.y
        case .bottom:
            minY = point.y
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .left:
            minX = point.x
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }

    func normalized(minSize: CGFloat) -> CGRect {
        var rect = standardized
        rect.size.width = max(rect.width, minSize)
        rect.size.height = max(rect.height, minSize)
        return rect
    }

    func constrained(to bounds: CGRect) -> CGRect {
        var rect = self
        if rect.width > bounds.width { rect.size.width = bounds.width }
        if rect.height > bounds.height { rect.size.height = bounds.height }
        if rect.minX < bounds.minX { rect.origin.x = bounds.minX }
        if rect.minY < bounds.minY { rect.origin.y = bounds.minY }
        if rect.maxX > bounds.maxX { rect.origin.x = bounds.maxX - rect.width }
        if rect.maxY > bounds.maxY { rect.origin.y = bounds.maxY - rect.height }
        return rect
    }
}

extension NSScreen {
    static var allScreensFrame: CGRect {
        screens.map(\.frame).reduce(.null) { $0.union($1) }
    }
}
