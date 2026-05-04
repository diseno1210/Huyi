import AppKit
import Foundation

final class ClipboardMonitor {
    var isEnabled = true

    private let translator: TranslationCoordinator
    private let popupController: ClipboardPopupController
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastText = ""
    private var isTranslating = false

    init(translator: TranslationCoordinator, popupController: ClipboardPopupController) {
        self.translator = translator
        self.popupController = popupController
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard isEnabled, pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let rawText = pasteboard.string(forType: .string) else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ClipboardTranslationSuppression.shouldSuppress(text: text) else { return }
        guard shouldTranslate(text) else { return }
        lastText = text

        Task { @MainActor in
            guard !isTranslating else { return }
            isTranslating = true
            defer { isTranslating = false }
            do {
                let translated = try await translator.translate([text]).first ?? ""
                popupController.show(source: text, translation: translated)
            } catch {
                popupController.show(source: text, translation: error.localizedDescription)
            }
        }
    }

    private func shouldTranslate(_ text: String) -> Bool {
        guard text != lastText, text.count >= 2, text.count <= 1_000 else { return false }
        let latinLetters = text.unicodeScalars.filter {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0)
        }.count
        return latinLetters >= max(2, text.count / 4)
    }
}

enum ClipboardTranslationSuppression {
    private struct Entry {
        let text: String
        let expiresAt: Date
    }

    private static var entries: [Entry] = []

    static func suppress(text: String) {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return }
        pruneExpiredEntries()
        entries.append(Entry(text: normalized, expiresAt: Date().addingTimeInterval(3)))
    }

    static func shouldSuppress(text: String) -> Bool {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return false }
        pruneExpiredEntries()

        guard let index = entries.firstIndex(where: { $0.text == normalized }) else {
            return false
        }
        entries.remove(at: index)
        return true
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func pruneExpiredEntries() {
        let now = Date()
        entries.removeAll { $0.expiresAt < now }
    }
}
