//
//  StartupMetricsExporter.swift
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
import os.log
import PixelKit
import PrivacyConfig

/// Represents an Error that prevented us from exporting the Startup Stats
///
enum StartupMetricsExporterError: Error {
    case errorEncoding
    case errorSaving
}

// MARK: - StartupMetricsExporter

final class StartupMetricsExporter {

    private let profiler: StartupProfiler

    init(profiler: StartupProfiler) {
        self.profiler = profiler
    }

    /// Exports a fresh MemoryAllocationStats to the specified URL
    ///
    func exportMetrics(targetURL: URL) throws {
        let metrics = profiler.exportMetrics()
        let encoded = try encodeToJSON(snapshot: metrics)

        try write(payload: encoded, to: targetURL)
    }

    /// Exports the latest `StartupMetrics` as reported by `StartupProfiler` into a Temporary URL: `/tmp/[Bundle-ID]-startup-metrics.json`
    ///
    @discardableResult
    func exportMetricsToTemporaryURL() throws -> URL {
        let targetURL = URL.temporaryStartupMetricsExportURL
        try exportMetrics(targetURL: targetURL)
        return targetURL
    }
}

private extension StartupMetricsExporter {

    func encodeToJSON(snapshot: StartupMetrics) throws -> Data {
        do {
            return try JSONEncoder().encode(snapshot)
        } catch {
            throw StartupMetricsExporterError.errorEncoding
        }
    }

    func write(payload: Data, to targetURL: URL) throws {
        do {
            try payload.write(to: targetURL, options: .atomic)
        } catch {
            throw StartupMetricsExporterError.errorSaving
        }
    }
}

private extension URL {

    /// Our Temporary Stats URL is in `/tmp` as `FileManager.default.temporaryDirectory` will always point to a different location
    /// due to the macOS Sandbox.
    ///
    /// Since this URL will be required by the CI Runner as well, we're using a globally accessible and temporary location
    /// within the filesystem.
    ///
    static var temporaryStartupMetricsExportURL: URL {
        let filename = Bundle.main.bundleIdentifier ?? "com.duckduckgo.macos.browser"
        return URL(fileURLWithPath: "/tmp/\(filename)-startup-metrics.json")
    }
}
