import Foundation
import AVFoundation
import Speech
import os

actor AudioEngineActor {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    
    let logger = Logger(subsystem: "com.example.SoundcoreClone", category: "AudioEngineActor")
    private var transcriptContinuation: AsyncStream<String>.Continuation?
    
    func startRecording(fileURL: URL) async throws -> AsyncStream<String> {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try audioSession.setPreferredIOBufferDuration(0.005)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { fatalError("Unable to create request") }
        
        request.shouldReportPartialResults = true
        // Add punctuation so we can use it for sentence boundary detection
        request.addsPunctuation = true
        
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
        
        let format = inputNode.outputFormat(forBus: 0)
        let aacSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]
        
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
        
        audioFile = nil
        transcriptContinuation?.finish()
        transcriptContinuation = nil
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    // Allows the UI to forcefully flush the current STT buffer when a sentence boundary is reached
    // so the recognizer starts fresh for the next sentence without breaking the audio tap.
    func flushSTTBuffer() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        let inputNode = audioEngine.inputNode
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                Task { await self.yieldTranscript(result.bestTranscription.formattedString) }
            }
        }
    }
    
    private func yieldTranscript(_ text: String) {
        transcriptContinuation?.yield(text)
    }
}
