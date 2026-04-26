import Foundation
import AVFoundation
import Speech
import os

@Observable
class AudioController {
    var isRecording = false
    var transcript: String = "" {
        didSet {
            NotificationCenter.default.post(name: NSNotification.Name("TranscriptUpdated"), object: nil)
        }
    }
    var permissionsGranted = false
    var errorMessage: String? = nil
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    var currentFileURL: URL?
    private var audioFile: AVAudioFile?
    
    let logger = Logger(subsystem: "com.example.SoundcoreClone", category: "AudioController")
    
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    AVAudioApplication.requestRecordPermission { granted in
                        DispatchQueue.main.async {
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
    
    func startRecording() throws {
        guard permissionsGranted else {
            errorMessage = "Permissions not granted yet."
            return
        }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        transcript = ""
        
        let audioSession = AVAudioSession.sharedInstance()
        
        // Optimize audio session for low-latency speech recognition
        // .measurement mode minimizes system audio processing (like AGC) which reduces buffer latency
        // setting preferredIOBufferDuration to 0.005 (5ms) forces the hardware to deliver audio chunks faster
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
        try audioSession.setPreferredIOBufferDuration(0.005) 
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { fatalError("Unable to create request") }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Force on-device recognition if available to bypass all network latency
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentURL.appendingPathComponent("recording-\(Int(Date().timeIntervalSince1970)).caf")
        self.currentFileURL = fileURL
        
        let format = inputNode.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                self.stopRecording()
            }
        }
        
        // Use a smaller buffer size (1024 frames) so the speech recognizer gets data more frequently
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            self.recognitionRequest?.append(buffer)
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                self.logger.error("Error writing audio file: \(error.localizedDescription)")
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        errorMessage = nil
    }
    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioFile = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setActive(false)
        
        isRecording = false
    }
}
