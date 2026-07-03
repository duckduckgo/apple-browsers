//
//  CalendarEventPreviewHelperTests.swift
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
import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("CalendarEventPreviewHelper")
struct CalendarEventPreviewHelperTests {

    @available(iOS 17.0, *)
    @Test("Malformed .ics reports a parse failure without presenting QuickLook", .timeLimit(.minutes(1)))
    func parseFailureReportsFailureWithoutQuickLook() throws {
        let url = try writeICSFile("not even close to a calendar file")
        defer { try? FileManager.default.removeItem(at: url) }

        let viewController = UIViewController()
        var quickLookPresentations = 0
        var reportedFailure: CalendarEventPreviewHelper.Failure?
        var didDismiss = false

        let helper = CalendarEventPreviewHelper(url, viewController: viewController) { _, _, completion in
            quickLookPresentations += 1
            completion()
        }
        helper.onFailure = { reportedFailure = $0 }
        helper.onDismiss = { didDismiss = true }
        helper.preview()

        #expect(quickLookPresentations == 0)
        #expect(reportedFailure == .parseFailure)
        #expect(didDismiss)
    }

    @available(iOS 17.0, *)
    @Test("Multi-event .ics still falls back to QuickLook", .timeLimit(.minutes(1)))
    func multipleEventsFallsBackToQuickLook() throws {
        let url = try writeICSFile(Fixtures.multipleEvents)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewController = UIViewController()
        var quickLookPresentations = 0
        var reportedFailure: CalendarEventPreviewHelper.Failure?

        let helper = CalendarEventPreviewHelper(url, viewController: viewController) { _, _, completion in
            quickLookPresentations += 1
            completion()
        }
        helper.onFailure = { reportedFailure = $0 }
        helper.preview()

        #expect(quickLookPresentations == 1)
        #expect(reportedFailure == .multipleEvents)
    }

    @available(iOS 17.0, *)
    @Test("Unrecognized-time-zone .ics still falls back to QuickLook", .timeLimit(.minutes(1)))
    func unrecognizedTimeZoneFallsBackToQuickLook() throws {
        let url = try writeICSFile(Fixtures.unrecognizedTimeZone)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewController = UIViewController()
        var quickLookPresentations = 0
        var reportedFailure: CalendarEventPreviewHelper.Failure?

        let helper = CalendarEventPreviewHelper(url, viewController: viewController) { _, _, completion in
            quickLookPresentations += 1
            completion()
        }
        helper.onFailure = { reportedFailure = $0 }
        helper.preview()

        #expect(quickLookPresentations == 1)
        #expect(reportedFailure == .unrecognizedTimeZone)
    }

    @available(iOS 17.0, *)
    @Test("Parse failure does not leak the helper", .timeLimit(.minutes(1)))
    func parseFailureDoesNotLeakHelper() throws {
        let url = try writeICSFile("not even close to a calendar file")
        defer { try? FileManager.default.removeItem(at: url) }

        let viewController = UIViewController()
        weak var weakHelper: CalendarEventPreviewHelper?
        do {
            let helper = CalendarEventPreviewHelper(url, viewController: viewController) { _, _, completion in
                completion()
            }
            weakHelper = helper
            helper.preview()
        }

        #expect(weakHelper == nil)
    }

    // MARK: - Helpers

    private func writeICSFile(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".ics")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private enum Fixtures {
        static let multipleEvents = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:first@example.com
        DTSTART:20260601T140000Z
        DTEND:20260601T150000Z
        SUMMARY:First Event
        END:VEVENT
        BEGIN:VEVENT
        UID:second@example.com
        DTSTART:20260602T140000Z
        DTEND:20260602T150000Z
        SUMMARY:Second Event
        END:VEVENT
        END:VCALENDAR
        """

        static let unrecognizedTimeZone = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Test//EN
        BEGIN:VEVENT
        UID:badtz@example.com
        DTSTART;TZID=Definitely Not A Real Timezone:20260601T140000
        DTEND;TZID=Definitely Not A Real Timezone:20260601T150000
        SUMMARY:Unknown TZID
        END:VEVENT
        END:VCALENDAR
        """
    }
}
