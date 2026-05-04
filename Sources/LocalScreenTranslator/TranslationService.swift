import Foundation

enum TranslationDirection {
    case englishToChinese
    case chineseToEnglish

    var sourceLanguageName: String {
        switch self {
        case .englishToChinese:
            "English"
        case .chineseToEnglish:
            "Chinese"
        }
    }

    var targetLanguageName: String {
        switch self {
        case .englishToChinese:
            "Simplified Chinese"
        case .chineseToEnglish:
            "English"
        }
    }
}

@MainActor
final class TranslationRouter {
    private let settings: AppSettings
    private let englishToChineseApple: TranslationCoordinator
    private let chineseToEnglishApple: TranslationCoordinator
    private let localAIService = OMLXTranslationService()

    init(
        settings: AppSettings,
        englishToChineseApple: TranslationCoordinator,
        chineseToEnglishApple: TranslationCoordinator
    ) {
        self.settings = settings
        self.englishToChineseApple = englishToChineseApple
        self.chineseToEnglishApple = chineseToEnglishApple
    }

    func translate(_ texts: [String], direction: TranslationDirection) async throws -> [String] {
        switch settings.translationEngine {
        case .appleTranslation:
            return try await translateWithApple(texts, direction: direction)
        case .localAIWithAppleFallback:
            do {
                return try await localAIService.translate(texts, direction: direction, settings: settings)
            } catch {
                guard settings.appleTranslationFallbackEnabled else {
                    throw TranslationFailure(message: "本地 AI 翻译失败：\(error.localizedDescription)")
                }

                do {
                    return try await translateWithApple(texts, direction: direction)
                } catch {
                    throw TranslationFailure(message: "本地 AI 翻译失败，备用 Apple 机翻也失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func translateWithApple(_ texts: [String], direction: TranslationDirection) async throws -> [String] {
        let coordinator = direction == .chineseToEnglish ? chineseToEnglishApple : englishToChineseApple
        return try await coordinator.translate(texts)
    }
}

final class OMLXTranslationService {
    func translate(
        _ texts: [String],
        direction: TranslationDirection,
        settings: AppSettings
    ) async throws -> [String] {
        let cleanTexts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cleanTexts.contains(where: { !$0.isEmpty }) else { return texts }

        do {
            return try await translateBatch(cleanTexts, direction: direction, settings: settings)
        } catch {
            var results: [String] = []
            results.reserveCapacity(cleanTexts.count)
            for text in cleanTexts {
                guard !text.isEmpty else {
                    results.append("")
                    continue
                }
                let translated = try await translateSingle(text, direction: direction, settings: settings)
                results.append(translated)
            }
            return results
        }
    }

    private func translateBatch(
        _ texts: [String],
        direction: TranslationDirection,
        settings: AppSettings
    ) async throws -> [String] {
        let numberedText = texts.enumerated()
            .map { index, text in "\(index + 1). \(text)" }
            .joined(separator: "\n")
        let prompt = """
        Translate each numbered item from \(direction.sourceLanguageName) to \(direction.targetLanguageName).
        Return only the translations, one per line, with the same numbering. Do not add explanations.

        \(numberedText)
        """
        let response = try await request(prompt: prompt, settings: settings)
        return try parseNumbered(response, expectedCount: texts.count)
    }

    private func translateSingle(
        _ text: String,
        direction: TranslationDirection,
        settings: AppSettings
    ) async throws -> String {
        let prompt = """
        Translate the following text from \(direction.sourceLanguageName) to \(direction.targetLanguageName).
        Return only the translated text. Do not add explanations.

        \(text)
        """
        return try await request(prompt: prompt, settings: settings)
    }

    private func request(prompt: String, settings: AppSettings) async throws -> String {
        let endpoint = try chatCompletionsURL(from: settings.localAIBaseURL)
        let model = settings.localAIModel
        guard !model.isEmpty else {
            throw TranslationFailure(message: "本地 AI 模型名为空。")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !settings.localAIAPIKey.isEmpty {
            request.setValue("Bearer \(settings.localAIAPIKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: "You are a translation engine. Output translated text only."),
                ChatMessage(role: "user", content: prompt)
            ],
            temperature: 0
        ))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = settings.localAITimeout
        configuration.timeoutIntervalForResource = settings.localAITimeout
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw TranslationFailure(message: "本地 AI 返回 HTTP \(httpResponse.statusCode)：\(message)")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw TranslationFailure(message: "本地 AI 没有返回译文。")
        }
        return content
    }

    private func chatCompletionsURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationFailure(message: "本地 AI Base URL 为空。")
        }

        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: normalized + "/chat/completions") else {
            throw TranslationFailure(message: "本地 AI Base URL 无效。")
        }
        return url
    }

    private func parseNumbered(_ response: String, expectedCount: Int) throws -> [String] {
        let lines = response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var results = Array(repeating: "", count: expectedCount)
        var matchedCount = 0
        let pattern = #"^\s*(\d+)[\.\)、\)]\s*(.+)$"#
        let regex = try NSRegularExpression(pattern: pattern)

        for line in lines {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: nsRange),
                  match.numberOfRanges == 3,
                  let indexRange = Range(match.range(at: 1), in: line),
                  let textRange = Range(match.range(at: 2), in: line),
                  let index = Int(line[indexRange]),
                  (1...expectedCount).contains(index)
            else {
                continue
            }

            results[index - 1] = String(line[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            matchedCount += 1
        }

        guard matchedCount == expectedCount,
              !results.contains(where: { $0.isEmpty }) else {
            throw TranslationFailure(message: "本地 AI 批量译文格式无法解析。")
        }

        return results
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}
