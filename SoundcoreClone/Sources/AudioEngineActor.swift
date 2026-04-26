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
        // Stop the engine and remove the tap
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Explicitly tear down the STT pipelines
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        // Close the file writer to flush the final AAC bytes to disk
        audioFile = nil
        
        // Close the AsyncStream
        transcriptContinuation?.finish()
        transcriptContinuation = nil
        
        // EXTREME BATTERY OPTIMIZATION:
        // Explicitly deactivate the audio session and tell the OS to drop the hardware locks.
        // This allows the iPhone to instantly spin down the audio silicon and save battery.
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.warning("Failed to cleanly deactivate audio session: \(error.localizedDescription)")
        }
    }
}
