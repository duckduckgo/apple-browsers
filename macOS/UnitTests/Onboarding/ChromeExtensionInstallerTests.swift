//
//  ChromeExtensionInstallerTests.swift
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
import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class ChromeExtensionInstallerTests: XCTestCase {

    private var applicationSupportURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        applicationSupportURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: applicationSupportURL.path) {
            try FileManager.default.removeItem(at: applicationSupportURL)
        }
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: applicationSupportURL.path) {
            try FileManager.default.removeItem(at: applicationSupportURL)
        }
        applicationSupportURL = nil
        try super.tearDownWithError()
    }

    func testWhenBuildIsNotSparkleThenCanInstallIsFalse() throws {
        let buildType = ApplicationBuildTypeMock()
        buildType.isSparkleBuild = false

        let installer = makeSUT(buildType: buildType)

        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenChromeIsNotInstalledThenCanInstallIsFalse() {
        let installer = makeSUT(isChromeInstalled: { false })

        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenChromeIsInstalledButNoChannelRootExistsThenCanInstallIsFalse() {
        let installer = makeSUT()

        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenExternalExtensionFileExistsForAnyEligibilityExtensionThenCanInstallIsFalse() throws {
        try createChromeChannelDirectory(named: "Chrome")
        try createExternalExtensionFile(channel: "Chrome", extensionID: DDGChromeExtension.full.extensionID)

        let installer = makeSUT()

        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenProfileExtensionDirectoryExistsForAnyEligibilityExtensionThenCanInstallIsFalse() throws {
        try createChromeChannelDirectory(named: "Chrome")
        try createProfileExtensionDirectory(channel: "Chrome",
                                            profileName: "Default",
                                            extensionID: DDGChromeExtension.noAISearch.extensionID)

        let installer = makeSUT()

        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenAllEligibilityChecksPassThenCanInstallIsTrue() throws {
        try createChromeChannelDirectory(named: "Chrome")

        let installer = makeSUT()

        XCTAssertTrue(installer.canInstallDDGExtension)
    }

    func testWhenInstallSucceedsThenSearchExtensionFileIsWrittenForInstalledChannelsOnly() throws {
        try createChromeChannelDirectory(named: "Chrome")
        try createChromeChannelDirectory(named: "Chrome Beta")

        let installer = makeSUT()
        let didInstall = installer.installDDGExtension()

        XCTAssertTrue(didInstall)
        XCTAssertTrue(externalExtensionFileURL(channel: "Chrome", extensionID: DDGChromeExtension.search.extensionID).isExistingFile)
        XCTAssertTrue(externalExtensionFileURL(channel: "Chrome Beta", extensionID: DDGChromeExtension.search.extensionID).isExistingFile)
        XCTAssertFalse(externalExtensionFileURL(channel: "Chrome Dev", extensionID: DDGChromeExtension.search.extensionID).isExistingFile)
        XCTAssertFalse(externalExtensionFileURL(channel: "Chrome Canary", extensionID: DDGChromeExtension.search.extensionID).isExistingFile)

        XCTAssertFalse(externalExtensionFileURL(channel: "Chrome", extensionID: DDGChromeExtension.full.extensionID).isExistingFile)
        XCTAssertFalse(externalExtensionFileURL(channel: "Chrome", extensionID: DDGChromeExtension.noAISearch.extensionID).isExistingFile)
    }

    func testWhenInstallSucceedsThenCanInstallIsFalse() throws {
        try createChromeChannelDirectory(named: "Chrome")

        let installer = makeSUT()

        XCTAssertTrue(installer.canInstallDDGExtension)
        XCTAssertTrue(installer.installDDGExtension())
        XCTAssertFalse(installer.canInstallDDGExtension)
    }

    func testWhenDetectionHitsFileSystemErrorThenDetectionFailedPixelIsFiredAndCanInstallIsFalse() throws {
        try createChromeChannelDirectory(named: "Chrome")
        try createProfileExtensionDirectory(channel: "Chrome", profileName: "Default", extensionID: "unrelated-extension-id")

        let fileManager = ThrowingFileManager()
        fileManager.throwOnContentsOfDirectory = true

        let pixelFiring = PixelKitMock()
        let installer = makeSUT(fileManager: fileManager, pixelFiring: pixelFiring)

        XCTAssertFalse(installer.canInstallDDGExtension)
        XCTAssertEqual(firedInstallerPixelEvents(from: pixelFiring), [.detectionFailed])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.frequency, .dailyAndStandard)
    }

    func testWhenInstallHitsFileSystemErrorThenInstallFailedPixelIsFiredAndInstallReturnsFalse() throws {
        try createChromeChannelDirectory(named: "Chrome")

        let fileManager = ThrowingFileManager()
        fileManager.throwOnCreateDirectory = true

        let pixelFiring = PixelKitMock()
        let installer = makeSUT(fileManager: fileManager, pixelFiring: pixelFiring)

        XCTAssertFalse(installer.installDDGExtension())
        XCTAssertEqual(firedInstallerPixelEvents(from: pixelFiring), [.installFailed])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.frequency, .dailyAndStandard)
    }

    // MARK: - Helpers

    private func makeSUT(
        buildType: ApplicationBuildTypeMock = {
            let buildType = ApplicationBuildTypeMock()
            buildType.isSparkleBuild = true
            return buildType
        }(),
        isChromeInstalled: @escaping () -> Bool = { true },
        fileManager: FileManager = .default,
        pixelFiring: PixelFiring? = nil
    ) -> ChromeExtensionInstaller {
        ChromeExtensionInstaller(
            buildType: buildType,
            isChromeInstalled: isChromeInstalled,
            applicationSupportURL: applicationSupportURL,
            fileManager: fileManager,
            pixelFiring: pixelFiring
        )
    }

    private func createChromeChannelDirectory(named channelName: String) throws {
        let channelDirectory = applicationSupportURL
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent(channelName, isDirectory: true)
        try FileManager.default.createDirectory(at: channelDirectory, withIntermediateDirectories: true)
    }

    private func createExternalExtensionFile(channel: String, extensionID: String) throws {
        let fileURL = externalExtensionFileURL(channel: channel, extensionID: extensionID)
        let fileContents = #"{"external_update_url":"https://clients2.google.com/service/update2/crx"}"#
        guard let fileData = fileContents.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileData.write(to: fileURL)
    }

    private func createProfileExtensionDirectory(channel: String, profileName: String, extensionID: String) throws {
        let extensionDirectory = applicationSupportURL
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent(channel, isDirectory: true)
            .appendingPathComponent(profileName, isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
            .appendingPathComponent(extensionID, isDirectory: true)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
    }

    private func externalExtensionFileURL(channel: String, extensionID: String) -> URL {
        applicationSupportURL
            .appendingPathComponent("Google", isDirectory: true)
            .appendingPathComponent(channel, isDirectory: true)
            .appendingPathComponent("External Extensions", isDirectory: true)
            .appendingPathComponent("\(extensionID).json", isDirectory: false)
    }
}

private func firedInstallerPixelEvents(from pixelFiring: PixelKitMock) -> [ChromeExtensionInstallerPixelEvent] {
    pixelFiring.actualFireCalls.compactMap { call in
        guard let debugEvent = call.pixel as? DebugEvent,
              case .custom(let event) = debugEvent.eventType,
              let installerEvent = event as? ChromeExtensionInstallerPixelEvent else {
            return nil
        }
        return installerEvent
    }
}

private final class ThrowingFileManager: FileManager, @unchecked Sendable {
    var throwOnContentsOfDirectory = false
    var throwOnCreateDirectory = false

    override func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions = []
    ) throws -> [URL] {
        if throwOnContentsOfDirectory {
            throw CocoaError(.fileReadUnknown)
        }
        return try super.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: mask)
    }

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if throwOnCreateDirectory {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

private extension URL {
    var isExistingFile: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
