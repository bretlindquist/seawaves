import Foundation
import SwiftUI

@Observable
class HistoryManager {
    var sessions: [TranslationSessionModel] = []
    
    init() {
        loadHistory()
    }
    
    func addSession(_ session: TranslationSessionModel) {
        // Insert at the top so newest is first
        sessions.insert(session, at: 0)
        saveHistory()
    }
    
    func deleteSession(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        saveHistory()
    }
    
    func clearAll() {
        sessions.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        Task.detached(priority: .background) { [sessions] in
            if let encoded = try? JSONEncoder().encode(sessions) {
                UserDefaults.standard.set(encoded, forKey: "savedSessions")
            }
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "savedSessions"),
           let decoded = try? JSONDecoder().decode([TranslationSessionModel].self, from: data) {
            self.sessions = decoded
        }
    }
}
