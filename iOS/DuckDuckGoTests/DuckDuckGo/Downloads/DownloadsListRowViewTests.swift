//
//  DownloadsListRowViewTests.swift
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

import Combine
import Foundation
import SnapshotTestingSupport
import SwiftUI
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("Downloads List Row View Tests", .serialized)
final class DownloadsListRowViewTests {

    private static let snapshotSize = SnapshotImageSize.fixed(CGSize(width: 390, height: 200))

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testOngoingRowWithKnownSize() async throws {
        let row = try await makeOngoingRow(totalBytesWritten: 4_000_000, totalBytesExpectedToWrite: 10_000_000)

        assertImageSnapshot(matching: inList(OngoingDownloadRow(rowModel: row, cancelButtonAction: {})),
                            size: Self.snapshotSize)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testOngoingRowWithKnownSizeAtAccessibilityTextSize() async throws {
        let row = try await makeOngoingRow(totalBytesWritten: 4_000_000, totalBytesExpectedToWrite: 10_000_000)

        assertImageSnapshot(matching: inList(OngoingDownloadRow(rowModel: row, cancelButtonAction: {}), dynamicTypeSize: .accessibility3),
                            size: Self.snapshotSize)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testOngoingRowWithUnknownSize() async throws {
        let row = try await makeOngoingRow(totalBytesWritten: 4_000_000, totalBytesExpectedToWrite: 0)

        assertImageSnapshot(matching: inList(OngoingDownloadRow(rowModel: row, cancelButtonAction: {})),
                            size: Self.snapshotSize)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testOngoingRowWithUnknownSizeAtAccessibilityTextSize() async throws {
        let row = try await makeOngoingRow(totalBytesWritten: 4_000_000, totalBytesExpectedToWrite: 0)

        assertImageSnapshot(matching: inList(OngoingDownloadRow(rowModel: row, cancelButtonAction: {}), dynamicTypeSize: .accessibility3),
                            size: Self.snapshotSize)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testCompleteRow() throws {
        let row = try makeCompleteRow(named: "report.pdf", byteCount: 2_500_000)

        assertImageSnapshot(matching: inList(CompleteDownloadRow(rowModel: row, shareButtonAction: { _ in })),
                            size: Self.snapshotSize)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testCompleteRowAtAccessibilityTextSize() throws {
        let row = try makeCompleteRow(named: "report.pdf", byteCount: 2_500_000)

        assertImageSnapshot(matching: inList(CompleteDownloadRow(rowModel: row, shareButtonAction: { _ in }), dynamicTypeSize: .accessibility3),
                            size: Self.snapshotSize)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func testCompleteRowWithLongFilename() throws {
        let row = try makeCompleteRow(named: "a-very-long-downloaded-file-name-that-does-not-fit-on-a-single-line-of-the-list.pdf",
                                      byteCount: 2_500_000)

        assertImageSnapshot(matching: inList(CompleteDownloadRow(rowModel: row, shareButtonAction: { _ in })),
                            size: Self.snapshotSize)
    }

    private func inList<Row: View>(_ row: Row, dynamicTypeSize: DynamicTypeSize = .large) -> some View {
        List {
            Section(header: Text(UserText.dateRangeToday)) {
                row
            }
        }
        .listStyle(.insetGrouped)
        .dynamicTypeSize(dynamicTypeSize)
    }

    private func makeOngoingRow(totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) async throws -> OngoingDownloadRowViewModel {
        let download = Download(url: URL(string: "https://duck.com/archive.zip")!,
                                filename: "archive.zip",
                                mimeType: .octetStream,
                                temporary: false,
                                downloadSession: MockDownloadSession())
        download.downloadSession(download.session,
                                 didWriteData: 0,
                                 totalBytesWritten: totalBytesWritten,
                                 totalBytesExpectedToWrite: totalBytesExpectedToWrite)
        let row = OngoingDownloadRowViewModel(download: download, locale: Locale(identifier: "en_US"))
        let publisher = row.$fileSize
            .first { !$0.isEmpty }
            .timeout(.seconds(5), scheduler: DispatchQueue.main)
        var fileSize: String?
        for await value in publisher.values {
            fileSize = value
        }
        try #require(fileSize != nil)
        return row
    }

    private func makeCompleteRow(named name: String, byteCount: Int) throws -> CompleteDownloadRowViewModel {
        let url = directory.appendingPathComponent(name)
        try Data(count: byteCount).write(to: url)
        return CompleteDownloadRowViewModel(fileURL: url, locale: Locale(identifier: "en_US"))
    }
}
