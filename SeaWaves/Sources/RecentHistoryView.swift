import SwiftUI
import SwiftData
import AVFoundation
import Translation

struct RecentHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TranslationSessionModel> { $0.folder == nil }, sort: \TranslationSessionModel.startTime, order: .reverse) 
    private var recentSessions: [TranslationSessionModel]
    
    @Query(sort: \TranslationFolder.creationDate) private var folders: [TranslationFolder]
    
    private let synthesizer = AVSpeechSynthesizer()
    
    @State private var sessionToRename: TranslationSessionModel?
    @State private var newName: String = ""
    @State private var sessionToMove: TranslationSessionModel?
    
    var body: some View {
        NavigationStack {
            List {
                if recentSessions.isEmpty {
                    Text("No recent unarchived recordings.")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                }
                
                ForEach(recentSessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session, synthesizer: synthesizer)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            HStack {
                                Text("\(session.sourceLanguageCode) → \(session.targetLanguageCode)")
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
                                .lineLimit(1)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    // DELIGHTFUL UX: Native Swipe Actions
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteSingleSession(session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            sessionToMove = session
                        } label: {
                            Label("Move", systemImage: "folder")
                        }
                        .tint(.indigo)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            sessionToRename = session
                            newName = session.name
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            }
            .navigationTitle("Recent")
            .alert("Rename Recording", isPresented: .constant(sessionToRename != nil)) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { sessionToRename = nil }
                Button("Save") {
                    if let session = sessionToRename {
                        session.name = newName
                        try? modelContext.save()
                    }
                    sessionToRename = nil
                }
            }
            .confirmationDialog("Move to Folder", isPresented: .constant(sessionToMove != nil), titleVisibility: .visible) {
                ForEach(folders) { folder in
                    Button(folder.name) {
                        if let session = sessionToMove {
                            moveToFolder(session: session, folder: folder)
                        }
                    }
                }
                Button("Cancel", role: .cancel) { sessionToMove = nil }
            }
        }
    }
    
    private func moveToFolder(session: TranslationSessionModel, folder: TranslationFolder) {
        session.folder = folder
        try? modelContext.save()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        sessionToMove = nil
    }
    
    private func deleteSingleSession(_ session: TranslationSessionModel) {
        if let url = session.audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }
}

@Observable
class SessionAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    var isPlaying = false
    
    func loadAndPlay(url: URL?) {
        guard let url = url else { return }
        do {
            if audioPlayer == nil || audioPlayer?.url != url {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true)
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.delegate = self
            }
            
            if isPlaying {
                audioPlayer?.pause()
                isPlaying = false
            } else {
                audioPlayer?.play()
                isPlaying = true
            }
        } catch {
            print("Failed to play audio: \(error)")
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}

struct SessionDetailView: View {
    let session: TranslationSessionModel
    let synthesizer: AVSpeechSynthesizer
    @State private var audioPlayer = SessionAudioPlayer()
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(session.segments) { segment in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(segment.sourceText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(segment.translatedText)
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if segment.translatedText.contains("Translation failed") {
                                    Button(action: {
                                        segment.translatedText = "Retrying..."
                                        NotificationCenter.default.post(name: NSNotification.Name("RetryTranslation_\(session.id.uuidString)"), object: segment)
                                    }) {
                                        Image(systemName: "arrow.clockwise.circle.fill")
                                            .font(.body)
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                                Button(action: { speak(text: segment.translatedText, lang: session.targetLanguageCode) }) {
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
            
            // Audio Playback Bar
            if session.audioFileURL != nil {
                VStack {
                    Divider()
                    HStack {
                        Text("Original Recording")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: { audioPlayer.loadAndPlay(url: session.audioFileURL) }) {
                            Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                }
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .onDisappear {
            audioPlayer.stop()
        }
        .translationTask(TranslationSession.Configuration(
            source: Locale.Language(identifier: session.sourceLanguageCode),
            target: Locale.Language(identifier: session.targetLanguageCode)
        )) { translationSession in
            do {
                try await translationSession.prepareTranslation()
            } catch {
                print("Retry prep failed: \(error)")
            }
            let notificationName = NSNotification.Name("RetryTranslation_\(session.id.uuidString)")
            for await notification in NotificationCenter.default.notifications(named: notificationName) {
                guard let segment = notification.object as? TranslationSegmentModel else { continue }
                do {
                    let response = try await translationSession.translate(segment.sourceText)
                    await MainActor.run {
                        segment.translatedText = response.targetText
                    }
                } catch {
                    print("Retry translation error: \(error)")
                    await MainActor.run {
                        segment.translatedText = "Translation failed. Check language model."
                    }
                }
            }
        }
    }
    
    private func speak(text: String, lang: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Find a matching voice if possible
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        if let matchingVoice = availableVoices.first(where: { $0.language.starts(with: lang) }) {
            utterance.voice = matchingVoice
        }
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
}
