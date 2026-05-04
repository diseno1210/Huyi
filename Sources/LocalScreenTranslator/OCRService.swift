import CoreGraphics
import Foundation
import Vision

struct RecognizedLine {
    let text: String
    let rect: CGRect
}

enum OCRRecognitionMode {
    case english
    case chineseAndEnglish

    var recognitionLanguages: [String] {
        switch self {
        case .english:
            ["en-US"]
        case .chineseAndEnglish:
            ["zh-Hans", "zh-Hant", "en-US"]
        }
    }
}

final class OCRService {
    func recognizeText(in image: CGImage, mode: OCRRecognitionMode = .english) throws -> String {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return try recognizeLines(in: image, screenRect: imageRect, mode: mode)
            .map(\.text)
            .joined(separator: "\n")
    }

    func recognizeLines(in image: CGImage, screenRect: CGRect, mode: OCRRecognitionMode = .english) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = mode.recognitionLanguages
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = (request.results ?? [])
            .compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecognizedLine(
                    text: text,
                    rect: Self.screenRect(for: observation.boundingBox, in: screenRect)
                )
            }

        return observations.sorted {
            if abs($0.rect.minY - $1.rect.minY) > 4 {
                return $0.rect.minY > $1.rect.minY
            }
            return $0.rect.minX < $1.rect.minX
        }
    }

    private static func screenRect(for normalizedRect: CGRect, in screenRect: CGRect) -> CGRect {
        CGRect(
            x: screenRect.minX + normalizedRect.minX * screenRect.width,
            y: screenRect.minY + normalizedRect.minY * screenRect.height,
            width: normalizedRect.width * screenRect.width,
            height: normalizedRect.height * screenRect.height
        )
    }
}
