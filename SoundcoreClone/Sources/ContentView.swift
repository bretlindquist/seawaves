import SwiftUI
import Translation
import AVFoundation

struct ContentView: View {
    @State private var audioController = AudioController()
    
    @State private var sourceLanguage = SupportedLanguage.english
    @State private var targetLanguage = SupportedLanguage.allTargets[0]
    @State private var configuration: TranslationSession.Configuration?
    
    @AppStorage("savedSegments") private var savedSegmentsData: Data = Data()
    @State private var segments: [TranslationSegment] = []
    
    @State private var isExportingText = false
    @State private var isExportingAudio = false
    
    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !audioController.permissionsGranted {
                    Button("Grant Permissions") {
                        audioController.requestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                
                HStack(spacing: 12) {
                    Text(sourceLanguage.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.tertiaryLabel)
                    
                    Picker("Target Language", selection: $targetLanguage) {
                        ForEach(SupportedLanguage.allTargets) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline)
                    .tint(.primary)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            ForEach(segments) { segment in
                                SegmentView(segment: segment) {
                                    speak(text: segment.translatedText, language: targetLanguage.ttsCode)
                                }
                                .id(segment.id)
                            }
                            
                            if audioController.isRecording && !audioController.transcript.isEmpty {
                                LiveSegmentView(text: audioController.transcript)
                                    .id("live")
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: segments.count) {
                        saveHistory()
                        if let last = segments.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: audioController.transcript) {
                        withAnimation { proxy.scrollTo("live", anchor: .bottom) }
                    }
                }
                
                VStack(spacing: 0) {
                    if let errorMessage = audioController.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.bottom, 8)
                    }
                    
                    Button(action: {
                        toggleRecording()
                    }) {
                        ZStack {
                            if audioController.isRecording {
                                WaveformView(isRecording: true)
                                    .frame(width: 120, height: 80)
                                    .opacity(0.2)
                            }
                            
                            ZStack {
                                Circle()
                                    .stroke(audioController.isRecording ? Color.red : Color.secondary.opacity(0.2), lineWidth: 2)
                                    .frame(width: 64, height: 64)
                                
                                if audioController.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.red)
                                        .frame(width: 24, height: 24)
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 54, height: 54)
                                }
                            }
                        }
                        .frame(height: 80)
                    }
                    .disabled(!audioController.permissionsGranted)
                    .padding(.bottom, 32)
                    .padding(.top, 16)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground).ignoresSafeArea(edges: .bottom))
            }
            .navigationTitle("Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { isExportingText = true }) {
                            Label("Export Transcript", systemImage: "doc.text")
                        }
                        Button(action: { isExportingAudio = true }) {
                            Label("Export Last Audio", systemImage: "waveform")
                        }
                        Divider()
                        Button(role: .destructive, action: { clearHistory() }) {
                            Label("Clear History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.primary)
                    }
                }
            }
            .onAppear {
                audioController.requestPermissions()
                loadHistory()
            }
            .sheet(isPresented: $isExportingText) {
                ShareSheet(activityItems: [generateTranscriptText()])
            }
            .sheet(isPresented: $isExportingAudio) {
                if let url = audioController.currentFileURL {
                    ShareSheet(activityItems: [url])
                } else {
                    Text("No audio recorded yet.")
                }
            }
            // Explicit trigger for translating the final chunk
            .translationTask(configuration) { session in
                do {
                    for await _ in NotificationCenter.default.notifications(named: NSNotification.Name("FinalTranscriptReady")) {
                        let finalSourceText = audioController.transcript
                        if !finalSourceText.isEmpty {
                            // Run the native translation asynchronously 
                            let response = try await session.translate(finalSourceText)
                            await MainActor.run {
                                let newSegment = TranslationSegment(
                                    sourceText: finalSourceText,
                                    translatedText: response.targetText,
                                    isFinal: true
                                )
                                self.segments.append(newSegment)
                            }
                        }
                    }
                } catch {
                    print("Translation error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleRecording() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        Task {
            if audioController.isRecording {
                // Signal UI to stop instantly
                let snapshot = audioController.transcript
                await audioController.stopRecording()
                
                if !snapshot.isEmpty {
                    // Fire the translation layer for the snapshot
                    NotificationCenter.default.post(name: NSNotification.Name("FinalTranscriptReady"), object: nil)
                }
            } else {
                do {
                    let srcLocale = Locale.Language(identifier: sourceLanguage.id)
                    let tgtLocale = Locale.Language(identifier: targetLanguage.id)
                    configuration = TranslationSession.Configuration(source: srcLocale, target: tgtLocale)
                    
                    try await audioController.startRecording()
                } catch {
                    audioController.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func speak(text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
    
    // MARK: - Persistence & Export
    
    private func saveHistory() {
        // Run JSON encoding in a detached task to avoid blocking the main thread during heavy chat logs
        let currentSegments = segments
        Task.detached(priority: .background) {
            if let encoded = try? JSONEncoder().encode(currentSegments) {
                await MainActor.run {
                    savedSegmentsData = encoded
                }
            }
        }
    }
    
    private func loadHistory() {
        if let decoded = try? JSONDecoder().decode([TranslationSegment].self, from: savedSegmentsData) {
            segments = decoded
        }
    }
    
    private func clearHistory() {
        segments.removeAll()
        savedSegmentsData = Data()
    }
    
    private func generateTranscriptText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        
        return segments.map { segment in
            "[\(dateFormatter.string(from: segment.timestamp))]\n" +
            "\(sourceLanguage.displayName): \(segment.sourceText)\n" +
            "\(targetLanguage.displayName): \(segment.translatedText)\n"
        }.joined(separator: "\n")
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SegmentView: View {
    let segment: TranslationSegment
    let onPlay: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(segment.sourceText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(segment.translatedText)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Button(action: onPlay) {
                    Image(systemName: "speaker.wave.2")
                        .font(.body)
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LiveSegmentView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text("Listening")
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundColor(.secondary)
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
