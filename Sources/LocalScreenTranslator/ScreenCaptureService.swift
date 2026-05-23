import AppKit
import CoreGraphics
import ScreenCaptureKit

struct ScreenSnapshot {
    let image: CGImage
    let appKitRect: CGRect
    let quartzRect: CGRect

    var displayImage: NSImage {
        NSImage(cgImage: image, size: appKitRect.size)
    }

    func crop(appKitRect rect: CGRect) -> CGImage? {
        let clippedRect = rect.intersection(appKitRect)
        guard !clippedRect.isNull, clippedRect.width > 0, clippedRect.height > 0 else {
            return nil
        }

        let clippedQuartzRect = ScreenCaptureService.appKitToQuartz(clippedRect)
        let scaleX = CGFloat(image.width) / quartzRect.width
        let scaleY = CGFloat(image.height) / quartzRect.height
        let cropRect = CGRect(
            x: (clippedQuartzRect.minX - quartzRect.minX) * scaleX,
            y: (clippedQuartzRect.minY - quartzRect.minY) * scaleY,
            width: clippedQuartzRect.width * scaleX,
            height: clippedQuartzRect.height * scaleY
        )
        .integral
        .clamped(to: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))

        guard cropRect.width > 0, cropRect.height > 0 else {
            return nil
        }
        return image.cropping(to: cropRect)
    }
}

final class ScreenCaptureService {
    func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    func captureSnapshot() async throws -> ScreenSnapshot? {
        let appKitRect = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        guard !appKitRect.isNull, appKitRect.width > 0, appKitRect.height > 0 else {
            return nil
        }

        let quartzRect = Self.appKitToQuartz(appKitRect)
        guard let image = try await capture(quartzRect: quartzRect) else {
            return nil
        }
        return ScreenSnapshot(image: image, appKitRect: appKitRect, quartzRect: quartzRect)
    }

    func capture(rect appKitRect: CGRect) async throws -> CGImage? {
        let quartzRect = Self.appKitToQuartz(appKitRect)
        return try await capture(quartzRect: quartzRect)
    }

    private func capture(quartzRect: CGRect) async throws -> CGImage? {
        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: quartzRect) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    static func appKitToQuartz(_ rect: CGRect) -> CGRect {
        let allScreens = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return CGRect(
            x: rect.minX,
            y: allScreens.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

private extension CGRect {
    func clamped(to bounds: CGRect) -> CGRect {
        let minX = max(self.minX, bounds.minX)
        let minY = max(self.minY, bounds.minY)
        let maxX = min(self.maxX, bounds.maxX)
        let maxY = min(self.maxY, bounds.maxY)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
