//
//  WebExtensionManagerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
final class WebExtensionManagerTests: XCTestCase {

    var pathsStoringMock: WebExtensionPathsStoringMock!
    var webExtensionLoadingMock: WebExtensionLoadingMock!
    var internalUserStore: MockInternalUserStoring!
    var featureFlaggerMock: MockFeatureFlagger!

    override func setUp() {
        super.setUp()

        pathsStoringMock = WebExtensionPathsStoringMock()
        webExtensionLoadingMock = WebExtensionLoadingMock()
        internalUserStore = MockInternalUserStoring()
        featureFlaggerMock = MockFeatureFlagger()
        featureFlaggerMock.internalUserDecider = DefaultInternalUserDecider(store: internalUserStore)
        internalUserStore.isInternalUser = true
    }

    override func tearDown() {
        webExtensionLoadingMock?.cleanupTestExtensions()
        pathsStoringMock = nil
        webExtensionLoadingMock = nil
        internalUserStore = nil
        featureFlaggerMock = nil

        super.tearDown()
    }

    @MainActor
    func testWhenExtensionIsAdded_ThenPathIsStored() async {
        let webExtensionManager = WebExtensionManager(
            installationStore: pathsStoringMock,
            webExtensionLoader: webExtensionLoadingMock
        )

        let path = "/path/to/extension"
        await webExtensionManager.installExtension(path: path)
        XCTAssertTrue(pathsStoringMock.addCalled)
        XCTAssertEqual(pathsStoringMock.addedURL, path)
    }

    @MainActor
    func testWhenExtensionIsRemoved_ThenPathIsRemovedFromStore() async throws {
        let webExtensionManager = WebExtensionManager(
            installationStore: pathsStoringMock,
            webExtensionLoader: webExtensionLoadingMock
        )

        let path = "/path/to/extension"
        try webExtensionManager.uninstallExtension(path: path)
        XCTAssertTrue(pathsStoringMock.removeCalled)
        XCTAssertEqual(pathsStoringMock.removedURL, path)
    }

    @MainActor
    func testWhenWebExtensionsAreLoaded_ThenPathsAreFetchedFromStore() async {
        let paths = ["/path/to/extension1", "/path/to/extension2"]
        pathsStoringMock.paths = paths

        let extensionManager = WebExtensionManager(
            installationStore: pathsStoringMock,
            webExtensionLoader: webExtensionLoadingMock
        )

        await extensionManager.loadInstalledExtensions()
        XCTAssertTrue(webExtensionLoadingMock.loadWebExtensionsCalled)
        XCTAssertEqual(webExtensionLoadingMock.loadedPaths, paths)
    }

    @MainActor
    func testThatWebExtensionPaths_ReturnsPathsFromStore() {
        let webExtensionManager = WebExtensionManager(
            installationStore: pathsStoringMock,
            webExtensionLoader: webExtensionLoadingMock
        )

        let paths = ["/path/to/extension1", "/path/to/extension2"]
        pathsStoringMock.paths = paths
        let resultPaths = webExtensionManager.webExtensionPaths
        XCTAssertEqual(resultPaths, paths)
    }
}
