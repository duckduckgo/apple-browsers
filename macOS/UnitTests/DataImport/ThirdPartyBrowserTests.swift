//
//  ThirdPartyBrowserTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

class ThirdPartyBrowserTests: XCTestCase {

    private let mockApplicationSupportDirectoryName = UUID().uuidString

    override func setUp() {
        super.setUp()
        let defaultRootDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try? FileManager.default.removeItem(at: defaultRootDirectoryURL)
    }

    override func tearDown() {
        super.tearDown()
        let defaultRootDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try? FileManager.default.removeItem(at: defaultRootDirectoryURL)
    }

    func testWhenCreatingThirdPartyBrowser_AndValidBrowserIsProvided_ThenThirdPartyBrowserInitializationSucceeds() {
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .brave))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .chrome))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .edge))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .firefox))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .lastPass))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .onePassword7))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .onePassword8))
        XCTAssertNotNil(ThirdPartyBrowser.browser(for: .safari))

        XCTAssertNil(ThirdPartyBrowser.browser(for: .csv))
    }

    func testWhenCreatingThirdPartyBrowser_AndValidBrowserIsNotProvided_ThenThirdPartyBrowserInitializationFails() {
        XCTAssertNil(ThirdPartyBrowser.browser(for: .csv))
    }

    func testWhenGettingBrowserProfiles_AndFirefoxProfileExists_ThenFirefoxProfileIsReturned() throws {
        let defaultProfileName = "profile.default"
        let defaultReleaseProfileName = "profile.default-release"

        let mockApplicationSupportDirectory = FileSystem(rootDirectoryName: mockApplicationSupportDirectoryName) {
            Directory("Firefox") {
                Directory("Profiles") {
                    Directory(defaultReleaseProfileName) {
                        File("key4.db", contents: .copy(key4DatabaseURL()))
                        File("logins.json", contents: .copy(loginsURL()))
                    }

                    Directory(defaultProfileName) {
                        File("key3.db", contents: .copy(key4DatabaseURL()))
                        File("logins.json", contents: .copy(loginsURL()))
                    }
                }
            }
        }

        let mockApplicationSupportDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try mockApplicationSupportDirectory.writeToTemporaryDirectory()

        let list = ThirdPartyBrowser.firefox.browserProfiles(applicationSupportURL: mockApplicationSupportDirectoryURL)

        let validProfiles = list.profiles.filter { $0.validateProfileData()?.containsValidData == true }
        XCTAssertEqual(validProfiles.count, 2)
        XCTAssertEqual(list.defaultProfile?.profileName, "default-release")
    }

    func testWhenGettingBrowserProfiles_AndFirefoxProfileOnlyHasBookmarksData_ThenFirefoxProfileIsReturned() throws {
        let defaultReleaseProfileName = "profile.default-release"

        let mockApplicationSupportDirectory = FileSystem(rootDirectoryName: mockApplicationSupportDirectoryName) {
            Directory("Firefox") {
                Directory("Profiles") {
                    Directory(defaultReleaseProfileName) {
                        File("places.sqlite", contents: .copy(bookmarksURL()))
                    }
                }
            }
        }

        let mockApplicationSupportDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try mockApplicationSupportDirectory.writeToTemporaryDirectory()

        let list = ThirdPartyBrowser.firefox.browserProfiles(applicationSupportURL: mockApplicationSupportDirectoryURL)

        let validProfiles = list.profiles.filter { $0.validateProfileData()?.containsValidData == true }
        XCTAssertEqual(validProfiles.count, 1)
        XCTAssertEqual(list.defaultProfile?.profileName, "default-release")
    }

    // MARK: - Inaccessible profile detection (macOS 27+)

    func testWhenChromeDataDirectoryIsNotReadable_AndDetectionEnabled_ThenPermissionDeniedProfileIsSurfaced() throws {
        let mockApplicationSupportDirectory = FileSystem(rootDirectoryName: mockApplicationSupportDirectoryName) {
            Directory("Google") {
                Directory("Chrome") {
                    File("Bookmarks", contents: .string("{}"))
                }
            }
        }

        let mockApplicationSupportDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try mockApplicationSupportDirectory.writeToTemporaryDirectory()

        // Deny read access to the Chrome data directory to simulate the macOS 27 TCC restriction (NSCocoaError 257).
        let chromeDirectory = mockApplicationSupportDirectoryURL.appendingPathComponent("Google/Chrome")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: chromeDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: chromeDirectory.path) }

        let list = ThirdPartyBrowser.chrome.browserProfiles(applicationSupportURL: mockApplicationSupportDirectoryURL,
                                                            detectsInaccessibleProfiles: true)

        XCTAssertTrue(list.validImportableProfiles.isEmpty)
        XCTAssertEqual(list.permissionDeniedProfiles.count, 1)
        XCTAssertEqual(list.permissionDeniedProfiles.first?.accessState, .permissionDenied)
        XCTAssertTrue(list.requiresDirectoryAccessPermission)
        // The browser must still be offered for import so the user can be guided to grant access.
        XCTAssertEqual(list.defaultProfile?.accessState, .permissionDenied)
    }

    func testWhenChromeDataDirectoryIsNotReadable_AndDetectionDisabled_ThenNoPermissionDeniedProfile() throws {
        let mockApplicationSupportDirectory = FileSystem(rootDirectoryName: mockApplicationSupportDirectoryName) {
            Directory("Google") {
                Directory("Chrome") {
                    File("Bookmarks", contents: .string("{}"))
                }
            }
        }

        let mockApplicationSupportDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try mockApplicationSupportDirectory.writeToTemporaryDirectory()

        let chromeDirectory = mockApplicationSupportDirectoryURL.appendingPathComponent("Google/Chrome")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: chromeDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: chromeDirectory.path) }

        let list = ThirdPartyBrowser.chrome.browserProfiles(applicationSupportURL: mockApplicationSupportDirectoryURL,
                                                            detectsInaccessibleProfiles: false)

        XCTAssertTrue(list.permissionDeniedProfiles.isEmpty)
        XCTAssertFalse(list.requiresDirectoryAccessPermission)
        // Pre-macOS 27 behaviour: an unreadable directory is treated as no data and the browser is filtered out.
        XCTAssertNil(list.defaultProfile)
    }

    func testWhenFirefoxProfilesDirectoryIsNotReadable_AndDetectionEnabled_ThenPermissionDeniedProfileIsSurfaced() throws {
        let mockApplicationSupportDirectory = FileSystem(rootDirectoryName: mockApplicationSupportDirectoryName) {
            Directory("Firefox") {
                Directory("Profiles") {
                    Directory("profile.default-release") {
                        File("places.sqlite", contents: .string(""))
                    }
                }
            }
        }

        let mockApplicationSupportDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try mockApplicationSupportDirectory.writeToTemporaryDirectory()

        // Deny read access to the Firefox profiles directory to simulate the macOS 27 TCC restriction.
        let profilesDirectory = mockApplicationSupportDirectoryURL.appendingPathComponent("Firefox/Profiles")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: profilesDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: profilesDirectory.path) }

        let list = ThirdPartyBrowser.firefox.browserProfiles(applicationSupportURL: mockApplicationSupportDirectoryURL,
                                                             detectsInaccessibleProfiles: true)

        // The inaccessible top-level profiles directory must be represented as a single permission-denied profile,
        // not left in the list as a readable one.
        XCTAssertTrue(list.validImportableProfiles.isEmpty)
        XCTAssertEqual(list.permissionDeniedProfiles.count, 1)
        XCTAssertTrue(list.requiresDirectoryAccessPermission)
        XCTAssertEqual(list.defaultProfile?.accessState, .permissionDenied)
    }

    func testWhenReadableProfileExists_AndDetectionEnabled_ThenNoPermissionDeniedProfile() throws {
        let defaultReleaseProfileName = "profile.default-release"

        let mockApplicationSupportDirectory = FileSystem(rootDirectoryName: mockApplicationSupportDirectoryName) {
            Directory("Firefox") {
                Directory("Profiles") {
                    Directory(defaultReleaseProfileName) {
                        File("places.sqlite", contents: .copy(bookmarksURL()))
                    }
                }
            }
        }

        let mockApplicationSupportDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(mockApplicationSupportDirectoryName)
        try mockApplicationSupportDirectory.writeToTemporaryDirectory()

        let list = ThirdPartyBrowser.firefox.browserProfiles(applicationSupportURL: mockApplicationSupportDirectoryURL,
                                                             detectsInaccessibleProfiles: true)

        XCTAssertTrue(list.permissionDeniedProfiles.isEmpty)
        XCTAssertFalse(list.requiresDirectoryAccessPermission)
        XCTAssertEqual(list.defaultProfile?.profileName, "default-release")
    }

    private func key4DatabaseURL() -> URL {
        let bundle = Bundle(for: ThirdPartyBrowserTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData/No Primary Password/key4.db")
    }

    private func loginsURL() -> URL {
        let bundle = Bundle(for: ThirdPartyBrowserTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData/No Primary Password/logins.json")
    }

    private func bookmarksURL() -> URL {
        let bundle = Bundle(for: ThirdPartyBrowserTests.self)
        return bundle.resourceURL!.appendingPathComponent("DataImportResources/TestFirefoxData/places.sqlite")
    }

}
