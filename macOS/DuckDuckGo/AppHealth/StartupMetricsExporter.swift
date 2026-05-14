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

/// Represents an Error that prevented us from exporting the Startup Stats
///
enum StartupMetricsExporterError: Error {
    case errorEncoding
    case errorSaving
}

// MARK: - StartupMetricsExporter

final class StartupMetricsExporter {

    private let profiler: StartupProfiler
    private let previousSessionRestored: Bool
    private let windowContext: WindowContext

    init(profiler: StartupProfiler, previousSessionRestored: Bool, windowContext: WindowContext) {
        self.profiler = profiler
        self.previousSessionRestored = previousSessionRestored
        self.windowContext = windowContext
    }

    /// Exports the latest `StartupMetrics` as reported by `StartupProfiler` to the specified URL
    ///
    func exportMetrics(targetURL: URL) throws {
        let metrics = profiler.exportMetrics()
        let payload = ExportStartupMetrics(metrics: metrics, previousSessionRestored: previousSessionRestored, windowContext: windowContext)
        let encoded = try encodeToJSON(payload: payload)
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

    func encodeToJSON(payload: ExportStartupMetrics) throws -> Data {
        do {
            return try JSONEncoder().encode(payload)
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

// MARK: - ExportStartupMetrics

/// This Transfer Object is a helper that allows us encode the StartupMetrics in a format ready for usage in `macOS Performance Tests`
private struct ExportStartupMetrics: Encodable {
    let metrics: StartupMetrics
    let previousSessionRestored: Bool
    let windowContext: WindowContext
}

private extension ExportStartupMetrics {

    enum CodingKeys: String, CodingKey {
        case pinnedTabs
        case sessionRestoration
        case standardTabs
        case windows
        case appDelegateInit
        case appWillFinishLaunching
        case appDidFinishLaunchingBeforeRestoration
        case appDidFinishLaunchingAfterRestoration
        case appStateRestoration
        case appDelegateInitToWillFinishLaunching
        case appWillFinishToDidFinishLaunching
        case mainMenuInit
        case timeToInteractive
    }

    func encode(to encoder: Encoder) throws {
        try encodeContext(to: encoder)
        try encodeMetrics(to: encoder)
    }

    func encodeContext(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(windowContext.pinnedTabs, forKey: .pinnedTabs)
        try container.encode(previousSessionRestored, forKey: .sessionRestoration)
        try container.encode(windowContext.standardTabs, forKey: .standardTabs)
        try container.encode(windowContext.windows, forKey: .windows)
    }

    func encodeMetrics(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        let keysToMilliseconds: [(CodingKeys, TimeInterval)] = StartupStep.allCases.compactMap { step in
            guard let duration = metrics.duration(step: step), let codingKey = CodingKeys(rawValue: step.rawValue) else {
                assertionFailure()
                return nil
            }

            return (codingKey, duration.toMilliseconds)
        }

        for (codingKey, milliseconds) in keysToMilliseconds {
            try container.encode(milliseconds, forKey: codingKey)
        }

        if let deltaMS = metrics.timeElapsedBetween(endOf: .appDelegateInit, startOf: .appWillFinishLaunching)?.toMilliseconds {
            try container.encode(deltaMS, forKey: .appDelegateInitToWillFinishLaunching)
        }

        if let deltaMS = metrics.timeElapsedBetween(endOf: .appWillFinishLaunching, startOf: .appDidFinishLaunchingBeforeRestoration)?.toMilliseconds {
            try container.encode(deltaMS, forKey: .appWillFinishToDidFinishLaunching)
        }
    }
}

// MARK: - TimeInterval Private Helpers

private extension TimeInterval {

    var toMilliseconds: TimeInterval {
        self * 1000
    }
}
