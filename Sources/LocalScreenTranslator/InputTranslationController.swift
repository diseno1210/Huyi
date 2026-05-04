import AppKit

@MainActor
final class InputTranslationController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private let englishToChinese: TranslationCoordinator
    private let chineseToEnglish: TranslationCoordinator
    private var panel: NSPanel?
    private weak var inputView: NSTextView?
    private weak var directionLabel: NSTextField?
    private weak var resultView: NSTextView?
    private var latestResult = ""
    private var pendingWorkItem: DispatchWorkItem?
    private var eventMonitors: [Any] = []

    init(englishToChinese: TranslationCoordinator, chineseToEnglish: TranslationCoordinator) {
        self.englishToChinese = englishToChinese
        self.chineseToEnglish = chineseToEnglish
    }

    func toggle() {
        if panel != nil {
            close()
        } else {
            show()
        }
    }

    func show() {
        close()

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(width: 540, height: 330)
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(
            x: min(max(mouse.x - size.width / 2, screenFrame.minX + 18), screenFrame.maxX - size.width - 18),
            y: min(max(mouse.y - size.height / 2, screenFrame.minY + 18), screenFrame.maxY - size.height - 18)
        )

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "输入翻译"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = makeContentView(size: size)
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        self.panel = panel
        beginDismissMonitoring()
        inputView?.window?.makeFirstResponder(inputView)
    }

    func close() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    func windowWillClose(_ notification: Notification) {
        close()
    }

    func textDidChange(_ notification: Notification) {
        scheduleTranslation()
    }

    private func makeContentView(size: NSSize) -> NSView {
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        let padding: CGFloat = 14
        let buttonHeight: CGFloat = 42
        let inputHeight: CGFloat = 104
        let directionHeight: CGFloat = 22
        let inputY = size.height - inputHeight - padding
        let directionY = inputY - directionHeight - 6
        let resultY = buttonHeight
        let resultHeight = directionY - resultY - padding

        let inputScroll = makeTextScroll(frame: NSRect(
            x: padding,
            y: inputY,
            width: size.width - padding * 2,
            height: inputHeight
        ))
        let inputTextView = inputScroll.documentView as? NSTextView
        inputTextView?.delegate = self
        inputTextView?.isEditable = true
        inputTextView?.string = ""
        self.inputView = inputTextView
        contentView.addSubview(inputScroll)

        let directionLabel = NSTextField(labelWithString: InputTranslationDirection.emptyStatusText)
        directionLabel.frame = NSRect(x: padding + 2, y: directionY, width: size.width - padding * 2, height: directionHeight)
        directionLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        directionLabel.textColor = .secondaryLabelColor
        contentView.addSubview(directionLabel)
        self.directionLabel = directionLabel

        let resultScroll = makeTextScroll(frame: NSRect(
            x: padding,
            y: resultY,
            width: size.width - padding * 2,
            height: resultHeight
        ))
        let resultTextView = resultScroll.documentView as? NSTextView
        resultTextView?.isEditable = false
        resultTextView?.string = "请输入中文或英文。"
        self.resultView = resultTextView
        contentView.addSubview(resultScroll)

        let copyButton = NSButton(title: "复制译文", target: self, action: #selector(copyResult))
        copyButton.bezelStyle = .rounded
        copyButton.frame = NSRect(x: padding, y: 8, width: 100, height: 28)
        contentView.addSubview(copyButton)

        return contentView
    }

    private func makeTextScroll(frame: NSRect) -> NSScrollView {
        let scrollView = NSScrollView(frame: frame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        textView.autoresizingMask = [.width, .height]
        textView.font = NSFont.systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = textView
        return scrollView
    }

    private func scheduleTranslation() {
        pendingWorkItem?.cancel()

        let text = inputView?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            latestResult = ""
            directionLabel?.stringValue = InputTranslationDirection.emptyStatusText
            resultView?.string = "请输入中文或英文。"
            return
        }

        let direction = InputTranslationDirection.detect(text)
        directionLabel?.stringValue = direction.statusText
        resultView?.string = direction.loadingText
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.translate(text, direction: direction)
            }
        }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func translate(_ text: String, direction: InputTranslationDirection) async {
        do {
            let coordinator = direction == .chineseToEnglish ? chineseToEnglish : englishToChinese
            let result = try await coordinator.translate([text]).first ?? ""
            guard text == inputView?.string.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            latestResult = result
            directionLabel?.stringValue = direction.statusText
            resultView?.string = result
        } catch {
            latestResult = ""
            directionLabel?.stringValue = direction.statusText
            resultView?.string = error.localizedDescription
        }
    }

    @objc private func copyResult() {
        guard !latestResult.isEmpty else { return }
        ClipboardTranslationSuppression.suppress(text: latestResult)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestResult, forType: .string)
    }

    private func beginDismissMonitoring() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            guard let self else { return event }
            if event.window !== self.panel {
                self.close()
            }
            return event
        }) {
            eventMonitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            DispatchQueue.main.async {
                self?.close()
            }
        }) {
            eventMonitors.append(globalMonitor)
        }
    }
}

private enum InputTranslationDirection {
    case englishToChinese
    case chineseToEnglish

    static let emptyStatusText = "自动检测：中文 ⇄ English"

    static func detect(_ text: String) -> InputTranslationDirection {
        text.containsChineseCharacters ? .chineseToEnglish : .englishToChinese
    }

    var statusText: String {
        switch self {
        case .englishToChinese:
            "检测为 English，译文输出中文"
        case .chineseToEnglish:
            "检测为中文，译文输出 English"
        }
    }

    var loadingText: String {
        switch self {
        case .englishToChinese:
            "正在翻译为中文…"
        case .chineseToEnglish:
            "Translating to English…"
        }
    }
}

private extension String {
    var containsChineseCharacters: Bool {
        unicodeScalars.contains { scalar in
            let value = Int(scalar.value)
            return (0x3400...0x4DBF).contains(value) ||
                (0x4E00...0x9FFF).contains(value) ||
                (0xF900...0xFAFF).contains(value) ||
                (0x20000...0x2A6DF).contains(value) ||
                (0x2A700...0x2B73F).contains(value) ||
                (0x2B740...0x2B81F).contains(value) ||
                (0x2B820...0x2CEAF).contains(value)
        }
    }
}
