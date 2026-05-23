//
//  CompleteDownloadRowViewModelTests.swift
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

import BrowserServicesKit
import Core
import Foundation
import Testing
@testable import DuckDuckGo

@Suite("CompleteDownloadRowViewModel")
struct CompleteDownloadRowViewModelTests {

    @available(iOS 17, *)
    @Test("Returns a prepared event for a single-VEVENT .ics file when the flag is on", .timeLimit(.minutes(1)))
    func preparesEventForSingleVEvent() throws {
        let url = try writeICSFile(name: "single.ics", contents: Fixtures.singleEvent)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url, featureFlagger: flaggerWithICSOn())
        let prepared = viewModel.preparePreviewEvent()

        #expect(prepared != nil)
        #expect(prepared?.event.title == "Single Event")
    }

    @available(iOS 17, *)
    @Test("Returns nil when the feature flag is off", .timeLimit(.minutes(1)))
    func returnsNilWhenFlagIsOff() throws {
        let url = try writeICSFile(name: "single.ics", contents: Fixtures.singleEvent)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url, featureFlagger: MockFeatureFlagger())
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    @available(iOS 17, *)
    @Test("Returns nil for a non-.ics file even when the flag is on", .timeLimit(.minutes(1)))
    func returnsNilForNonICSExtension() throws {
        let url = try writeICSFile(name: "calendar.txt", contents: Fixtures.singleEvent)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url, featureFlagger: flaggerWithICSOn())
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    @available(iOS 17, *)
    @Test("Returns nil for a multi-VEVENT file", .timeLimit(.minutes(1)))
    func returnsNilForMultipleEvents() throws {
        let url = try writeICSFile(name: "multi.ics", contents: Fixtures.multipleEvents)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url, featureFlagger: flaggerWithICSOn())
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    @available(iOS 17, *)
    @Test("Returns nil for malformed .ics content", .timeLimit(.minutes(1)))
    func returnsNilForMalformedContent() throws {
        let url = try writeICSFile(name: "broken.ics", contents: "not a calendar")
        defer { try? FileManager.default.removeItem(at: url) }

        let viewModel = CompleteDownloadRowViewModel(fileURL: url, featureFlagger: flaggerWithICSOn())
        #expect(viewModel.preparePreviewEvent() == nil)
    }

    // MARK: - Helpers

    private func flaggerWithICSOn() -> MockFeatureFlagger {
        MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
    }

    private func writeICSFile(name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private enum Fixtures {
        static let singleEvent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:single@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:Single Event
        END:VEVENT
        END:VCALENDAR
        """

        static let multipleEvents = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:a@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:First Event
        END:VEVENT
        BEGIN:VEVENT
        UID:b@example.com
        DTSTART:20260602T140000Z
        DTEND:20260602T150000Z
        SUMMARY:Second Event
        END:VEVENT
        END:VCALENDAR
        """
    }
}
