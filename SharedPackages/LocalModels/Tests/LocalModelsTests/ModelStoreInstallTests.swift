//
//  ModelStoreInstallTests.swift
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

import CryptoKit
import Foundation
import Testing
@testable import LocalModels

extension StubbedNetworkTests {

    @Suite
    struct ModelStoreInstallTests {

        private struct TestError: Error {}

        private let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        private let files = ["a.bin": Data("aaa".utf8), "b.bin": Data("bbbb".utf8)]

        private var bundle: ModelBundle {
            ModelBundle(id: "fr-en", version: "3.0", files: [file("a.bin"), file("b.bin")])
        }

        @available(iOS 16, macOS 13, *)
        @Test("installs every file and the bundle record in one move", .timeLimit(.minutes(1)))
        func installsBundleAtomically() async throws {
            let store = try makeStore()

            let progress = try await collect(store.install(bundle))

            let folder = root.appendingPathComponent("fr-en")
            #expect(try String(contentsOf: folder.appendingPathComponent("a.bin"), encoding: .utf8) == "aaa")
            #expect(try String(contentsOf: folder.appendingPathComponent("b.bin"), encoding: .utf8) == "bbbb")
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("bundle.json").path))
            #expect(stagingIsEmpty())
            #expect(progress.last == 1)
        }

        @available(iOS 16, macOS 13, *)
        @Test("progress goes from 0 to 1 over all files and never goes back", .timeLimit(.minutes(1)))
        func progressIsMonotonicAndEndsAtOne() async throws {
            let store = try makeStore()

            let progress = try await collect(store.install(bundle))

            #expect(progress.allSatisfy { (0...1).contains($0) })
            #expect(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(progress.contains(3.0 / 7.0))
            #expect(progress.last == 1)
        }

        @available(iOS 16, macOS 13, *)
        @Test("a wrong sha256 discards the bundle", .timeLimit(.minutes(1)))
        func hashMismatchDiscardsBundle() async throws {
            let store = try makeStore()
            let broken = ModelBundle(id: "fr-en", version: "3.0", files: [file("a.bin"), file("b.bin", sha256: String(repeating: "0", count: 64))])

            await #expect(throws: ModelStoreError.hashMismatch(file: "b.bin")) { try await collect(store.install(broken)) }
            #expect(!isInstalled("fr-en"))
            #expect(stagingIsEmpty())
        }

        @available(iOS 16, macOS 13, *)
        @Test("a wrong size discards the bundle", .timeLimit(.minutes(1)))
        func sizeMismatchDiscardsBundle() async throws {
            let store = try makeStore()
            let broken = ModelBundle(id: "fr-en", version: "3.0", files: [file("a.bin", size: 99)])

            await #expect(throws: ModelStoreError.sizeMismatch(file: "a.bin", expected: 99, actual: 3)) { try await collect(store.install(broken)) }
            #expect(!isInstalled("fr-en"))
            #expect(stagingIsEmpty())
        }

        @available(iOS 16, macOS 13, *)
        @Test("an HTTP error discards the bundle", .timeLimit(.minutes(1)))
        func httpErrorDiscardsBundle() async throws {
            let store = try makeStore(status: 404)

            await #expect(throws: ModelStoreError.httpStatus(file: "a.bin", code: 404)) { try await collect(store.install(bundle)) }
            #expect(!isInstalled("fr-en"))
            #expect(stagingIsEmpty())
        }

        @available(iOS 16, macOS 13, *)
        @Test("the file process returns is stored under the file's name", .timeLimit(.minutes(1)))
        func processResultIsStoredUnderName() async throws {
            let store = try makeStore()
            let policy = DownloadPolicy { url, _ in
                let out = url.appendingPathExtension("out")
                try Data("X".utf8).write(to: out)
                return out
            }

            _ = try await collect(store.install(bundle, policy: policy))

            let folder = root.appendingPathComponent("fr-en")
            #expect(try String(contentsOf: folder.appendingPathComponent("a.bin"), encoding: .utf8) == "X")
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["a.bin", "b.bin", "bundle.json"])
        }

        @available(iOS 16, macOS 13, *)
        @Test("an error from process discards the bundle", .timeLimit(.minutes(1)))
        func processErrorDiscardsBundle() async throws {
            let store = try makeStore()
            let policy = DownloadPolicy { _, _ in throw TestError() }

            await #expect(throws: TestError.self) { try await collect(store.install(bundle, policy: policy)) }
            #expect(!isInstalled("fr-en"))
            #expect(stagingIsEmpty())
        }

        @available(iOS 16, macOS 13, *)
        @Test("ids and file names that could leave the root are rejected", .timeLimit(.minutes(1)), arguments: ["../x", "a/b", ".staging", "", ".."])
        func rejectsUnsafeNames(name: String) async throws {
            let store = try makeStore()

            await #expect(throws: ModelStoreError.invalidName(name)) {
                try await collect(store.install(ModelBundle(id: name, version: "1", files: [file("a.bin")])))
            }
            await #expect(throws: ModelStoreError.invalidName(name)) {
                try await collect(store.install(ModelBundle(id: "ok", version: "1", files: [file("a.bin", name: name)])))
            }
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("file names that collide with the record, a download or each other are rejected",
              .timeLimit(.minutes(1)),
              arguments: [["bundle.json"], ["a.download"], ["a.bin", "a.bin"]])
        func rejectsCollidingFileNames(names: [String]) async throws {
            let store = try makeStore()
            let files = names.map { file("a.bin", name: $0) }

            await #expect(throws: ModelStoreError.invalidName(names.last!)) {
                try await collect(store.install(ModelBundle(id: "ok", version: "1", files: files)))
            }
            #expect(StubURLProtocol.requests.isEmpty)
        }

        @available(iOS 16, macOS 13, *)
        @Test("a second install of the same id while one runs throws", .timeLimit(.minutes(1)))
        func secondConcurrentInstallThrows() async throws {
            let store = try makeStore()
            StubURLProtocol.delay = 0.3

            let first = store.install(bundle)
            await #expect(throws: ModelStoreError.alreadyInstalling("fr-en")) { try await collect(store.install(bundle)) }
            _ = try await collect(first)
            #expect(isInstalled("fr-en"))
        }

        @available(iOS 16, macOS 13, *)
        @Test("installing an installed bundle finishes without downloading", .timeLimit(.minutes(1)))
        func alreadyInstalledFinishesImmediately() async throws {
            let store = try makeStore()
            _ = try await collect(store.install(bundle))
            let requestCount = StubURLProtocol.requests.count

            let progress = try await collect(store.install(bundle))

            #expect(StubURLProtocol.requests.count == requestCount)
            #expect(progress == [1])
        }

        @available(iOS 16, macOS 13, *)
        @Test("cancel stops the install and removes staging", .timeLimit(.minutes(1)))
        func cancelRemovesStaging() async throws {
            let store = try makeStore()
            StubURLProtocol.delay = 1

            let stream = store.install(bundle)
            while StubURLProtocol.requests.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
            store.cancel("fr-en")

            await #expect(throws: CancellationError.self) { try await collect(stream) }
            #expect(!isInstalled("fr-en"))
            #expect(stagingIsEmpty())
        }

        // MARK: - Helpers

        private func makeStore(status: Int = 200) throws -> ModelStore {
            StubURLProtocol.reset()
            StubURLProtocol.handler = { [files] request in
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (response, files[request.url!.lastPathComponent] ?? Data())
            }
            return try ModelStore(root: root, session: .localModels(configuration: StubURLProtocol.configuration()))
        }

        private func file(_ fileName: String, name: String? = nil, size: Int64? = nil, sha256: String? = nil) -> ModelFile {
            let data = files[fileName]!
            return ModelFile(name: name ?? fileName,
                             url: URL(string: "https://models.test/\(fileName)")!,
                             size: size ?? Int64(data.count),
                             sha256: sha256 ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        }

        private func collect(_ stream: AsyncThrowingStream<Double, Error>) async throws -> [Double] {
            var all: [Double] = []
            for try await progress in stream { all.append(progress) }
            return all
        }

        private func isInstalled(_ id: String) -> Bool {
            FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path)
        }

        private func stagingIsEmpty() -> Bool {
            let staging = root.appendingPathComponent(".staging")
            return ((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []).isEmpty
        }
    }
}
