//
//  WebPageTranslationDebugView.swift
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

// Throwaway spike debug settings UI.
// ponytail: @State + .onChange write-back pattern; TranslationDebugSettings is a plain class (not Observable)

import SwiftUI

struct WebPageTranslationDebugView: View {
    private let settings = TranslationDebugSettings()
    @State private var scope: TranslationExtractionScope
    @State private var detector: TranslationDetector
    @State private var report: Bool
    @State private var detectionInput: TranslationDetectionInput
    @State private var legacyScript: Bool

    init() {
        let s = TranslationDebugSettings()
        _scope = State(initialValue: s.extractionScope)
        _detector = State(initialValue: s.detector)
        _report = State(initialValue: s.diagnosticReportEnabled)
        _detectionInput = State(initialValue: s.detectionInput)
        _legacyScript = State(initialValue: s.useLegacyScript)
    }

    var body: some View {
        Form {
            Picker("Extraction scope", selection: $scope) {
                Text("Viewport only").tag(TranslationExtractionScope.viewportOnly)
                Text("Batches").tag(TranslationExtractionScope.batches)
                Text("Full page (HTML, no extraction)").tag(TranslationExtractionScope.fullPageHTML)
                Text("Full page (extracted, single batch)").tag(TranslationExtractionScope.fullPageExtracted)
            }
            Picker("Language detector", selection: $detector) {
                Text("NaturalLanguage").tag(TranslationDetector.naturalLanguage)
                Text("CLD2").tag(TranslationDetector.cld2)
            }
            Picker("Detection input", selection: $detectionInput) {
                Text("HTML, full page").tag(TranslationDetectionInput.htmlFullPage)
                Text("HTML, first 50").tag(TranslationDetectionInput.htmlFirst50)
                Text("Text (stripped), full page").tag(TranslationDetectionInput.textFullPage)
                Text("Text (stripped), first 50").tag(TranslationDetectionInput.textFirst50)
                Text("Native sample (innerText + lang)").tag(TranslationDetectionInput.nativeSample)
            }
            Toggle("Diagnostic report", isOn: $report)
            Toggle("Legacy translation.js (instead of C-S-S)", isOn: $legacyScript)
        }
        .navigationTitle("Web Page Translation")
        .onChange(of: scope) { newValue in settings.extractionScope = newValue }
        .onChange(of: detector) { newValue in settings.detector = newValue }
        .onChange(of: detectionInput) { newValue in settings.detectionInput = newValue }
        .onChange(of: report) { newValue in settings.diagnosticReportEnabled = newValue }
        .onChange(of: legacyScript) { newValue in settings.useLegacyScript = newValue }
    }
}
