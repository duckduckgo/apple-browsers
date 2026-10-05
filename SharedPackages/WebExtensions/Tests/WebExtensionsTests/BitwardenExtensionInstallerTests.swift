//
//  BitwardenExtensionInstallerTests.swift
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
import WebExtensionsTestSupport
import XCTest
import ZIPFoundation

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class BitwardenExtensionInstallerTests: XCTestCase {

    private var manager: MockWebExtensionManaging!

    override func setUp() {
        super.setUp()
        manager = MockWebExtensionManaging()
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testDownloadURLCarriesChromeVersionAndExtensionID() {
        let url = BitwardenExtensionInstaller.downloadURL

        XCTAssertEqual(url.absoluteString, "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=140.0&acceptformat=crx2,crx3&x=id%3Dnngceckbapebfimnlniiiahkandclblb%26uc")
    }

    func testWhenDownloadSucceeds_ThenInstallsUnpackedDirectoryAndCleansUp() async throws {
        var installedURL: URL?
        var manifest: [String: Any]?
        manager.installExtensionHandler = { url in
            installedURL = url
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            let data = try Data(contentsOf: url.appendingPathComponent("manifest.json"))
            manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        var requestedURL: URL?
        let installer = makeInstaller(crx: try makeCRX3()) { requestedURL = $0 }

        try await installer.install()

        XCTAssertEqual(requestedURL, BitwardenExtensionInstaller.downloadURL)
        XCTAssertEqual(manifest?["name"] as? String, "Bitwarden")
        XCTAssertEqual(manifest?["key"] as? String, developerKey.base64EncodedString())
        XCTAssertTrue(manager.uninstalledIdentifiers.isEmpty)
        let installed = try XCTUnwrap(installedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
    }

    func testWhenManifestAlreadyHasKey_ThenItIsLeftAlone() async throws {
        var manifest: [String: Any]?
        manager.installExtensionHandler = { url in
            manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("manifest.json"))) as? [String: Any]
        }
        let installer = makeInstaller(crx: try makeCRX3(manifest: "{\"name\":\"Bitwarden\",\"key\":\"existing-key\"}"))

        try await installer.install()

        XCTAssertEqual(manifest?["key"] as? String, "existing-key")
    }

    func testWhenBitwardenIsInstalled_ThenUninstallsItBeforeInstalling() async throws {
        var uninstalledBeforeInstall: [String]?
        manager.installExtensionHandler = { [unowned manager] _ in
            uninstalledBeforeInstall = manager?.uninstalledIdentifiers
        }
        let installer = makeInstaller(crx: try makeCRX3(), installedIdentifiers: ["old-1", "old-2"])

        try await installer.install()

        XCTAssertEqual(uninstalledBeforeInstall, ["old-1", "old-2"])
    }

    func testWhenCRXIsInvalid_ThenThrowsAndKeepsInstalledCopy() async {
        let installer = makeInstaller(crx: Data("not a crx".utf8), installedIdentifiers: ["old"])

        do {
            try await installer.install()
            XCTFail("Expected install to throw")
        } catch {
            XCTAssertEqual(error as? CRXArchiveError, .invalidMagic)
        }
        XCTAssertTrue(manager.uninstalledIdentifiers.isEmpty)
    }

    func testWhenDownloadFails_ThenThrows() async {
        struct DownloadError: Error {}
        let installer = BitwardenExtensionInstaller(webExtensionManager: manager,
                                                    download: { _ in throw DownloadError() },
                                                    installedIdentifiers: { [] })

        do {
            try await installer.install()
            XCTFail("Expected install to throw")
        } catch {
            XCTAssertTrue(error is DownloadError)
        }
    }

    // MARK: - Helpers

    private func makeInstaller(crx: Data,
                               installedIdentifiers: [String] = [],
                               onDownload: @escaping (URL) -> Void = { _ in }) -> BitwardenExtensionInstaller {
        BitwardenExtensionInstaller(webExtensionManager: manager,
                                    download: { url in
                                        onDownload(url)
                                        return crx
                                    },
                                    installedIdentifiers: { installedIdentifiers })
    }

    private let developerKey = Data("developer-key".utf8)

    private func makeCRX3(manifest manifestJSON: String = "{\"name\":\"Bitwarden\"}") throws -> Data {
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let archive = try Archive(url: zipURL, accessMode: .create)
        let manifest = Data(manifestJSON.utf8)
        try archive.addEntry(with: "manifest.json", type: .file, uncompressedSize: Int64(manifest.count)) { position, size in
            manifest.subdata(in: Int(position)..<Int(position) + size)
        }

        // CrxFileHeader: one RSA proof holding the developer key, and signed_header_data holding its crx_id.
        let crxID = Data(SHA256.hash(data: developerKey).prefix(16))
        let proof = Data([0x0A, UInt8(developerKey.count)]) + developerKey
        let signedData = Data([0x0A, UInt8(crxID.count)]) + crxID
        let header = Data([0x12, UInt8(proof.count)]) + proof
            + Data([0x82, 0xF1, 0x04, UInt8(signedData.count)]) + signedData
        return Data("Cr24".utf8) + uint32(3) + uint32(UInt32(header.count)) + header + (try Data(contentsOf: zipURL))
    }

    private func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
