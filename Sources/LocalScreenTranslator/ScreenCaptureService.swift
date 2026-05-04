import AppKit
import CoreGraphics
import ScreenCaptureKit

final class ScreenCaptureService {
    func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    func capture(rect appKitRect: CGRect) async throws -> CGImage? {
        let quartzRect = Self.appKitToQuartz(appKitRect)
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

    private static func appKitToQuartz(_ rect: CGRect) -> CGRect {
        let allScreens = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return CGRect(
            x: rect.minX,
            y: allScreens.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}
