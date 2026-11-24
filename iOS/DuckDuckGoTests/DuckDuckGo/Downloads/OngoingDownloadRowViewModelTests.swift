//
//  OngoingDownloadRowViewModelTests.swift
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
import Testing
@testable import DuckDuckGo

@MainActor
@Suite("OngoingDownloadRowViewModel")
final class OngoingDownloadRowViewModelTests {

    private let locale = Locale(identifier: "en_US")

    @available(iOS 16, macOS 13, *)
    @Test("Known total size reports the fraction written as progress", .timeLimit(.minutes(1)))
    func knownTotalSizeReportsFractionAsProgress() {
        let download = makeDownload(totalBytesWritten: 250, totalBytesExpectedToWrite: 1_000)

        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        #expect(row.isTotalSizeKnown)
        #expect(row.progress == 0.25)
        #expect(row.filename == "file.zip")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Known total size progress follows the bytes written", .timeLimit(.minutes(1)))
    func knownTotalSizeProgressFollowsBytesWritten() {
        let download = makeDownload(totalBytesWritten: 0, totalBytesExpectedToWrite: 1_000)
        let row = OngoingDownloadRowViewModel(download: download, locale: locale)
        #expect(row.progress == 0)

        write(500, of: 1_000, to: download)
        #expect(row.progress == 0.5)

        write(1_000, of: 1_000, to: download)
        #expect(row.progress == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Known total size shows written and total sizes", .timeLimit(.minutes(1)))
    func knownTotalSizeShowsWrittenAndTotalSizes() async {
        let download = makeDownload(totalBytesWritten: 250_000, totalBytesExpectedToWrite: 1_000_000)
        let expected = UserText.downloadProgressMessage(currentSize: formatted(250_000), totalSize: formatted(1_000_000))

        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        #expect(await fileSize(of: row, reaching: expected) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("File size text settles on the latest bytes written after a burst of updates", .timeLimit(.minutes(1)))
    func fileSizeTextSettlesOnLatestValue() async {
        let download = makeDownload(totalBytesWritten: 0, totalBytesExpectedToWrite: 1_000_000)
        let row = OngoingDownloadRowViewModel(download: download, locale: locale)
        let expected = UserText.downloadProgressMessage(currentSize: formatted(900_000), totalSize: formatted(1_000_000))

        write(100_000, of: 1_000_000, to: download)
        write(500_000, of: 1_000_000, to: download)
        write(900_000, of: 1_000_000, to: download)

        #expect(await fileSize(of: row, reaching: expected) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown total size is reported as not known", .timeLimit(.minutes(1)))
    func unknownTotalSizeIsNotKnown() {
        let download = makeDownload(totalBytesWritten: 0, totalBytesExpectedToWrite: 0)

        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        #expect(!row.isTotalSizeKnown)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown total size gives NaN progress before any bytes are written", .timeLimit(.minutes(1)))
    func unknownTotalSizeGivesNaNProgressBeforeAnyBytes() {
        let download = makeDownload(totalBytesWritten: 0, totalBytesExpectedToWrite: 0)

        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        #expect(row.progress.isNaN)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown total size gives infinite progress once bytes are written", .timeLimit(.minutes(1)))
    func unknownTotalSizeGivesInfiniteProgressOnceBytesAreWritten() {
        let download = makeDownload(totalBytesWritten: 0, totalBytesExpectedToWrite: 0)
        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        write(500, of: 0, to: download)

        #expect(row.progress == .infinity)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown total size shows only the bytes written", .timeLimit(.minutes(1)))
    func unknownTotalSizeShowsOnlyBytesWritten() async {
        let download = makeDownload(totalBytesWritten: 250_000, totalBytesExpectedToWrite: 0)
        let expected = UserText.downloadProgressMessageForUnknownTotalSize(currentSize: formatted(250_000))

        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        #expect(await fileSize(of: row, reaching: expected) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Total size learned after the row is created is ignored", .timeLimit(.minutes(1)))
    func totalSizeLearnedAfterRowCreationIsIgnored() {
        let download = makeDownload(totalBytesWritten: 0, totalBytesExpectedToWrite: 0)
        let row = OngoingDownloadRowViewModel(download: download, locale: locale)

        write(500, of: 1_000, to: download)

        #expect(!row.isTotalSizeKnown)
        #expect(row.progress == .infinity)
    }

    private func makeDownload(totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) -> Download {
        let download = Download(url: URL(string: "https://duck.com/file.zip")!,
                                filename: "file.zip",
                                mimeType: .octetStream,
                                temporary: false,
                                downloadSession: MockDownloadSession())
        write(totalBytesWritten, of: totalBytesExpectedToWrite, to: download)
        return download
    }

    private func write(_ totalBytesWritten: Int64, of totalBytesExpectedToWrite: Int64, to download: Download) {
        download.downloadSession(download.session,
                                 didWriteData: 0,
                                 totalBytesWritten: totalBytesWritten,
                                 totalBytesExpectedToWrite: totalBytesExpectedToWrite)
    }

    private func formatted(_ bytes: Int64) -> String {
        DownloadsListRowViewModel.formattedByteCount(bytes, locale: locale)
    }

    private func fileSize(of row: OngoingDownloadRowViewModel, reaching expected: String) async -> String? {
        let publisher = row.$fileSize
            .first { $0 == expected }
            .timeout(.seconds(5), scheduler: DispatchQueue.main)
        for await value in publisher.values {
            return value
        }
        return nil
    }
}
