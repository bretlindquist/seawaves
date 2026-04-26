import Foundation
import AVFoundation
import Speech
import os

/// Dedicated Actor to handle high-frequency audio buffer processing off the main thread
actor AudioEngineActor {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    
    let logger = Logger(subsystem: "com.example.SoundcoreClone", category: "AudioEngineActor")
    
    // We yield transcript updates via a continuation to avoid NotificationCenter overhead
    private var transcriptContinuation: AsyncStream<String>.Continuation?
    
    func startRecording(fileURL: URL) async throws -> AsyncStream<String> {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { fatalError("Unable to create request") }
        
        request.shouldReportPartialResults = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        
        let format = inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        self.transcriptContinuation = continuation
        
        // Use a non-isolated task callback to handle the high frequency STT responses
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                continuation.yield(result.bestTranscription.formattedString)
            }
            if error != nil {
                continuation.finish()
            }
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            guard let self = self else { return }
            // Push buffer processing to a background detached task to prevent blocking the audio tap
            Task.detached(priority: .userInitiated) {
                await self.processBuffer(buffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        return stream
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
        do {
            try audioFile?.write(from: buffer)
        } catch {
            logger.error("Error writing audio file: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioFile = nil
        transcriptContinuation?.finish()
        transcriptContinuation = nil
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
