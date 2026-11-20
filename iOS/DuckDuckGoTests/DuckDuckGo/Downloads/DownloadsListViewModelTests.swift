//
//  DownloadsListViewModelTests.swift
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
@testable import DuckDuckGo

@MainActor
@Suite("DownloadsListViewModel", .serialized)
final class DownloadsListViewModelTests {

    private let directory: URL
    private let downloadManager = SpyDownloadManager()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        downloadManager.downloadsDirectory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @available(iOS 16, macOS 13, *)
    @Test("No downloads gives no sections", .timeLimit(.minutes(1)))
    func noDownloadsGivesNoSections() {
        let viewModel = makeViewModel()

        #expect(viewModel.sections.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ongoing and complete downloads from today share the Today section", .timeLimit(.minutes(1)))
    func ongoingAndCompleteDownloadsShareTodaySection() throws {
        downloadManager.downloadList = [makeDownload(filename: "ongoing.zip")]
        try makeFile(named: "complete.pdf")

        let viewModel = makeViewModel()

        #expect(viewModel.sections.map(\.header) == [UserText.dateRangeToday])
        let rows = try #require(viewModel.sections.first?.rows)
        #expect(Set(rows.map(\.filename)) == ["ongoing.zip", "complete.pdf"])
        #expect(rows.contains { $0 is OngoingDownloadRowViewModel && $0.filename == "ongoing.zip" })
        #expect(rows.contains { $0 is CompleteDownloadRowViewModel && $0.filename == "complete.pdf" })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Temporary downloads are not listed", .timeLimit(.minutes(1)))
    func temporaryDownloadsAreNotListed() {
        downloadManager.downloadList = [makeDownload(filename: "pass.pkpass", temporary: true)]

        let viewModel = makeViewModel()

        #expect(viewModel.sections.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Older downloads are grouped in a later section", .timeLimit(.minutes(1)))
    func olderDownloadsAreGroupedInLaterSection() throws {
        try makeFile(named: "today.pdf")
        try makeFile(named: "older.pdf", createdDaysAgo: 10)

        let viewModel = makeViewModel()

        #expect(viewModel.sections.map(\.header) == [UserText.dateRangeToday, UserText.dateRangePastMonth])
        #expect(viewModel.sections.map { $0.rows.map(\.filename) } == [["today.pdf"], ["older.pdf"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling a row cancels its download", .timeLimit(.minutes(1)))
    func cancellingRowCancelsDownload() throws {
        let download = makeDownload(filename: "ongoing.zip")
        downloadManager.downloadList = [download]
        let viewModel = makeViewModel()
        let row = try #require(viewModel.sections.first?.rows.first as? OngoingDownloadRowViewModel)

        viewModel.cancelDownload(for: row)

        #expect(downloadManager.cancelledDownloads == [download])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deleting a row removes its file and its row", .timeLimit(.minutes(1)))
    func deletingRowRemovesFileAndRow() throws {
        let today = try makeFile(named: "today.pdf")
        let older = try makeFile(named: "older.pdf", createdDaysAgo: 10)
        let viewModel = makeViewModel()

        viewModel.deleteDownload(at: IndexSet(integer: 0), in: 1)

        #expect(!FileManager.default.fileExists(atPath: older.path))
        #expect(FileManager.default.fileExists(atPath: today.path))
        #expect(viewModel.sections.map { $0.rows.map(\.filename) } == [["today.pdf"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Deleting all removes every complete download and keeps ongoing ones", .timeLimit(.minutes(1)))
    func deletingAllRemovesCompleteDownloadsAndKeepsOngoing() throws {
        downloadManager.downloadList = [makeDownload(filename: "ongoing.zip")]
        let today = try makeFile(named: "today.pdf")
        let older = try makeFile(named: "older.pdf", createdDaysAgo: 10)
        let viewModel = makeViewModel()

        viewModel.deleteAllDownloads()

        #expect(!FileManager.default.fileExists(atPath: today.path))
        #expect(!FileManager.default.fileExists(atPath: older.path))
        #expect(viewModel.sections.map { $0.rows.map(\.filename) } == [["ongoing.zip"]])
        #expect(downloadManager.cancelledDownloads.isEmpty)
    }

    private func makeViewModel() -> DownloadsListViewModel {
        DownloadsListViewModel(dataSource: DownloadsListDataSource(downloadManager: downloadManager))
    }

    private func makeDownload(filename: String, temporary: Bool = false) -> Download {
        Download(url: URL(string: "https://duck.com/\(filename)")!,
                 filename: filename,
                 mimeType: .octetStream,
                 temporary: temporary,
                 downloadSession: MockDownloadSession())
    }

    @discardableResult
    private func makeFile(named name: String, createdDaysAgo days: Int = 0) throws -> URL {
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("content".utf8))
        if days > 0 {
            let date = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }
}
