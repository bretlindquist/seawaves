import SwiftUI
import SwiftData
import Translation
import AVFoundation

struct TranslateView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var audioController = AudioController()
    
    @State private var sourceLanguage = SupportedLanguage.english
    @State private var targetLanguage = SupportedLanguage.allLanguages[1] // Default to Korean or next language
    @State private var configuration: TranslationSession.Configuration?
    
    // Live UI State
    @State private var liveTranslatedText: String = ""
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
                
                // Minimal Header
                HStack(spacing: 12) {
                    Picker("Source Language", selection: $sourceLanguage) {
                        ForEach(SupportedLanguage.allLanguages) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline)
                    .tint(.secondary)
                    
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Picker("Target Language", selection: $targetLanguage) {
                        ForEach(SupportedLanguage.allLanguages) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.subheadline)
                    .tint(.primary)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Continuous Scrolling Timeline
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            if let session = audioController.activeSession {
                                ForEach(session.segments) { segment in
                                    SegmentView(segment: segment) {
                                        speak(text: segment.translatedText, language: targetLanguage.ttsCode)
                                    }
                                    .id(segment.id)
                                }
                            }
                            
                            // Active Live Transcript Fragment
                            if audioController.isRecording && (!audioController.liveSourceText.isEmpty || !liveTranslatedText.isEmpty) {
                                LiveSegmentView(
                                    sourceText: audioController.liveSourceText,
                                    translatedText: liveTranslatedText
                                )
                                .id("live")
                            }
                        }
                        .padding(.vertical, 24)
                        .padding(.horizontal, 20)
                    }
                    // Auto-scroll to bottom as VAD chunks drop in
                    .onChange(of: audioController.activeSession?.segments.count) {
                        if let last = audioController.activeSession?.segments.last {
                            withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    // Smoothly auto-scroll live typing
                    .onChange(of: audioController.liveSourceText) {
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo("live", anchor: .bottom) }
                    }
                }
                
                // Control Bar with Reactive Waveform
                VStack(spacing: 0) {
                    if let errorMessage = audioController.errorMessage {
                        Text(errorMessage).foregroundColor(.red).font(.caption).padding(.bottom, 8)
                    }
                    
                    Button(action: {
                        toggleRecording()
                    }) {
                        ZStack {
                            if audioController.isRecording {
                                // Reactive waveform driven by real mic RMS levels
                                ReactiveWaveformView(level: audioController.liveAudioLevel)
                                    .frame(width: 140, height: 80)
                                    .opacity(0.3)
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
            .onAppear {
                audioController.setContext(modelContext)
                audioController.requestPermissions()
            }
            // Continuous Translation Worker
            .translationTask(configuration) { session in
                do {
                    // Ensure language models are downloaded and ready
                    try await session.prepareTranslation()
                    
                    // Task 1: Live stream translation (morphing text)
                    let liveTask = Task {
                        var currentTranslationTask: Task<Void, Never>?
                        for await notification in NotificationCenter.default.notifications(named: NSNotification.Name("LiveTranscriptUpdated")) {
                            guard let text = notification.object as? String, !text.isEmpty else { continue }
                            
                            currentTranslationTask?.cancel()
                            currentTranslationTask = Task {
                                do {
                                    let response = try await session.translate(text)
                                    if !Task.isCancelled {
                                        await MainActor.run { self.liveTranslatedText = response.targetText }
                                    }
                                } catch {
                                    if !Task.isCancelled {
                                        print("Live translation error: \(error)")
                                    }
                                }
                            }
                        }
                    }
                    
                    // Task 2: Commit chunk when VAD silence boundary is hit
                    let commitTask = Task {
                        for await notification in NotificationCenter.default.notifications(named: NSNotification.Name("CommitSentenceBoundary")) {
                            guard let text = notification.object as? String, !text.isEmpty else { continue }
                            
                            var finalTranslation = ""
                            do {
                                let response = try await session.translate(text)
                                finalTranslation = response.targetText
                            } catch {
                                print("Commit translation error: \(error)")
                            }
                            
                            await MainActor.run {
                                let newSegment = TranslationSegmentModel(
                                    timestamp: Date(),
                                    sourceText: text,
                                    translatedText: finalTranslation
                                )
                                
                                // Haptic bump when a line drops in
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                
                                self.audioController.activeSession?.segments.append(newSegment)
                                if self.audioController.activeSession?.cachedPreviewText == nil {
                                    self.audioController.activeSession?.cachedPreviewText = text
                                }
                                self.liveTranslatedText = "" // Clear live UI for the next sentence
                            }
                        }
                    }
                    
                    // Keep the task alive and clean up on cancellation
                    try? await Task.sleep(nanoseconds: UInt64.max)
                    liveTask.cancel()
                    commitTask.cancel()
                } catch {
                    print("Translation task error: \(error)")
                }
            }
        }
    }
    
    private func toggleRecording() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        Task {
            if audioController.isRecording {
                await audioController.stopRecording()
            } else {
                do {
                    self.liveTranslatedText = ""
                    let srcLocale = Locale.Language(identifier: sourceLanguage.id)
                    let tgtLocale = Locale.Language(identifier: targetLanguage.id)
                    
                    configuration = TranslationSession.Configuration(source: srcLocale, target: tgtLocale)
                    
                    // Create a new SwiftData session
                    let newSession = TranslationSessionModel(
                        name: "Recording \(Date().formatted(date: .abbreviated, time: .shortened))",
                        sourceLanguageCode: sourceLanguage.id,
                        targetLanguageCode: targetLanguage.id
                    )
                    modelContext.insert(newSession)
                    
                    try await audioController.startRecording(session: newSession, localeIdentifier: sourceLanguage.localeIdentifier)
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
}

// Flat, subtle UI for completed translations
struct SegmentView: View {
    let segment: TranslationSegmentModel
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

// Flat, subtle UI for live listening
struct LiveSegmentView: View {
    let sourceText: String
    let translatedText: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text("Listening").font(.caption).textCase(.uppercase).foregroundColor(.secondary)
            }
            Text(sourceText).font(.subheadline).foregroundColor(.secondary).opacity(0.8)
            Text(translatedText.isEmpty ? "..." : translatedText).font(.title2).fontWeight(.medium).foregroundColor(.primary).opacity(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Reactive Waveform driven by real audio RMS
struct ReactiveWaveformView: View {
    let level: Float
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.red)
                    // Apply different scaling factors to each bar so they bounce dynamically
                    .frame(width: 4, height: height(for: index, level: level))
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: level)
            }
        }
    }
    
    private func height(for index: Int, level: Float) -> CGFloat {
        let baseHeight: CGFloat = 8.0
        let maxJump: CGFloat = 40.0
        
        // Pseudo-randomize the jump for each bar based on the true RMS level
        let multiplier = [0.8, 1.2, 1.0, 0.6, 1.4, 0.9][index]
        let jump = CGFloat(level) * maxJump * multiplier
        
        return baseHeight + jump
    }
}
