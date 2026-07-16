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

    @available(iOS 16, *)
    @Test("Returns true for text/calendar MIME regardless of URL/filename", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyMatchesByMIME() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .calendar,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: "download.bin",
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Returns true when URL ends in .ics", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyMatchesByURLExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/event.ics"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Returns true when filename ends in .ics (dynamic URL via Content-Disposition)", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyMatchesByFilenameExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Returns false when no signal indicates ICS", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyRejectsUnrelatedDownloads() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(!FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/file.pdf"),
            filename: "file.pdf",
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Returns false when feature flag is off, even with all positive signals", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyRespectsFeatureFlag() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(!FilePreviewHelper.handlesDownloadNatively(
            mimeType: .calendar,
            url: URL(string: "https://example.com/event.ics"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Matches URL extension case-insensitively", .timeLimit(.minutes(1)))
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

    @available(iOS 16, *)
    @Test("Persists when MIME is text/calendar", .timeLimit(.minutes(1)))
    func shouldPersistMatchesByMIME() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .calendar,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Persists when filename ends in .ics even if URL doesn't", .timeLimit(.minutes(1)))
    func shouldPersistMatchesByFilenameExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [.icsCalendarLinks])
        #expect(FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .unknown,
            url: URL(string: "https://example.com/calendar?id=abc"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Does not persist when feature flag is off", .timeLimit(.minutes(1)))
    func shouldPersistRespectsFeatureFlag() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(!FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .calendar,
            url: URL(string: "https://example.com/event.ics"),
            filename: "event.ics",
            featureFlagger: flagger
        ))
    }

    // MARK: - vCard handlesDownloadNatively

    @available(iOS 16, *)
    @Test("Returns true for text/vcard MIME", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyMatchesByVCardMIME() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .contact,
            url: URL(string: "https://example.com/contact?id=abc"),
            filename: "download.bin",
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Returns true when URL ends in .vcf", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyMatchesByVCFURLExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/contact.vcf"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Returns true when filename ends in .vcard (dynamic URL via Content-Disposition)", .timeLimit(.minutes(1)))
    func handlesDownloadNativelyMatchesByVCardFilenameExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(FilePreviewHelper.handlesDownloadNatively(
            mimeType: .unknown,
            url: URL(string: "https://example.com/contact?id=abc"),
            filename: "contact.vcard",
            featureFlagger: flagger
        ))
    }

    // MARK: - vCard shouldPersistInDownloads

    @available(iOS 16, *)
    @Test("Persists when MIME is text/vcard", .timeLimit(.minutes(1)))
    func shouldPersistMatchesByVCardMIME() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .contact,
            url: URL(string: "https://example.com/contact?id=abc"),
            filename: nil,
            featureFlagger: flagger
        ))
    }

    @available(iOS 16, *)
    @Test("Persists when filename ends in .vcf even if URL doesn't", .timeLimit(.minutes(1)))
    func shouldPersistMatchesByVCFFilenameExtension() {
        let flagger = MockFeatureFlagger(enabledFeatureFlags: [])
        #expect(FilePreviewHelper.shouldPersistInDownloads(
            mimeType: .unknown,
            url: URL(string: "https://example.com/contact?id=abc"),
            filename: "contact.vcf",
            featureFlagger: flagger
        ))
    }

    // MARK: - canAutoPreviewVCardByExtension

    @available(iOS 16, *)
    @Test("Auto-previews .vcf by URL extension", .timeLimit(.minutes(1)))
    func canAutoPreviewVCardByURLExtension() {
        #expect(FilePreviewHelper.canAutoPreviewVCardByExtension(
            url: URL(string: "https://example.com/contact.VCF"),
            filename: nil
        ))
    }

    @available(iOS 16, *)
    @Test("Auto-previews .vcard by filename", .timeLimit(.minutes(1)))
    func canAutoPreviewVCardByFilenameExtension() {
        #expect(FilePreviewHelper.canAutoPreviewVCardByExtension(
            url: URL(string: "https://example.com/contact?id=abc"),
            filename: "contact.vcard"
        ))
    }
}
