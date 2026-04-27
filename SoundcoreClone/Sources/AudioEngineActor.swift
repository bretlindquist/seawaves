import Foundation
import AVFoundation
import Speech
import os

/// Event types emitted by the Audio Engine
enum AudioEngineEvent {
    case liveTranscriptUpdated(String)
    case sentenceBoundaryReached(String)
    case audioLevelUpdated(Float) // Used to drive the reactive waveform UI
}

actor AudioEngineActor {
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    
    // Silence Debounce / VAD parameters
    private var lastTranscriptUpdate: Date = Date()
    private var debounceTask: Task<Void, Never>?
    private let silenceThreshold: TimeInterval = 1.2 // 1.2 seconds of silence triggers a boundary
    
    // State
    private var currentLiveTranscript: String = ""
    
    let logger = Logger(subsystem: "com.example.SoundcoreClone", category: "AudioEngineActor")
    private var eventContinuation: AsyncStream<AudioEngineEvent>.Continuation?
    
    func startRecording(fileURL: URL) async throws -> AsyncStream<AudioEngineEvent> {
        recognitionTask?.cancel()
        recognitionTask = nil
        debounceTask?.cancel()
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try audioSession.setPreferredIOBufferDuration(0.005)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { fatalError("Unable to create request") }
        
        request.shouldReportPartialResults = true
        // We explicitly DO NOT rely on addsPunctuation to dictate boundaries anymore.
        request.addsPunctuation = true 
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        
        let (stream, continuation) = AsyncStream.makeStream(of: AudioEngineEvent.self)
        self.eventContinuation = continuation
        
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                Task { await self.handleSTTResult(result.bestTranscription.formattedString) }
            }
            if error != nil {
                Task { await self.flushAndReset() }
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
    
    private func handleSTTResult(_ newText: String) {
        // If the text hasn't actually grown/changed, don't reset the silence timer.
        // This prevents the engine from keeping a line open just because it's "thinking".
        if newText != currentLiveTranscript {
            currentLiveTranscript = newText
            eventContinuation?.yield(.liveTranscriptUpdated(newText))
            
            // Reset the silence debounce timer
            debounceTask?.cancel()
            debounceTask = Task {
                do {
                    // Wait for the silence threshold
                    try await Task.sleep(nanoseconds: UInt64(silenceThreshold * 1_000_000_000))
                    // If we haven't been cancelled by a new word, flush the chunk!
                    await self.flushAndReset()
                } catch {
                    // Task cancelled due to new speech, do nothing
                }
            }
        }
    }
    
    private func flushAndReset() {
        guard !currentLiveTranscript.isEmpty else { return }
        
        // 1. Commit the sentence
        let finalizedText = currentLiveTranscript
        eventContinuation?.yield(.sentenceBoundaryReached(finalizedText))
        currentLiveTranscript = ""
        
        // 2. Restart the STT engine so the next word starts a brand new string
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
                Task { await self.handleSTTResult(result.bestTranscription.formattedString) }
            }
        }
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
        do {
            try audioFile?.write(from: buffer)
        } catch {
            logger.error("Error writing AAC audio file: \(error.localizedDescription)")
        }
        
        // Calculate RMS for the live waveform UI
        if let channelData = buffer.floatChannelData?[0] {
            let frames = buffer.frameLength
            var sum: Float = 0.0
            for i in 0..<Int(frames) {
                sum += channelData[i] * channelData[i]
            }
            let rms = sqrt(sum / Float(frames))
            // Normalize RMS to a reasonable 0.0 - 1.0 range for the UI
            let normalizedLevel = min(max(rms * 5.0, 0.0), 1.0)
            eventContinuation?.yield(.audioLevelUpdated(normalizedLevel))
        }
    }
    
    func stopRecording() {
        debounceTask?.cancel()
        
        if !currentLiveTranscript.isEmpty {
            eventContinuation?.yield(.sentenceBoundaryReached(currentLiveTranscript))
            currentLiveTranscript = ""
        }
        
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioFile = nil
        eventContinuation?.finish()
        eventContinuation = nil
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
