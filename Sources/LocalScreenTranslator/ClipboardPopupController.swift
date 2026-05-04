import AppKit

final class ClipboardPopupController {
    private var window: NSPanel?
    private var closeTask: DispatchWorkItem?

    func show(source: String, translation: String) {
        closeTask?.cancel()
        window?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = PopupView(frame: panel.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 420, height: 180), source: source, translation: translation)

        let mouse = NSEvent.mouseLocation
        let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(mouse.x + 16, screenFrame.minX + 12), screenFrame.maxX - 432)
        let y = min(max(mouse.y - 90, screenFrame.minY + 12), screenFrame.maxY - 192)
        panel.setFrameOrigin(CGPoint(x: x, y: y))
        panel.orderFrontRegardless()
        window = panel

        let task = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        }
        closeTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
    }
}

private final class PopupView: NSView {
    private let source: String
    private let translation: String

    init(frame frameRect: NSRect, source: String, translation: String) {
        self.source = source
        self.translation = translation
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.8).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawText("复制内容", at: CGRect(x: 18, y: bounds.height - 30, width: bounds.width - 36, height: 18), size: 11, color: .secondaryLabelColor, weight: .medium)
        drawText(source, at: CGRect(x: 18, y: bounds.height - 78, width: bounds.width - 36, height: 40), size: 13, color: .labelColor, weight: .regular)
        drawText("中文翻译", at: CGRect(x: 18, y: bounds.height - 104, width: bounds.width - 36, height: 18), size: 11, color: .secondaryLabelColor, weight: .medium)
        drawText(translation, at: CGRect(x: 18, y: 18, width: bounds.width - 36, height: 68), size: 15, color: .labelColor, weight: .semibold)
    }

    private func drawText(_ text: String, at rect: CGRect, size: CGFloat, color: NSColor, weight: NSFont.Weight) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
    }
}
