import AppKit

@MainActor
final class PinnedImageController {
    private var pins: [UUID: PinnedImageWindowController] = [:]

    func pin(image: NSImage, near parentFrame: NSRect?) {
        let id = UUID()
        let controller = PinnedImageWindowController(id: id, image: image) { [weak self] id in
            self?.pins[id] = nil
        }
        pins[id] = controller
        controller.show(near: parentFrame)
    }
}

@MainActor
private final class PinnedImageWindowController: NSObject, NSWindowDelegate {
    private let id: UUID
    private let image: NSImage
    private let onClose: (UUID) -> Void
    private var panel: NSPanel?
    private var imageView: PinnedImageView?
    private var scale: CGFloat = 1

    private var originalSize: NSSize {
        let width = max(image.size.width, 1)
        let height = max(image.size.height, 1)
        return NSSize(width: width, height: height)
    }

    init(id: UUID, image: NSImage, onClose: @escaping (UUID) -> Void) {
        self.id = id
        self.image = image
        self.onClose = onClose
    }

    func show(near parentFrame: NSRect?) {
        let screenFrame = screenFrame(near: parentFrame)
        scale = initialScale(in: screenFrame)
        let size = windowSize(for: scale)
        let origin = originForInitialWindow(size: size, screenFrame: screenFrame, parentFrame: parentFrame)

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.delegate = self

        let imageView = PinnedImageView(frame: NSRect(origin: .zero, size: size), image: image)
        imageView.autoresizingMask = [.width, .height]
        imageView.onScroll = { [weak self] deltaY in
            self?.adjustScale(deltaY: deltaY)
        }
        imageView.onCopy = { [weak self] in
            self?.copyImage()
        }
        imageView.onDestroy = { [weak self] in
            self?.panel?.close()
        }
        panel.contentView = imageView
        panel.orderFrontRegardless()

        self.panel = panel
        self.imageView = imageView
    }

    func windowWillClose(_ notification: Notification) {
        onClose(id)
    }

    private func adjustScale(deltaY: CGFloat) {
        let zoomFactor: CGFloat = deltaY > 0 ? 1.08 : 0.92
        let nextScale = min(max(scale * zoomFactor, 0.25), 4)
        guard abs(nextScale - scale) > 0.001, let panel else { return }

        let frame = panel.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        scale = nextScale
        let nextSize = windowSize(for: scale)
        let nextFrame = NSRect(
            x: center.x - nextSize.width / 2,
            y: center.y - nextSize.height / 2,
            width: nextSize.width,
            height: nextSize.height
        )
        panel.setFrame(nextFrame, display: true)
        imageView?.needsDisplay = true
    }

    private func copyImage() {
        NSPasteboard.general.copy(image: image)
    }

    private func initialScale(in screenFrame: NSRect) -> CGFloat {
        let maxSize = NSSize(width: screenFrame.width * 0.7, height: screenFrame.height * 0.7)
        let scale = min(maxSize.width / originalSize.width, maxSize.height / originalSize.height, 1)
        return min(max(scale, 0.25), 4)
    }

    private func windowSize(for scale: CGFloat) -> NSSize {
        NSSize(width: originalSize.width * scale, height: originalSize.height * scale)
    }

    private func screenFrame(near parentFrame: NSRect?) -> NSRect {
        if let parentFrame,
           let screenFrame = NSScreen.screens.first(where: { $0.frame.intersects(parentFrame) })?.visibleFrame {
            return screenFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func originForInitialWindow(size: NSSize, screenFrame: NSRect, parentFrame: NSRect?) -> CGPoint {
        let baseX = (parentFrame?.minX ?? screenFrame.midX - size.width / 2) + 20
        let baseY = (parentFrame?.minY ?? screenFrame.midY - size.height / 2) - 20
        return CGPoint(
            x: min(max(baseX, screenFrame.minX + 12), screenFrame.maxX - size.width - 12),
            y: min(max(baseY, screenFrame.minY + 12), screenFrame.maxY - size.height - 12)
        )
    }
}

@MainActor
private final class PinnedImageView: NSView {
    let image: NSImage
    var onScroll: ((CGFloat) -> Void)?
    var onCopy: (() -> Void)?
    var onDestroy: (() -> Void)?

    init(frame frameRect: NSRect, image: NSImage) {
        self.image = image
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        shadow = NSShadow()
        shadow?.shadowBlurRadius = 18
        shadow?.shadowOffset = NSSize(width: 0, height: -4)
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.28)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.16).setFill()
        bounds.fill()
        image.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        guard delta != 0 else { return }
        onScroll?(delta)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "复制图片", action: #selector(copyImage), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let destroyItem = NSMenuItem(title: "关闭", action: #selector(destroy), keyEquivalent: "")
        destroyItem.target = self
        menu.addItem(destroyItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyImage() {
        onCopy?()
    }

    @objc private func destroy() {
        onDestroy?()
    }
}

extension NSPasteboard {
    func copy(image: NSImage) {
        clearContents()
        writeObjects([image])
    }
}
