import Foundation

struct SupportedLanguage: Identifiable, Hashable {
    let id: String
    let displayName: String
    let ttsCode: String
    let localeIdentifier: String // Added for Speech Recognition
    
    // Core translation languages
    static let english = SupportedLanguage(id: "en", displayName: "English", ttsCode: "en-US", localeIdentifier: "en-US")
    
    // Requested Target Languages
    static let allLanguages: [SupportedLanguage] = [
        english,
        SupportedLanguage(id: "ko", displayName: "Korean", ttsCode: "ko-KR", localeIdentifier: "ko-KR"),
        SupportedLanguage(id: "ja", displayName: "Japanese", ttsCode: "ja-JP", localeIdentifier: "ja-JP"),
        SupportedLanguage(id: "zh-Hans", displayName: "Chinese (Mandarin)", ttsCode: "zh-CN", localeIdentifier: "zh-CN"),
        SupportedLanguage(id: "th", displayName: "Thai", ttsCode: "th-TH", localeIdentifier: "th-TH"),
        SupportedLanguage(id: "fr", displayName: "French", ttsCode: "fr-FR", localeIdentifier: "fr-FR"),
        SupportedLanguage(id: "sv", displayName: "Swedish", ttsCode: "sv-SE", localeIdentifier: "sv-SE"),
        SupportedLanguage(id: "de", displayName: "German", ttsCode: "de-DE", localeIdentifier: "de-DE"),
        SupportedLanguage(id: "vi", displayName: "Vietnamese", ttsCode: "vi-VN", localeIdentifier: "vi-VN"),
        SupportedLanguage(id: "es", displayName: "Spanish", ttsCode: "es-ES", localeIdentifier: "es-ES")
    ]
}
