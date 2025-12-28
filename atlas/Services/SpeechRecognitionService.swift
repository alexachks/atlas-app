//
//  SpeechRecognitionService.swift
//  To do App
//
//  Created by Claude Code on 12/21/25.
//

import Foundation
import AVFoundation
import Combine
internal import Auth

enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recordingFailed
    case transcriptionFailed(String)
    case invalidAudioFile

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Microphone access is required for voice input"
        case .recordingFailed:
            return "Failed to start audio recording"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .invalidAudioFile:
            return "Invalid audio file generated"
        }
    }
}

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject {
    static let shared = SpeechRecognitionService()

    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var isProcessing = false
    @Published var error: String?
    @Published var recordingDuration: TimeInterval = 0

    // MARK: - Private Properties
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private let supabase = SupabaseService.shared

    private let whisperURL = "https://sqchwnbwcnqegwtffxbz.supabase.co/functions/v1/whisper-proxy"

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        let status = AVAudioSession.sharedInstance().recordPermission

        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    // MARK: - Recording

    func startRecording() async throws {
        let totalStart = CFAbsoluteTimeGetCurrent()
        print("🎙️ [SpeechService] startRecording() called")

        await MainActor.run {
            isProcessing = true
        }

        defer {
            BackgroundTask { @MainActor in
                isProcessing = false
                let totalTime = CFAbsoluteTimeGetCurrent() - totalStart
                print("✅ [SpeechService] startRecording() defer - total time: \(String(format: "%.3f", totalTime))s")
            }
        }

        // Check permission (non-blocking async)
        let permStart = CFAbsoluteTimeGetCurrent()
        let hasPermission = await requestPermission()
        let permTime = CFAbsoluteTimeGetCurrent() - permStart
        print("🔐 [SpeechService] Permission check took \(String(format: "%.3f", permTime))s, granted: \(hasPermission)")

        guard hasPermission else {
            throw SpeechRecognitionError.notAuthorized
        }

        // Configure audio session on background thread to avoid blocking UI
        let sessionStart = CFAbsoluteTimeGetCurrent()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .default)
                    try audioSession.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        let sessionTime = CFAbsoluteTimeGetCurrent() - sessionStart
        print("🔊 [SpeechService] Audio session setup took \(String(format: "%.3f", sessionTime))s")

        // Create recording URL
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("voice_\(UUID().uuidString).m4a")

        // Configure recording settings
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        // Create recorder
        let recorderStart = CFAbsoluteTimeGetCurrent()
        audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
        audioRecorder?.delegate = self
        let recorderTime = CFAbsoluteTimeGetCurrent() - recorderStart
        print("📼 [SpeechService] Recorder creation took \(String(format: "%.3f", recorderTime))s")

        // Start recording
        let recordStart = CFAbsoluteTimeGetCurrent()
        guard audioRecorder?.record() == true else {
            throw SpeechRecognitionError.recordingFailed
        }
        let recordTime = CFAbsoluteTimeGetCurrent() - recordStart
        print("▶️ [SpeechService] record() call took \(String(format: "%.3f", recordTime))s")

        await MainActor.run {
            isRecording = true
            recordingStartTime = Date()
            error = nil
            startTimer()
        }

        print("🎤 [SpeechService] Recording started: \(audioURL.lastPathComponent)")
    }

    func stopRecording() async throws -> String {
        guard let recorder = audioRecorder, recorder.isRecording else {
            throw SpeechRecognitionError.recordingFailed
        }

        let audioURL = recorder.url
        recorder.stop()

        await MainActor.run {
            isRecording = false
            stopTimer()
        }

        // Deactivate audio session
        try AVAudioSession.sharedInstance().setActive(false)

        print("🛑 Recording stopped: \(audioURL.lastPathComponent)")
        if let fileSize = try? FileManager.default.attributeSize(audioURL) {
            print("📊 File size: \(fileSize) bytes")
        }

        // Transcribe
        let text = try await transcribeAudio(audioURL)

        // Clean up
        try? FileManager.default.removeItem(at: audioURL)

        return text
    }

    func cancelRecording() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        let audioURL = recorder.url
        recorder.stop()

        BackgroundTask { @MainActor in
            isRecording = false
            stopTimer()
        }

        // Clean up
        try? FileManager.default.removeItem(at: audioURL)
        try? AVAudioSession.sharedInstance().setActive(false)

        print("❌ Recording cancelled")
    }

    // MARK: - Timer

    private func startTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            _Concurrency.Task { @MainActor in
                guard let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        recordingStartTime = nil
    }

    // MARK: - Transcription

    private func transcribeAudio(_ audioURL: URL) async throws -> String {
        guard let session = supabase.session else {
            throw SpeechRecognitionError.transcriptionFailed("Not authenticated")
        }

        await MainActor.run {
            isTranscribing = true
        }

        defer {
            BackgroundTask { @MainActor in
                isTranscribing = false
            }
        }

        // Read audio file
        let audioData = try Data(contentsOf: audioURL)
        guard !audioData.isEmpty else {
            throw SpeechRecognitionError.invalidAudioFile
        }

        print("📤 Uploading audio for transcription: \(audioData.count) bytes")
        print("🔑 Auth token present: \(session.accessToken.prefix(20))...")
        print("🌐 URL: \(whisperURL)")

        // Create multipart form data
        let boundary = UUID().uuidString
        print("📦 Boundary: \(boundary)")
        var body = Data()

        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary (no language param = auto-detect)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        guard let url = URL(string: whisperURL) else {
            throw SpeechRecognitionError.transcriptionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Send request
        print("📡 Sending request to Whisper API...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw SpeechRecognitionError.transcriptionFailed("Invalid response")
        }

        print("📥 Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Error response: \(errorMessage)")
            throw SpeechRecognitionError.transcriptionFailed("Status \(httpResponse.statusCode): \(errorMessage)")
        }

        // Parse response
        struct WhisperResponse: Codable {
            let text: String
        }

        let decoder = JSONDecoder()
        let whisperResponse = try decoder.decode(WhisperResponse.self, from: data)

        print("✅ Transcription successful: \(whisperResponse.text)")

        return whisperResponse.text
    }
}

// MARK: - AVAudioRecorderDelegate

extension SpeechRecognitionService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("🎵 Recording finished: \(flag ? "success" : "failure")")
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Recording error: \(error?.localizedDescription ?? "unknown")")
        BackgroundTask { @MainActor in
            self.error = error?.localizedDescription
            self.isRecording = false
        }
    }
}

// MARK: - Helper Extensions

extension FileManager {
    func attributeSize(_ url: URL) throws -> Int {
        let attributes = try attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int ?? 0
    }
}
