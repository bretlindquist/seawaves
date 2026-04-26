import SwiftUI
import Translation
import AVFoundation

struct ContentView: View {
    @State private var audioController = AudioController()
    
    // Translation States
    @State private var sourceLanguage = SupportedLanguage.english
    @State private var targetLanguage = SupportedLanguage.allTargets[0] // Defaults to Korean
    @State private var configuration: TranslationSession.Configuration?
    
    // Interpreter Timeline
    @State private var segments: [TranslationSegment] = []
    
    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Permissions
                if !audioController.permissionsGranted {
                    Button("Grant Permissions") {
                        audioController.requestPermissions()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                
                // Language Picker Header
                HStack(spacing: 16) {
                    Text(sourceLanguage.displayName)
                        .font(.headline)
                    
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                    
                    Picker("Target Language", selection: $targetLanguage) {
                        ForEach(SupportedLanguage.allTargets) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.headline)
                    .tint(.primary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.secondarySystemBackground))
                
                Divider()
                
                // Chat Timeline
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(segments) { segment in
                                SegmentView(segment: segment) {
                                    speak(text: segment.translatedText, language: targetLanguage.ttsCode)
                                }
                                .id(segment.id)
                            }
                            
                            // Active Live Transcript
                            if audioController.isRecording && !audioController.transcript.isEmpty {
                                LiveSegmentView(text: audioController.transcript)
                                    .id("live")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: segments.count) {
                        if let last = segments.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: audioController.transcript) {
                        withAnimation { proxy.scrollTo("live", anchor: .bottom) }
                    }
                }
                
                // Control Bar (Bottom)
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
                            // Waveform background when recording
                            if audioController.isRecording {
                                WaveformView(isRecording: true)
                                    .frame(width: 120, height: 80)
                                    .opacity(0.3)
                            }
                            
                            // Classic Record Button
                            ZStack {
                                Circle()
                                    .stroke(audioController.isRecording ? Color.red : Color.primary.opacity(0.3), lineWidth: 4)
                                    .frame(width: 72, height: 72)
                                
                                if audioController.isRecording {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.red)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 60, height: 60)
                                }
                            }
                        }
                        .frame(height: 100)
                    }
                    .disabled(!audioController.permissionsGranted)
                    .padding(.bottom, 24)
                    .padding(.top, 16)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground).shadow(color: .black.opacity(0.1), radius: 10, y: -5))
            }
            .navigationTitle("Live Interpreter")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                audioController.requestPermissions()
            }
            // Apple Native Translation API
            .translationTask(configuration) { session in
                do {
                    for await _ in NotificationCenter.default.notifications(named: NSNotification.Name("FinalTranscriptReady")) {
                        let currentText = audioController.transcript
                        if !currentText.isEmpty {
                            let response = try await session.translate(currentText)
                            await MainActor.run {
                                let newSegment = TranslationSegment(
                                    sourceText: currentText,
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
    
    private func toggleRecording() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        if audioController.isRecording {
            audioController.stopRecording()
            if !audioController.transcript.isEmpty {
                NotificationCenter.default.post(name: NSNotification.Name("FinalTranscriptReady"), object: nil)
            }
        } else {
            do {
                let srcLocale = Locale.Language(identifier: sourceLanguage.id)
                let tgtLocale = Locale.Language(identifier: targetLanguage.id)
                configuration = TranslationSession.Configuration(source: srcLocale, target: tgtLocale)
                
                try audioController.startRecording()
            } catch {
                audioController.errorMessage = error.localizedDescription
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

struct SegmentView: View {
    let segment: TranslationSegment
    let onPlay: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(segment.sourceText)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            Divider()
            
            HStack(alignment: .bottom) {
                Text(segment.translatedText)
                    .font(.body)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Button(action: onPlay) {
                    Image(systemName: "speaker.wave.2.circle.fill")
                        .resizable()
                        .frame(width: 28, height: 28)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
    }
}

struct LiveSegmentView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Listening...")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red)
            }
            
            Text(text)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}
