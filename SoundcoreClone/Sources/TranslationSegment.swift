import Foundation

struct TranslationSegment: Identifiable {
    let id = UUID()
    let timestamp: Date = Date()
    var sourceText: String
    var translatedText: String
    var isFinal: Bool
}
