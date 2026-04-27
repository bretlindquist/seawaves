import Foundation
import SwiftUI
import AVFoundation
import Speech
import os
import SwiftData

@Observable
@MainActor
class AudioController {
    var isRecording = false
    var permissionsGranted = false
    var errorMessage: String? = nil
    
    // Live UI State
    var liveSourceText: String = ""
    var liveAudioLevel: Float = 0.0
    
    private let engineActor = AudioEngineActor()
    private var listeningTask: Task<Void, Never>?
    
    // We pass the current SwiftData session in so the controller can append directly to the database
    var activeSession: TranslationSessionModel?
    private var modelContext: ModelContext?
    
    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { granted in
                        Task { @MainActor in
                            self.permissionsGranted = granted
                            if !granted { self.errorMessage = "Microphone permission denied" }
                        }
                    }
                case .denied:
                    self.errorMessage = "Speech recognition permission denied"
                    self.permissionsGranted = false
                case .restricted, .notDetermined:
                    self.errorMessage = "Speech recognition restricted or not determined"
                    self.permissionsGranted = false
                @unknown default:
                    self.permissionsGranted = false
                }
            }
        }
    }
    
    func startRecording(session: TranslationSessionModel) async throws {
        guard permissionsGranted else {
            errorMessage = "Permissions not granted yet."
            return
        }
        
        self.activeSession = session
        self.liveSourceText = ""
        self.liveAudioLevel = 0.0
        self.errorMessage = nil
        
        // Ensure the session has a file URL for raw audio
        let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentURL.appendingPathComponent("recording-\(Int(Date().timeIntervalSince1970)).m4a")
        session.audioFileURL = fileURL
        
        let stream = try await engineActor.startRecording(fileURL: fileURL)
        self.isRecording = true
        
        listeningTask = Task {
            for await event in stream {
                switch event {
                case .liveTranscriptUpdated(let text):
                    self.liveSourceText = text
                    // Ping the View to run live TranslationSession if desired
                    NotificationCenter.default.post(name: NSNotification.Name("LiveTranscriptUpdated"), object: text)
                    
                case .sentenceBoundaryReached(let finalizedText):
                    self.liveSourceText = ""
                    // Ping the View to finalize translation and append to SwiftData
                    NotificationCenter.default.post(name: NSNotification.Name("CommitSentenceBoundary"), object: finalizedText)
                    
                case .audioLevelUpdated(let level):
                    // Animate the waveform
                    withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.8)) {
                        self.liveAudioLevel = level
                    }
                }
            }
        }
    }
    
    func stopRecording() async {
        listeningTask?.cancel()
        listeningTask = nil
        
        await engineActor.stopRecording()
        
        self.isRecording = false
        self.liveSourceText = ""
        self.liveAudioLevel = 0.0
        
        // Save the SwiftData context once the session ends
        try? modelContext?.save()
        self.activeSession = nil
    }
}
