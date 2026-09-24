//
//  TranslationDiagnosticReport.swift
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

// Throwaway spike. Post-run diagnostic report model + SwiftUI sheet.
// ponytail: plain struct, not Observable — throwaway spike only

import SwiftUI

struct TranslationDiagnosticReport {
    struct Bergamot {
        let modelTier: String
        let modelLoadSeconds: Double
        let downloadBytes: Int64?
        let downloadSeconds: Double?
    }

    let engine: String
    let languagePair: String
    let extractionScope: String
    let detector: String
    let detectionInput: String
    let detectedSourceLanguage: String?
    let detectionSeconds: Double?
    let nodesExtracted: Int
    let uniqueUnits: Int
    let viewportCount: Int
    let timeToViewportSeconds: Double?
    let fullPageSeconds: Double
    let throughput: Double
    let bergamot: Bergamot?
    let errorMessage: String?

    var summaryLines: [String] {
        var l: [String] = []
        if let err = errorMessage {
            l.append("⚠️ Error: \(err)")
        }
        l.append("Engine: \(engine)")
        l.append("Language: \(languagePair)")
        l.append("Extraction scope: \(extractionScope)")
        l.append("Detector: \(detector) (\(detectionInput))  \u{2192}  detected: \(detectedSourceLanguage ?? "\u{2014}")  in \(detectionSeconds.map { String(format: "%.3fs", $0) } ?? "\u{2014}")")
        l.append("Nodes: \(nodesExtracted)   Unique: \(uniqueUnits)   Viewport: \(viewportCount)")
        l.append(String(format: "Time to viewport: %@", timeToViewportSeconds.map { String(format: "%.1fs", $0) } ?? "\u{2014}"))
        l.append(String(format: "Full page: %.1fs", fullPageSeconds))
        l.append(String(format: "Throughput: %.1f str/s", throughput))
        if let b = bergamot {
            l.append("Model tier: \(b.modelTier)")
            l.append(String(format: "Model load: %.1fs", b.modelLoadSeconds))
            if let bytes = b.downloadBytes, let secs = b.downloadSeconds {
                l.append(String(format: "Download: %.1f MB in %.1fs", Double(bytes) / 1_000_000, secs))
            }
        }
        return l
    }
}

struct TranslationDiagnosticReportView: View {
    let report: TranslationDiagnosticReport

    var body: some View {
        NavigationView {
            List(Array(report.summaryLines.enumerated()), id: \.offset) {
                Text($0.element).font(.system(.body, design: .monospaced))
            }
            .navigationTitle("Translation Report")
        }
    }
}
