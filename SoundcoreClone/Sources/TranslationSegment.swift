import Foundation

struct TranslationSegment: Identifiable, Codable {
    var id = UUID()
    var timestamp: Date = Date()
    var sourceText: String
    var translatedText: String
    var isFinal: Bool
}
