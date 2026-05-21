//
//  FilePreviewHelperTests.swift
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

@Suite("FilePreviewHelper")
struct FilePreviewHelperTests {

    // MARK: - handlesDownloadNatively

    @Test("Returns true for text/calendar MIME regardless of URL/filename")
    func handlesDownloadNativelyMatchesByMIME() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .calendar,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: "download.bin",
            featureFlagger: flagger
        ))
    }

    @Test("Returns true when URL ends in .ics")
    func handlesDownloadNativelyMatchesByURLExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/event.ics"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    @Test("Returns true when filename ends in .ics (dynamic URL via Content-Disposition)")
    func handlesDownloadNativelyMatchesByFilenameExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    @Test("Returns false when no signal indicates ICS")
    func handlesDownloadNativelyRejectsUnrelatedDownloads() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(!FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/file.pdf"),
            filename: "file.pdf",
            featureFlagger: flagger
        ))
    }

    @Test("Returns false when feature flag is off, even with all positive signals")
    func handlesDownloadNativelyRespectsFeatureFlag() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(!FilePreviewHelper.handlesDownloadNatively(
            mimeType: .calendar,
            url: URL(string: "https://example.com/event.ics"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    @Test("Matches URL extension case-insensitively")
    func handlesDownloadNativelyMatchesUppercaseExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/EVENT.ICS"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    // MARK: - shouldPersistInDownloads

    @Test("Persists when MIME is text/calendar")
    func shouldPersistMatchesByMIME() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .calendar,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    @Test("Persists when filename ends in .ics even if URL doesn't")
    func shouldPersistMatchesByFilenameExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .unknown,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    @Test("Does not persist when feature flag is off")
    func shouldPersistRespectsFeatureFlag() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(!FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .calendar,
            url: URL(string: "https://example.com/event.ics"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }
}
