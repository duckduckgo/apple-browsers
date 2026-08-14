//
//  DuckAiUsageLimitsTests.swift
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

import DuckAiDataStore
import XCTest
@testable import AIChat

final class DuckAiUsageLimitsTests: XCTestCase {

    /// Fixed "now" for every case, so the future/past timestamps below read unambiguously.
    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
    private let future = "2026-08-14T00:00:00.000Z"
    private let alsoFuture = "2026-08-17T00:00:00.000Z"
    private let past = "2024-01-01T00:00:00.000Z"

    // MARK: - Well-formed payloads

    func testWhenBothWindowsPresentThenBothDecode() {
        let limits = decode(#"{"daily":{"percentUsed":42.5,"resetsAt":"\#(future)"},"weekly":{"percentUsed":63,"resetsAt":"\#(alsoFuture)"}}"#)

        XCTAssertEqual(limits.daily?.percentUsed, 42.5)
        XCTAssertEqual(limits.daily?.resetsAt, date(future))
        XCTAssertEqual(limits.weekly?.percentUsed, 63)
        XCTAssertEqual(limits.weekly?.resetsAt, date(alsoFuture))
        XCTAssertTrue(limits.hasData)
    }

    func testWhenOnlyDailyPresentThenWeeklyIsNilRatherThanZero() {
        let limits = decode(#"{"daily":{"percentUsed":10,"resetsAt":"\#(future)"}}"#)

        XCTAssertEqual(limits.daily?.percentUsed, 10)
        XCTAssertNil(limits.weekly)
    }

    func testWhenOnlyWeeklyPresentThenDailyIsNilRatherThanZero() {
        let limits = decode(#"{"weekly":{"percentUsed":10,"resetsAt":"\#(future)"}}"#)

        XCTAssertEqual(limits.weekly?.percentUsed, 10)
        XCTAssertNil(limits.daily)
    }

    /// The web app writes a snapshot on every usage-state update, so a field it adds later must not
    /// take the whole payload down with it.
    func testWhenPayloadCarriesUnknownFieldsThenTheyAreIgnored() {
        let limits = decode(#"{"schemaVersion":2,"monthly":{"percentUsed":1,"resetsAt":"\#(future)"},"daily":{"percentUsed":5,"resetsAt":"\#(future)","used":12,"limit":240}}"#)

        XCTAssertEqual(limits.daily?.percentUsed, 5)
    }

    func testWhenResetsAtHasNoFractionalSecondsThenItStillParses() {
        let limits = decode(#"{"daily":{"percentUsed":5,"resetsAt":"2026-08-14T00:00:00Z"}}"#)

        XCTAssertNotNil(limits.daily)
    }

    // MARK: - No-data inputs

    /// The web app writes `"{}"` deliberately rather than deleting the key, so a stale snapshot can't
    /// outlive a sign-out or a server response that dropped usage.
    func testWhenSnapshotIsEmptyObjectThenNoData() {
        XCTAssertEqual(decode("{}"), .noData)
    }

    func testWhenKeyIsAbsentThenNoData() {
        XCTAssertEqual(DuckAiUsageLimits.make(entryValue: nil, now: now), .noData)
    }

    func testWhenValueIsNotAStringThenNoData() {
        for value in [42, true, ["a", "b"], NSNull()] as [Any] {
            XCTAssertEqual(DuckAiUsageLimits.make(entryValue: value, now: now), .noData, "unexpected decode of \(value)")
        }
    }

    func testWhenStringIsNotJSONThenNoData() {
        for json in ["", "   ", "not json", "{oops", #"{"daily":}"#] {
            XCTAssertEqual(decode(json), .noData, "unexpected decode of \(json)")
        }
    }

    func testWhenJSONIsNotAnObjectThenNoData() {
        for json in ["[1,2]", "\"x\"", "12"] {
            XCTAssertEqual(decode(json), .noData, "unexpected decode of \(json)")
        }
    }

    /// Defensive: the entries namespace stores strings today, but a dictionary shouldn't be rejected.
    func testWhenValueIsADictionaryThenItDecodes() {
        let value: [String: Any] = ["daily": ["percentUsed": 20, "resetsAt": future]]

        XCTAssertEqual(DuckAiUsageLimits.make(entryValue: value, now: now).daily?.percentUsed, 20)
    }

    // MARK: - Freshness

    /// The snapshot isn't updated while Duck.ai isn't running, so a window past its reset has unknown
    /// usage — reporting its last-seen percentage would keep warning long after the limit lifted.
    func testWhenWindowHasAlreadyResetThenItIsDropped() {
        let limits = decode(#"{"daily":{"percentUsed":100,"resetsAt":"\#(past)"},"weekly":{"percentUsed":80,"resetsAt":"\#(future)"}}"#)

        XCTAssertNil(limits.daily)
        XCTAssertEqual(limits.weekly?.percentUsed, 80)
    }

    func testWhenEveryWindowHasResetThenNoData() {
        XCTAssertEqual(decode(#"{"daily":{"percentUsed":100,"resetsAt":"\#(past)"},"weekly":{"percentUsed":100,"resetsAt":"\#(past)"}}"#), .noData)
    }

    func testWhenResetsAtEqualsNowThenWindowIsDropped() {
        let atNow = ISO8601DateFormatter.testFormatter.string(from: now)

        XCTAssertNil(decode(#"{"daily":{"percentUsed":50,"resetsAt":"\#(atNow)"}}"#).daily)
    }

    // MARK: - Malformed windows

    func testWhenWindowIsMalformedThenOnlyThatWindowIsDropped() {
        let malformedDaily = [
            #"{"percentUsed":50}"#,                                    // no resetsAt
            #"{"resetsAt":"\#(future)"}"#,                             // no percentUsed
            #"{"percentUsed":50,"resetsAt":"whenever"}"#,              // unparseable date
            #"{"percentUsed":50,"resetsAt":123}"#,                     // non-string date
            #"{"percentUsed":"50","resetsAt":"\#(future)"}"#,          // string percentage
            #"{"percentUsed":true,"resetsAt":"\#(future)"}"#,          // bool percentage
            "42"                                                       // not an object
        ]

        for daily in malformedDaily {
            let limits = decode(#"{"daily":\#(daily),"weekly":{"percentUsed":63,"resetsAt":"\#(future)"}}"#)
            XCTAssertNil(limits.daily, "unexpectedly decoded \(daily)")
            XCTAssertEqual(limits.weekly?.percentUsed, 63, "sibling window lost for \(daily)")
        }
    }

    // MARK: - percentUsed

    func testPercentUsedBoundaries() {
        XCTAssertEqual(decode(#"{"daily":{"percentUsed":0,"resetsAt":"\#(future)"}}"#).daily?.percentUsed, 0)
        XCTAssertEqual(decode(#"{"daily":{"percentUsed":100,"resetsAt":"\#(future)"}}"#).daily?.percentUsed, 100)
        XCTAssertEqual(decode(#"{"daily":{"percentUsed":0.001,"resetsAt":"\#(future)"}}"#).daily?.percentUsed, 0.001)
    }

    /// The web app clamps already; this only guards against a contract change reaching the UI unclamped.
    func testWhenPercentUsedIsOutOfRangeThenItIsClamped() {
        XCTAssertEqual(decode(#"{"daily":{"percentUsed":140,"resetsAt":"\#(future)"}}"#).daily?.percentUsed, 100)
        XCTAssertEqual(decode(#"{"daily":{"percentUsed":-5,"resetsAt":"\#(future)"}}"#).daily?.percentUsed, 0)
    }

    // MARK: - Provider

    func testProviderReadsWhatTheBridgeWrote() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue,
                             value: #"{"daily":{"percentUsed":42.5,"resetsAt":"\#(future)"}}"#)
        let sut = DuckAiUsageLimitsProvider(storage: storage, dateProvider: { self.now })

        XCTAssertEqual(sut.currentUsageLimits().daily?.percentUsed, 42.5)
    }

    func testProviderReturnsNoDataWhenKeyWasNeverWritten() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        let sut = DuckAiUsageLimitsProvider(storage: storage, dateProvider: { self.now })

        XCTAssertEqual(sut.currentUsageLimits(), .noData)
    }

    func testProviderReturnsNoDataAndFiresPixelWhenStorageThrows() {
        struct StorageError: Error {}
        let storage = ThrowingStorageHandler(error: StorageError())
        let pixelFiring = MockDuckAiNativeStoragePixelFiring()
        let sut = DuckAiUsageLimitsProvider(storage: storage, pixelFiring: pixelFiring, dateProvider: { self.now })

        XCTAssertEqual(sut.currentUsageLimits(), .noData)
        XCTAssertEqual(pixelFiring.firedEvents.count, 1)
        guard case .settingsGetError = pixelFiring.firedEvents[0] else {
            return XCTFail("Expected settingsGetError pixel, got \(pixelFiring.firedEvents[0])")
        }
    }

    /// A snapshot that doesn't parse is an ordinary no-data state, not something to report.
    func testProviderDoesNotFirePixelForUnparseableSnapshot() throws {
        let storage = try DuckAiNativeStorageHandler(.memory())
        try storage.putEntry(key: DuckAiNativeStorageReservedEntryKeys.usageLimits.rawValue, value: "{oops")
        let pixelFiring = MockDuckAiNativeStoragePixelFiring()
        let sut = DuckAiUsageLimitsProvider(storage: storage, pixelFiring: pixelFiring, dateProvider: { self.now })

        XCTAssertEqual(sut.currentUsageLimits(), .noData)
        XCTAssertTrue(pixelFiring.firedEvents.isEmpty)
    }

    // MARK: - Helpers

    private func decode(_ json: String) -> DuckAiUsageLimits {
        DuckAiUsageLimits.make(entryValue: json, now: now)
    }

    private func date(_ iso: String) -> Date? {
        ISO8601DateFormatter.testFormatter.date(from: iso)
    }
}

private extension ISO8601DateFormatter {
    static let testFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Only the entries read matters here; everything else is inert.
private final class ThrowingStorageHandler: DuckAiNativeStorageHandling {
    private let error: Error

    init(error: Error) { self.error = error }

    func putEntry(key: String, value: Any) throws {}
    func getEntry(key: String) throws -> Any? { throw error }
    func getAllEntries() throws -> [String: Any] { [:] }
    func deleteEntry(key: String) throws {}
    func deleteAllEntries() throws {}
    func replaceAllEntries(_ entries: [String: Any]) throws {}
    func putChat(chatId: String, data: Data) throws {}
    func putChats(_ chats: [DuckAiChatRecord]) throws {}
    func getChat(chatId: String) throws -> DuckAiChatRecord? { nil }
    func getAllChats() throws -> [DuckAiChatRecord] { [] }
    func deleteChat(chatId: String) throws {}
    func deleteAllChats() throws {}
    func putFile(uuid: String, chatId: String, data: Data) throws {}
    func getFile(uuid: String) throws -> DuckAiFileContent? { nil }
    func listFiles() throws -> [DuckAiFileMetadata] { [] }
    func deleteFile(uuid: String) throws {}
    func deleteFiles(chatId: String) throws {}
    func deleteAllFiles() throws {}
    func isMigrationDone() throws -> Bool { false }
    func isMigrationDone(key: String) throws -> Bool { false }
    func markMigrationDone(key: String) throws {}
}
