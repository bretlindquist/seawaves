import Foundation
import AVFoundation
import Speech
import os

@Observable
@MainActor
class AudioController {
    var isRecording = false
    var transcript: String = ""
    var permissionsGranted = false
    var errorMessage: String? = nil
    var currentFileURL: URL?
    
    private let engineActor = AudioEngineActor()
    private var listeningTask: Task<Void, Never>?
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            Task { @MainActor in
                switch authStatus {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { granted in
                        Task { @MainActor in
                            self.permissionsGranted = granted
                            if !granted {
                                self.errorMessage = "Microphone permission denied"
                            }
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
    
    func startRecording() async throws {
        guard permissionsGranted else {
            errorMessage = "Permissions not granted yet."
            return
        }
        
        self.transcript = ""
        self.errorMessage = nil
        
        let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // Change file extension from .caf to .m4a to match the AAC encoding
        let fileURL = documentURL.appendingPathComponent("recording-\(Int(Date().timeIntervalSince1970)).m4a")
        self.currentFileURL = fileURL
        
        let stream = try await engineActor.startRecording(fileURL: fileURL)
        self.isRecording = true
        
        listeningTask = Task {
            for await liveTranscript in stream {
                self.transcript = liveTranscript
            }
        }
    }
    
    func stopRecording() async {
        listeningTask?.cancel()
        listeningTask = nil
        
        await engineActor.stopRecording()
        self.isRecording = false
    }
}
