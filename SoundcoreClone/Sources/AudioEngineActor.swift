import Foundation
import AVFoundation
import Speech
import os

actor AudioEngineActor {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // We use AVAudioFile to write hardware-encoded AAC directly to disk
    private var audioFile: AVAudioFile?
    
    let logger = Logger(subsystem: "com.example.SoundcoreClone", category: "AudioEngineActor")
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
        
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        self.transcriptContinuation = continuation
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { result, error in
            if let result = result {
                continuation.yield(result.bestTranscription.formattedString)
            }
            if error != nil {
                continuation.finish()
            }
        }
        
        // Define compressed AAC (m4a) settings
        // AAC hardware encoding uses tiny CPU and shrinks files by ~90%
        let format = inputNode.outputFormat(forBus: 0)
        let aacSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1, // Mono is fine for voice
            AVEncoderBitRateKey: 64000 // 64kbps is excellent for speech
        ]
        
        // Ensure the file URL has the correct .m4a extension
        audioFile = try AVAudioFile(forWriting: fileURL, settings: aacSettings)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            guard let self = self else { return }
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
            // AVAudioFile automatically converts the raw PCM buffer to AAC on the fly
            try audioFile?.write(from: buffer)
        } catch {
            logger.error("Error writing AAC audio file: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioFile = nil // Closes the file
        transcriptContinuation?.finish()
        transcriptContinuation = nil
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
