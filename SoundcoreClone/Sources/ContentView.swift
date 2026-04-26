import SwiftUI
import Translation
import AVFoundation

struct ContentView: View {
    @State private var audioController = AudioController()
    
    // Translation States
    @State private var targetLanguage = Locale.Language(identifier: "es")
    @State private var sourceLanguage = Locale.Language(identifier: "en")
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
                    Text("English")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundColor(.blue)
                    Text("Spanish")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                
                Divider()
                
                // Chat Timeline
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(segments) { segment in
                                SegmentView(segment: segment) {
                                    speak(text: segment.translatedText, language: "es-ES")
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
                
                // Control Bar
                VStack(spacing: 12) {
                    if let errorMessage = audioController.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Button(action: {
                        toggleRecording()
                    }) {
                        ZStack {
                            Circle()
                                .fill(audioController.isRecording ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: audioController.isRecording ? "stop.fill" : "mic.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .foregroundColor(audioController.isRecording ? .red : .blue)
                        }
                    }
                    .disabled(!audioController.permissionsGranted)
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground).shadow(radius: 2, y: -2))
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
                                
                                // Optional: Auto-speak translation
                                // speak(text: response.targetText, language: "es-ES")
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
        if audioController.isRecording {
            audioController.stopRecording()
            // Fire translation for the final chunk of speech
            if !audioController.transcript.isEmpty {
                NotificationCenter.default.post(name: NSNotification.Name("FinalTranscriptReady"), object: nil)
            }
        } else {
            do {
                configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
                try audioController.startRecording()
            } catch {
                audioController.errorMessage = error.localizedDescription
            }
        }
    }
    
    private func speak(text: String, language: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = 0.5 // Natural reading speed
        synthesizer.speak(utterance)
    }
}

// UI Component for completed translations
struct SegmentView: View {
    let segment: TranslationSegment
    let onPlay: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(segment.sourceText)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text(segment.translatedText)
                    .font(.body)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: onPlay) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.blue)
                        .padding(8)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}

// UI Component for the live breathing transcript
struct LiveSegmentView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Listening...")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}
