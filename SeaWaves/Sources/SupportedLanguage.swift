import Foundation

struct SupportedLanguage: Identifiable, Hashable {
    let id: String
    let displayName: String
    let ttsCode: String
    
    // Core translation languages
    static let english = SupportedLanguage(id: "en", displayName: "English", ttsCode: "en-US")
    
    // Requested Target Languages
    static let allTargets: [SupportedLanguage] = [
        SupportedLanguage(id: "ko", displayName: "Korean", ttsCode: "ko-KR"),
        SupportedLanguage(id: "ja", displayName: "Japanese", ttsCode: "ja-JP"),
        SupportedLanguage(id: "zh-Hans", displayName: "Chinese (Mandarin)", ttsCode: "zh-CN"),
        SupportedLanguage(id: "th", displayName: "Thai", ttsCode: "th-TH"),
        SupportedLanguage(id: "fr", displayName: "French", ttsCode: "fr-FR"),
        SupportedLanguage(id: "sv", displayName: "Swedish", ttsCode: "sv-SE"),
        SupportedLanguage(id: "de", displayName: "German", ttsCode: "de-DE"),
        SupportedLanguage(id: "vi", displayName: "Vietnamese", ttsCode: "vi-VN")
    ]
}
