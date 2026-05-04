import AppKit

final class StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(
        onTranslateArea: @escaping () -> Void,
        onCaptureScreenshot: @escaping () -> Void,
        onInputTranslation: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onClearOverlay: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem.button?.title = ""
        statusItem.button?.image = TigerStatusIcon.makeImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "虎译 - 本地截图翻译"

        let menu = NSMenu()
        let translateItem = NSMenuItem(title: "截图翻译", action: #selector(translateArea), keyEquivalent: "")
        translateItem.target = self
        translateItem.representedObject = ActionBox(onTranslateArea)
        menu.addItem(translateItem)

        let captureItem = NSMenuItem(title: "截图", action: #selector(captureScreenshot), keyEquivalent: "")
        captureItem.target = self
        captureItem.representedObject = ActionBox(onCaptureScreenshot)
        menu.addItem(captureItem)

        let inputTranslationItem = NSMenuItem(title: "输入翻译", action: #selector(inputTranslation), keyEquivalent: "")
        inputTranslationItem.target = self
        inputTranslationItem.representedObject = ActionBox(onInputTranslation)
        menu.addItem(inputTranslationItem)

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.representedObject = ActionBox(onOpenSettings)
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let clearItem = NSMenuItem(title: "清除译文", action: #selector(clearOverlay), keyEquivalent: "")
        clearItem.target = self
        clearItem.representedObject = ActionBox(onClearOverlay)
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.representedObject = ActionBox(onQuit)
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func translateArea(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    @objc private func captureScreenshot(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    @objc private func inputTranslation(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    @objc private func clearOverlay(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.action()
    }
}

private enum TigerStatusIcon {
    static func makeImage() -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let orange = NSColor(calibratedRed: 1.0, green: 0.57, blue: 0.12, alpha: 1)
        let darkOrange = NSColor(calibratedRed: 0.75, green: 0.28, blue: 0.03, alpha: 1)
        let black = NSColor(calibratedWhite: 0.06, alpha: 1)
        let cream = NSColor(calibratedRed: 1.0, green: 0.9, blue: 0.66, alpha: 1)
        let pink = NSColor(calibratedRed: 1.0, green: 0.67, blue: 0.5, alpha: 1)

        drawEar(points: [NSPoint(x: 5.2, y: 13.6), NSPoint(x: 6.8, y: 20), NSPoint(x: 10.2, y: 15.4)], fill: orange, stroke: darkOrange)
        drawEar(points: [NSPoint(x: 11.8, y: 15.4), NSPoint(x: 15.2, y: 20), NSPoint(x: 16.8, y: 13.6)], fill: orange, stroke: darkOrange)
        drawEar(points: [NSPoint(x: 6.5, y: 14.7), NSPoint(x: 7.2, y: 17.7), NSPoint(x: 8.8, y: 15.5)], fill: pink, stroke: nil)
        drawEar(points: [NSPoint(x: 13.2, y: 15.5), NSPoint(x: 14.8, y: 17.7), NSPoint(x: 15.5, y: 14.7)], fill: pink, stroke: nil)

        let face = NSBezierPath(ovalIn: NSRect(x: 3.6, y: 3, width: 14.8, height: 15.8))
        orange.setFill()
        face.fill()
        darkOrange.setStroke()
        face.lineWidth = 0.7
        face.stroke()

        drawStripe(from: NSPoint(x: 11, y: 17.7), to: NSPoint(x: 11, y: 13.4), color: black, width: 1.3)
        drawStripe(from: NSPoint(x: 8.2, y: 16.1), to: NSPoint(x: 9.7, y: 13.3), color: black, width: 1.1)
        drawStripe(from: NSPoint(x: 13.8, y: 16.1), to: NSPoint(x: 12.3, y: 13.3), color: black, width: 1.1)
        drawStripe(from: NSPoint(x: 4.4, y: 11.8), to: NSPoint(x: 7.6, y: 10.8), color: black, width: 1.1)
        drawStripe(from: NSPoint(x: 17.6, y: 11.8), to: NSPoint(x: 14.4, y: 10.8), color: black, width: 1.1)

        let muzzle = NSBezierPath(ovalIn: NSRect(x: 7.3, y: 5.1, width: 7.4, height: 5.5))
        cream.setFill()
        muzzle.fill()

        black.setFill()
        NSBezierPath(ovalIn: NSRect(x: 7.4, y: 10.9, width: 1.8, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 12.8, y: 10.9, width: 1.8, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.1, y: 7.5, width: 1.8, height: 1.2)).fill()
        drawStripe(from: NSPoint(x: 11, y: 7.4), to: NSPoint(x: 11, y: 6.2), color: black, width: 0.7)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawEar(points: [NSPoint], fill: NSColor, stroke: NSColor?) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        path.close()
        fill.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            path.lineWidth = 0.55
            path.stroke()
        }
    }

    private static func drawStripe(from start: NSPoint, to end: NSPoint, color: NSColor, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}

private final class ActionBox {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}
