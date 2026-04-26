import Foundation

// A single translated bubble
struct TranslationSegment: Identifiable, Codable {
    var id = UUID()
    var timestamp: Date = Date()
    var sourceText: String
    var translatedText: String
    var isFinal: Bool
}

// A full recording session (grouped by when the user hit record)
struct TranslationSessionModel: Identifiable, Codable {
    var id = UUID()
    var startTime: Date = Date()
    var sourceLanguageName: String
    var targetLanguageName: String
    var segments: [TranslationSegment] = []
    
    // Derived property for the history list preview
    var previewText: String {
        segments.first?.sourceText ?? "Empty Session"
    }
}
