import Foundation
import SwiftUI
import Translation

@MainActor
final class TranslationCoordinator: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private let source: Locale.Language
    private let target: Locale.Language
    private var queue: [PendingTranslation] = []
    private var active: PendingTranslation?

    init(sourceIdentifier: String = "en", targetIdentifier: String = "zh-Hans") {
        self.source = Locale.Language(identifier: sourceIdentifier)
        self.target = Locale.Language(identifier: targetIdentifier)
    }

    func translate(_ texts: [String]) async throws -> [String] {
        let cleanTexts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cleanTexts.contains(where: { !$0.isEmpty }) else { return texts }

        return try await withCheckedThrowingContinuation { continuation in
            queue.append(PendingTranslation(texts: cleanTexts, continuation: continuation))
            startNextIfNeeded()
        }
    }

    func run(session: TranslationSession) async {
        guard let pending = active else { return }

        do {
            try await session.prepareTranslation()
            let requests = pending.texts.enumerated().map { index, text in
                TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
            }
            let responses = try await session.translations(from: requests)
            let translated = responses
                .sorted {
                    (Int($0.clientIdentifier ?? "") ?? 0) < (Int($1.clientIdentifier ?? "") ?? 0)
                }
                .map(\.targetText)

            pending.continuation.resume(returning: translated)
        } catch {
            pending.continuation.resume(throwing: TranslationFailure.wrap(error))
        }

        active = nil
        startNextIfNeeded()
    }

    private func startNextIfNeeded() {
        guard active == nil, !queue.isEmpty else { return }
        active = queue.removeFirst()

        if configuration != nil {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}

private struct PendingTranslation {
    let texts: [String]
    let continuation: CheckedContinuation<[String], Error>
}

struct TranslationFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }

    static func wrap(_ error: Error) -> TranslationFailure {
        let nsError = error as NSError
        if nsError.localizedDescription.isEmpty {
            return TranslationFailure(message: "翻译失败。请确认这台 Mac 已安装英文和中文翻译语言资源。")
        }
        return TranslationFailure(message: nsError.localizedDescription)
    }
}

final class TranslationHostWindow {
    private let window: NSWindow

    init(coordinator: TranslationCoordinator) {
        let view = TranslationHostView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: view)
        window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
    }
}

private struct TranslationHostView: View {
    @ObservedObject var coordinator: TranslationCoordinator

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .translationTask(coordinator.configuration) { session in
                await coordinator.run(session: session)
            }
    }
}
