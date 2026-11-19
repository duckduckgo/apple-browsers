//
//  ModelStoreLifecycleTests.swift
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
@testable import LocalModels

extension StubbedNetworkTests {

    @Suite
    struct ModelStoreLifecycleTests {

        private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        @available(iOS 16, macOS 13, *)
        @Test("installed lists only folders with a bundle record, sorted by id", .timeLimit(.minutes(1)))
        func installedListsOnlyCompleteBundles() throws {
            try writeBundle("fr-en", version: "3.0")
            try writeBundle("de-en", version: "2.0")
            try FileManager.default.createDirectory(at: root.appendingPathComponent("junk"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("broken"), withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: root.appendingPathComponent("broken/bundle.json"))

            let installed = try makeStore().installed()

            #expect(installed == [
                InstalledBundle(id: "de-en", version: "2.0", folder: root.appendingPathComponent("de-en")),
                InstalledBundle(id: "fr-en", version: "3.0", folder: root.appendingPathComponent("fr-en"))
            ])
        }

        @available(iOS 16, macOS 13, *)
        @Test("folder(for:) returns the folder of an installed bundle only", .timeLimit(.minutes(1)))
        func folderForReturnsInstalledFolder() throws {
            try writeBundle("fr-en", version: "3.0")
            let store = try makeStore()

            #expect(store.folder(for: "fr-en") == root.appendingPathComponent("fr-en"))
            #expect(store.folder(for: "de-en") == nil)
            #expect(store.folder(for: "../fr-en") == nil)
        }

        @available(iOS 16, macOS 13, *)
        @Test("delete removes the bundle and is a no-op when it's absent", .timeLimit(.minutes(1)))
        func deleteRemovesBundle() throws {
            try writeBundle("fr-en", version: "3.0")
            let store = try makeStore()

            try store.delete("fr-en")

            #expect(store.installed().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("fr-en").path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".staging").path).isEmpty)
            try store.delete("fr-en")
        }

        @available(iOS 16, macOS 13, *)
        @Test("delete rejects names that could leave the root", .timeLimit(.minutes(1)))
        func deleteRejectsUnsafeNames() throws {
            let store = try makeStore()

            #expect(throws: ModelStoreError.invalidName("..")) { try store.delete("..") }
            #expect(FileManager.default.fileExists(atPath: root.path))
        }

        @available(iOS 16, macOS 13, *)
        @Test("delete cancels a running install of the bundle", .timeLimit(.minutes(1)))
        func deleteCancelsRunningInstall() async throws {
            let store = try makeStore()
            StubURLProtocol.delay = 1
            let file = ModelFile(name: "a.bin", url: URL(string: "https://models.test/a.bin")!, size: 3, sha256: String(repeating: "0", count: 64))
            let stream = store.install(ModelBundle(id: "fr-en", version: "3.0", files: [file]))
            while StubURLProtocol.requests.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }

            try store.delete("fr-en")

            await #expect(throws: CancellationError.self) { for try await _ in stream {} }
            #expect(store.installed().isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("init deletes staging folders left by an interrupted install", .timeLimit(.minutes(1)))
        func initClearsLeftoverStaging() throws {
            let leftover = root.appendingPathComponent(".staging/fr-en-1")
            try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
            try Data("aaa".utf8).write(to: leftover.appendingPathComponent("a.bin"))

            let store = try makeStore()

            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".staging").path))
            #expect(store.installed().isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("root is excluded from backups", .timeLimit(.minutes(1)))
        func rootIsExcludedFromBackup() throws {
            _ = try makeStore()

            #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        }

        // MARK: - Helpers

        private func makeStore() throws -> ModelStore {
            StubURLProtocol.reset()
            return try ModelStore(root: root, session: .localModels(configuration: StubURLProtocol.configuration()))
        }

        /// Writes an installed bundle the way a finished install leaves it.
        private func writeBundle(_ id: String, version: String) throws {
            let folder = root.appendingPathComponent(id)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(#"{"id":"\#(id)","version":"\#(version)"}"#.utf8).write(to: folder.appendingPathComponent("bundle.json"))
        }
    }
}
