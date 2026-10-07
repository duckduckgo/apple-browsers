//
//  VoiceSearchSpeechRecognizer.swift
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
import PrivacyConfig
import FeatureFlags_iOS

final class VoiceSearchSpeechRecognizer: SpeechRecognizerProtocol {
    private let featureFlagger: FeatureFlagger
    private let legacy: SpeechRecognizerProtocol
    private let makeAnalyzerRecognizer: () async -> SpeechRecognizerProtocol?
    private var activeRecognizer: SpeechRecognizerProtocol?
    private var selectionTask: Task<Void, Never>?

    init(featureFlagger: FeatureFlagger,
         legacy: SpeechRecognizerProtocol = SpeechRecognizer(),
         makeAnalyzerRecognizer: @escaping () async -> SpeechRecognizerProtocol? = {
             if #available(iOS 26, *), let locale = await SpeechAnalyzerRecognizer.supportedLocale() {
                 return SpeechAnalyzerRecognizer(locale: locale)
             }
             return nil
         }) {
        self.featureFlagger = featureFlagger
        self.legacy = legacy
        self.makeAnalyzerRecognizer = makeAnalyzerRecognizer
    }

    var isAvailable: Bool { legacy.isAvailable || Self.isAnalyzerEnabled(using: featureFlagger) }
    var requiresPreparation: Bool { Self.isAnalyzerEnabled(using: featureFlagger) }

    static func isAnalyzerEnabled(using featureFlagger: FeatureFlagger) -> Bool {
        if #available(iOS 26, *) {
            return featureFlagger.isFeatureOn(.speechAnalyzer) && SpeechAnalyzerRecognizer.isSupported
        }
        return false
    }

    static func requestMicAccess(withHandler handler: @escaping (Bool) -> Void) {
        SpeechRecognizer.requestMicAccess(withHandler: handler)
    }

    func getVolumeLevel(from channelData: UnsafeMutablePointer<Float>) -> Float {
        legacy.getVolumeLevel(from: channelData)
    }

    func startRecording(resultHandler: @escaping (String?, Error?, Bool) -> Void,
                        volumeCallback: @escaping (Float) -> Void) {
        stopRecording()
        let useAnalyzer = featureFlagger.isFeatureOn(.speechAnalyzer)
        selectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let modern = useAnalyzer ? await self.makeAnalyzerRecognizer() : nil
            guard !Task.isCancelled else { return }
            let recognizer = modern ?? self.legacy
            self.activeRecognizer = recognizer
            recognizer.startRecording(resultHandler: resultHandler, volumeCallback: volumeCallback)
        }
    }

    func stopRecording() {
        selectionTask?.cancel()
        selectionTask = nil
        activeRecognizer?.stopRecording()
        activeRecognizer = nil
    }

    deinit {
        stopRecording()
    }
}
