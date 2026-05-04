import AppKit

struct TranslationOverlayItem {
    let sourceText: String
    let targetText: String
    let rect: CGRect
}

final class TranslationOverlayController {
    private var window: NSWindow?
    private var eventMonitors: [Any] = []

    func show(items: [TranslationOverlayItem]) {
        clear()
        guard !items.isEmpty else { return }

        let frame = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let window = TranslationOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = TranslationOverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            screenOrigin: frame.origin,
            items: items
        )
        window.orderFrontRegardless()
        self.window = window
        beginDismissMonitoring()
    }

    func clear() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        window?.orderOut(nil)
        window = nil
    }

    private func beginDismissMonitoring() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.clear()
            return event
        }
        if let localMonitor {
            eventMonitors.append(localMonitor)
        }

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.clear()
            }
        }
        if let globalMonitor {
            eventMonitors.append(globalMonitor)
        }
    }
}

private final class TranslationOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class TranslationOverlayView: NSView {
    private let screenOrigin: CGPoint
    private let items: [TranslationOverlayItem]

    init(frame frameRect: NSRect, screenOrigin: CGPoint, items: [TranslationOverlayItem]) {
        self.screenOrigin = screenOrigin
        self.items = items
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for item in items {
            draw(item)
        }
    }

    private func draw(_ item: TranslationOverlayItem) {
        var rect = item.rect.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        rect = rect.insetBy(dx: -5, dy: -3)
        rect.size.width = max(rect.width, 80)
        rect.size.height = max(rect.height, 24)

        let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.72).setFill()
        backgroundPath.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byWordWrapping

        let fontSize = fittedFontSize(for: item.targetText, in: rect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let textRect = rect.insetBy(dx: 5, dy: 3)
        item.targetText.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
    }

    private func fittedFontSize(for text: String, in rect: CGRect) -> CGFloat {
        var size = min(max(rect.height * 0.52, 10), 18)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        while size > 8 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .paragraphStyle: paragraph
            ]
            let measured = text.boundingRect(
                with: CGSize(width: rect.width - 10, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            if measured.height <= rect.height - 4 {
                return size
            }
            size -= 1
        }
        return size
    }
}
