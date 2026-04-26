import SwiftUI
import AVFoundation

struct HistoryView: View {
    @Bindable var historyManager: HistoryManager
    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        List {
            if historyManager.sessions.isEmpty {
                Text("No translation history yet.")
                    .foregroundColor(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(historyManager.sessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session, synthesizer: synthesizer)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(session.sourceLanguageName) → \(session.targetLanguageName)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                
                                Spacer()
                                
                                Text(session.startTime, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(session.previewText)
                                .font(.body)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: historyManager.deleteSession)
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !historyManager.sessions.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear All", role: .destructive) {
                        historyManager.clearAll()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
}

struct SessionDetailView: View {
    let session: TranslationSessionModel
    let synthesizer: AVSpeechSynthesizer
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(session.segments) { segment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(segment.sourceText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(segment.translatedText)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Button(action: {
                                speak(text: segment.translatedText)
                            }) {
                                Image(systemName: "speaker.wave.2")
                                    .font(.body)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle(session.startTime.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
    }
    
    private func speak(text: String) {
        // We do not have the exact language code saved in the session model right now,
        // but AVSpeechSynthesizer will auto-detect the language if left to default, 
        // or we could map it based on targetLanguageName in a future pass.
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}
