//
//  SpeechAnalyzerRecognizer.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Speech
import AVFoundation

@available(iOS 26, *)
final class SpeechAnalyzerRecognizer: SpeechRecognizerProtocol {
    static var isSupported: Bool { SpeechTranscriber.isAvailable }
    var isAvailable: Bool { Self.isSupported }
    var requiresPreparation: Bool { true }

    private let locale: Locale
    private var recordingTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var latestTranscription: String?
    private var tapInstalled = false
    private var analyzer: SpeechAnalyzer?
    private var audioEngine: AVAudioEngine?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    init(locale: Locale) {
        self.locale = locale
    }

    static func supportedLocale() async -> Locale? {
        guard isSupported else { return nil }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
    }

    static func requestMicAccess(withHandler handler: @escaping (Bool) -> Void) {
        SpeechRecognizer.requestMicAccess(withHandler: handler)
    }

    func getVolumeLevel(from channelData: UnsafeMutablePointer<Float>) -> Float {
        Self.volumeLevel(channelData, frameCount: 1024)
    }

    private static func volumeLevel(_ channelData: UnsafePointer<Float>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }
        let samples = UnsafeBufferPointer(start: channelData, count: frameCount)
        let average = samples.reduce(0) { $0 + abs($1) } / Float(frameCount)
        return (min(max(average, 0.003), 0.07) - 0.003) / (0.07 - 0.003)
    }

    func startRecording(resultHandler: @escaping (String?, Error?, Bool) -> Void,
                        volumeCallback: @escaping (Float) -> Void) {
        stopRecording()
        recordingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let transcriber = SpeechTranscriber(locale: self.locale, preset: .progressiveTranscription)
                try await self.installAssets(for: transcriber)
                try Task.checkCancellation()
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                    throw SpeechRecognizerError.audioInputUnavailable
                }
                try Task.checkCancellation()
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                self.analyzer = analyzer
                try await analyzer.prepareToAnalyze(in: format)
                try Task.checkCancellation()
                let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                self.inputContinuation = continuation
                self.readResults(from: transcriber, resultHandler: resultHandler)
                try self.startAudioEngine(format: format, continuation: continuation,
                                          resultHandler: resultHandler, volumeCallback: volumeCallback)
                try await analyzer.start(inputSequence: inputs)
            } catch {
                guard !Task.isCancelled else { return }
                self.stopRecording()
                resultHandler(nil, error, true)
            }
        }
    }

    private func installAssets(for transcriber: SpeechTranscriber) async throws {
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
        } catch {
            throw SpeechRecognizerError.modelUnavailable
        }
    }

    private func readResults(from transcriber: SpeechTranscriber, resultHandler: @escaping (String?, Error?, Bool) -> Void) {
        resultsTask = Task { @MainActor [weak self] in
            var finalizedText = ""
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { return }
                    let text = String(result.text.characters)
                    let transcription = finalizedText + text
                    self?.latestTranscription = transcription
                    if result.isFinal { finalizedText = transcription }
                    resultHandler(transcription, nil, result.isFinal)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self?.stopRecording()
                resultHandler(nil, error, true)
            }
        }
    }

    private func startAudioEngine(format: AVAudioFormat,
                                  continuation: AsyncStream<AnalyzerInput>.Continuation,
                                  resultHandler: @escaping (String?, Error?, Bool) -> Void,
                                  volumeCallback: @escaping (Float) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true)
        let engine = AVAudioEngine()
        self.audioEngine = engine
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard SpeechRecognizer.isValidRecordingFormat(sourceFormat),
              let converter = AVAudioConverter(from: sourceFormat, to: format) else {
            throw SpeechRecognizerError.audioInputUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { buffer, _ in
            if let samples = buffer.floatChannelData?[0] {
                volumeCallback(Self.volumeLevel(samples, frameCount: Int(buffer.frameLength)))
            }
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / sourceFormat.sampleRate))
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            if let conversionError {
                continuation.finish()
                resultHandler(nil, conversionError, true)
            } else if converted.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        tapInstalled = true
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let text = self.latestTranscription
                self.stopRecording()
                resultHandler(text, nil, true)
            } catch { }
        }
        engine.prepare()
        try engine.start()
    }

    func stopRecording() {
        recordingTask?.cancel()
        recordingTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        latestTranscription = nil
        if let audioEngine {
            audioEngine.stop()
            if tapInstalled { audioEngine.inputNode.removeTap(onBus: 0) }
            tapInstalled = false
            self.audioEngine = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            self.analyzer = nil
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    deinit {
        stopRecording()
    }
}
