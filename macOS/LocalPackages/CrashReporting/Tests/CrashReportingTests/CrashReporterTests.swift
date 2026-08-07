//
//  CrashReporterTests.swift
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
import Testing

@testable import CrashReporting

struct CrashReporterTests {

    private let day: TimeInterval = 24 * 60 * 60

    @Test("Crash reports older than the pixel age limit are excluded from pixel reporting", .timeLimit(.minutes(1)))
    func crashReportsOlderThanAgeLimitAreExcludedFromPixelReporting() {
        let now = Date()
        let recent = makeReport(named: "DuckDuckGo-recent.crash", creationDate: now.addingTimeInterval(-3 * day))
        let stale = makeReport(named: "DuckDuckGo-stale.crash", creationDate: now.addingTimeInterval(-10 * day))

        let eligible = CrashReporter.crashReportsEligibleForPixelReporting([recent, stale], now: now)

        #expect(eligible.map(\.url) == [recent.url])
    }

    @Test("Crash reports within the pixel age limit are included in pixel reporting", .timeLimit(.minutes(1)))
    func crashReportsWithinAgeLimitAreIncludedInPixelReporting() {
        let now = Date()
        let recent = makeReport(named: "DuckDuckGo-recent.crash", creationDate: now.addingTimeInterval(-6 * day))

        let eligible = CrashReporter.crashReportsEligibleForPixelReporting([recent], now: now)

        #expect(eligible.count == 1)
    }

    // MARK: - Helpers

    private func makeReport(named name: String, creationDate: Date) -> LegacyCrashReport {
        let fileManager = MockFileManager()
        let url = FileManager.userDiagnosticReports.appendingPathComponent(name)
        fileManager.registerFile(at: url, in: FileManager.userDiagnosticReports, contents: "Process: DuckDuckGo [123]", creationDate: creationDate)
        return LegacyCrashReport(url: url, fileManager: fileManager)
    }
}
