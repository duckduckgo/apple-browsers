//
//  TranslationDebugSettings.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

// Throwaway spike debug settings for web-page translation POC.
// ponytail: plain UserDefaults wrapper, no KeyValueStore — throwaway spike only

import Foundation

enum TranslationExtractionScope: String, CaseIterable {
    case viewportOnly        // translate only the viewport-visible blocks
    case batches             // extract blocks, translate viewport-first then the rest in chunks
    case fullPageHTML        // no extraction: translate the whole page's innerHTML as one blob
    case fullPageExtracted   // extract all blocks, translate them all in a single batch
}
enum TranslationDetector: String, CaseIterable { case naturalLanguage, cld2 }

enum TranslationDetectionInput: String, CaseIterable {
    case htmlFirst50        // HTML, first 50 units      (current behaviour = default)
    case htmlFullPage       // HTML, full page
    case textFirst50        // stripped text, first 50 units
    case textFullPage       // stripped text, full page
    case nativeSample       // native reads body.innerText (first 4 KB) + <html lang>, no C-S-S involvement
    var stripsHTML: Bool { self == .textFirst50 || self == .textFullPage }
    var usesFullPage: Bool { self == .htmlFullPage || self == .textFullPage }
}

final class TranslationDebugSettings {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var extractionScope: TranslationExtractionScope {
        get { defaults.string(forKey: "translationDebug.extractionScope").flatMap(TranslationExtractionScope.init(rawValue:)) ?? .batches }
        set { defaults.set(newValue.rawValue, forKey: "translationDebug.extractionScope") }
    }
    var detector: TranslationDetector {
        get { defaults.string(forKey: "translationDebug.detector").flatMap(TranslationDetector.init(rawValue:)) ?? .naturalLanguage }
        set { defaults.set(newValue.rawValue, forKey: "translationDebug.detector") }
    }
    var diagnosticReportEnabled: Bool {
        get { defaults.bool(forKey: "translationDebug.diagnosticReportEnabled") }   // absent → false, correct default
        set { defaults.set(newValue, forKey: "translationDebug.diagnosticReportEnabled") }
    }
    /// Old path: inject translation.js and call `window.__ddgPOC`. Off → the C-S-S `pageTranslation` feature.
    var useLegacyScript: Bool {
        get { defaults.bool(forKey: "translationDebug.useLegacyScript") }
        set { defaults.set(newValue, forKey: "translationDebug.useLegacyScript") }
    }
    var detectionInput: TranslationDetectionInput {
        get { defaults.string(forKey: "translationDebug.detectionInput").flatMap(TranslationDetectionInput.init(rawValue:)) ?? .htmlFirst50 }
        set { defaults.set(newValue.rawValue, forKey: "translationDebug.detectionInput") }
    }
}
