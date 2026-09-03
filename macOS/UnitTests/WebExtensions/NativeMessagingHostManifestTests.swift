//
//  NativeMessagingHostManifestTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class NativeMessagingHostManifestTests: XCTestCase {

    private var directories: [URL] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        directories = try (0..<3).map { _ in try makeTemporaryDirectory() }
    }

    override func tearDownWithError() throws {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
        try super.tearDownWithError()
    }

    // MARK: - Decoding

    func testWhenManifestIsChromeStyleThenAllowedOriginsAreDecoded() throws {
        let json = """
        {
            "name": "com.8bit.bitwarden",
            "path": "/Applications/Bitwarden.app/Contents/MacOS/desktop_proxy",
            "type": "stdio",
            "allowed_origins": ["chrome-extension://nngceckbapebfimnlniiiahkandclblb/"]
        }
        """

        let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.name, "com.8bit.bitwarden")
        XCTAssertEqual(manifest.path, "/Applications/Bitwarden.app/Contents/MacOS/desktop_proxy")
        XCTAssertEqual(manifest.type, .stdio)
        XCTAssertEqual(manifest.allowedOrigins, ["chrome-extension://nngceckbapebfimnlniiiahkandclblb/"])
        XCTAssertNil(manifest.allowedExtensions)
    }

    func testWhenManifestIsFirefoxStyleThenAllowedExtensionsAreDecoded() throws {
        let json = """
        {
            "name": "com.8bit.bitwarden",
            "path": "/Applications/Bitwarden.app/Contents/MacOS/desktop_proxy",
            "type": "stdio",
            "allowed_extensions": ["{446900e4-71c2-419f-a6a7-df9c091e268b}"]
        }
        """

        let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.allowedExtensions, ["{446900e4-71c2-419f-a6a7-df9c091e268b}"])
        XCTAssertNil(manifest.allowedOrigins)
    }

    func testWhenManifestListsNeitherOriginsNorExtensionsThenBothAreNil() throws {
        let json = """
        { "name": "com.example.host", "path": "host", "type": "stdio" }
        """

        let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: Data(json.utf8))

        XCTAssertNil(manifest.allowedOrigins)
        XCTAssertNil(manifest.allowedExtensions)
    }

    func testWhenPathIsRelativeThenExecutableResolvesNextToTheManifest() throws {
        let json = """
        { "name": "com.example.host", "path": "bin/host", "type": "stdio" }
        """
        let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: Data(json.utf8))
        let manifestURL = URL(fileURLWithPath: "/tmp/hosts/com.example.host.json")

        let executable = manifest.executableURL(relativeTo: manifestURL)

        XCTAssertEqual(executable.path, "/tmp/hosts/bin/host")
    }

    func testWhenPathIsAbsoluteThenExecutableIgnoresTheManifestLocation() throws {
        let json = """
        { "name": "com.example.host", "path": "/usr/local/bin/host", "type": "stdio" }
        """
        let manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: Data(json.utf8))
        let manifestURL = URL(fileURLWithPath: "/tmp/hosts/com.example.host.json")

        let executable = manifest.executableURL(relativeTo: manifestURL)

        XCTAssertEqual(executable.path, "/usr/local/bin/host")
    }

    // MARK: - Locating

    func testWhenTheFirstDirectoryHasTheManifestThenItIsUsed() throws {
        let firstExecutable = try makeExecutable(named: "host-one", in: directories[0])
        let secondExecutable = try makeExecutable(named: "host-two", in: directories[1])
        try writeManifest(name: "com.example.host", executable: firstExecutable, in: directories[0])
        try writeManifest(name: "com.example.host", executable: secondExecutable, in: directories[1])

        let located = try NativeMessagingHostManifestLocator.locate(name: "com.example.host",
                                                                   searchDirectories: directories)

        XCTAssertEqual(located.executable.path, firstExecutable.path)
    }

    func testWhenTheFirstDirectoriesLackTheManifestThenTheSearchContinues() throws {
        let executable = try makeExecutable(named: "host", in: directories[2])
        try writeManifest(name: "com.example.host", executable: executable, in: directories[2])

        let located = try NativeMessagingHostManifestLocator.locate(name: "com.example.host",
                                                                   searchDirectories: directories)

        XCTAssertEqual(located.manifest.name, "com.example.host")
        XCTAssertEqual(located.executable.path, executable.path)
    }

    func testWhenNoDirectoryHasTheManifestThenNotFoundIsThrown() throws {
        XCTAssertThrowsError(try NativeMessagingHostManifestLocator.locate(name: "com.example.missing",
                                                                          searchDirectories: directories)) { error in
            guard case NativeMessagingHostManifestLocator.LocatorError.notFound(let name) = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
            XCTAssertEqual(name, "com.example.missing")
        }
    }

    func testWhenAManifestNamesANonExecutablePathThenTheSearchContinues() throws {
        let plainFile = directories[0].appendingPathComponent("host")
        try Data("not executable".utf8).write(to: plainFile)
        try writeManifest(name: "com.example.host", executable: plainFile, in: directories[0])

        let usableExecutable = try makeExecutable(named: "host", in: directories[1])
        try writeManifest(name: "com.example.host", executable: usableExecutable, in: directories[1])

        let located = try NativeMessagingHostManifestLocator.locate(name: "com.example.host",
                                                                   searchDirectories: directories)

        XCTAssertEqual(located.executable.path, usableExecutable.path)
    }

    /// `executableMissing` is thrown inside the loop, and the loop's own `catch` swallows it,
    /// so the caller sees `notFound` instead. This pins that, because the handler turns the
    /// error into the message the user reads.
    func testWhenTheOnlyManifestNamesANonExecutablePathThenNotFoundIsThrown() throws {
        let plainFile = directories[0].appendingPathComponent("host")
        try Data("not executable".utf8).write(to: plainFile)
        try writeManifest(name: "com.example.host", executable: plainFile, in: directories[0])

        XCTAssertThrowsError(try NativeMessagingHostManifestLocator.locate(name: "com.example.host",
                                                                          searchDirectories: directories)) { error in
            guard case NativeMessagingHostManifestLocator.LocatorError.notFound = error else {
                return XCTFail("Expected notFound, got \(error)")
            }
        }
    }

    func testWhenAManifestIsMalformedThenTheSearchContinues() throws {
        let manifestURL = directories[0].appendingPathComponent("com.example.host.json")
        try Data("{ not json".utf8).write(to: manifestURL)

        let executable = try makeExecutable(named: "host", in: directories[1])
        try writeManifest(name: "com.example.host", executable: executable, in: directories[1])

        let located = try NativeMessagingHostManifestLocator.locate(name: "com.example.host",
                                                                   searchDirectories: directories)

        XCTAssertEqual(located.executable.path, executable.path)
    }

    func testWhenSearchDirectoriesAreOmittedThenTheBrowserDirectoriesAreSearched() {
        let directories = NativeMessagingHostManifestLocator.searchDirectories

        XCTAssertEqual(directories.first?.lastPathComponent, "NativeMessagingHosts")
        XCTAssertTrue(directories.contains { $0.path.contains("Application Support/DuckDuckGo/NativeMessagingHosts") })
        XCTAssertTrue(directories.contains { $0.path.contains("Google/Chrome") })
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativeMessagingHostManifestTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func writeManifest(name: String, executable: URL, in directory: URL) throws {
        let manifest: [String: Any] = [
            "name": name,
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: directory.appendingPathComponent("\(name).json"))
    }
}
