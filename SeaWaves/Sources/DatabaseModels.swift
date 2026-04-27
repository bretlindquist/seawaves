import Foundation
import SwiftData

@Model
final class TranslationFolder {
    var id: UUID
    var name: String
    var creationDate: Date
    
    @Relationship(deleteRule: .nullify, inverse: \TranslationSessionModel.folder)
    var sessions: [TranslationSessionModel]?
    
    init(name: String, creationDate: Date = Date()) {
        self.id = UUID()
        self.name = name
        self.creationDate = creationDate
    }
}

@Model
final class TranslationSessionModel {
    var id: UUID
    var name: String
    var startTime: Date
    var sourceLanguageCode: String
    var targetLanguageCode: String
    var audioFileURL: URL? // The raw AAC file location
    
    @Relationship(deleteRule: .cascade)
    var segments: [TranslationSegmentModel]
    
    var folder: TranslationFolder?
    var cachedPreviewText: String?
    
    init(name: String = "New Recording", startTime: Date = Date(), sourceLanguageCode: String, targetLanguageCode: String, audioFileURL: URL? = nil) {
        self.id = UUID()
        self.name = name
        self.startTime = startTime
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.audioFileURL = audioFileURL
        self.segments = []
    }
    
    var previewText: String {
        if let cachedPreviewText { return cachedPreviewText }
        return segments.first?.sourceText ?? "Empty Session"
    }
}

@Model
final class TranslationSegmentModel {
    var id: UUID
    var timestamp: Date
    var sourceText: String
    var translatedText: String
    
    // Inverse relationship back to the session
    var session: TranslationSessionModel?
    
    init(timestamp: Date = Date(), sourceText: String, translatedText: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sourceText = sourceText
        self.translatedText = translatedText
    }
}
