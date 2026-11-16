//
//  WebExtensionPermissionPromptTests.swift
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

import AppKit
import WebExtensions
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class WebExtensionPermissionPromptTests: XCTestCase {
    private var alertPresenter: WebExtensionAlertPresenterMock!
    private var windowControllersManager: WindowControllersManagerMock!
    private var prompt: WebExtensionPermissionPrompt!

    override func setUp() {
        super.setUp()
        alertPresenter = WebExtensionAlertPresenterMock()
        windowControllersManager = WindowControllersManagerMock()
        prompt = WebExtensionPermissionPrompt(
            windowProvider: { nil },
            themeManager: ThemeManager(appearancePreferences: .mock),
            alertPresenter: alertPresenter,
            nativeMessagingAlertSuppressionStore: NativeMessagingAlertSuppressionStore(),
            windowControllersManager: windowControllersManager
        )
    }

    override func tearDown() {
        prompt = nil
        windowControllersManager = nil
        alertPresenter = nil
        super.tearDown()
    }

    func testWhenOKIsPressedWithoutTheCheckboxThenThePlainAlertIsShownAgainOnTheNextRequest() async throws {
        alertPresenter.response = .confirmed(isChecked: false)
        let bitwarden = try await makeContext(named: "Bitwarden")

        await requestNativeMessaging(from: [bitwarden, bitwarden])

        XCTAssertEqual(alertPresenter.presentedConfigurations.map(\.title), Array(repeating: "Bitwarden can’t connect to apps on your Mac", count: 2))
        XCTAssertNil(alertPresenter.presentedConfigurations.first?.icon)
        XCTAssertEqual(alertPresenter.presentedConfigurations.first?.confirmTitle, UserText.ok)
        XCTAssertNotNil(alertPresenter.presentedConfigurations.first?.checkbox)
    }

    func testWhenOKIsPressedWithTheCheckboxThenOnlyThatExtensionStopsShowingTheAlert() async throws {
        alertPresenter.response = .confirmed(isChecked: true)
        let bitwarden = try await makeContext(named: "Bitwarden")
        let otherExtension = try await makeContext(named: "Other")

        await requestNativeMessaging(from: [bitwarden, bitwarden, otherExtension])

        XCTAssertEqual(alertPresenter.presentedConfigurations.map(\.title), [
            "Bitwarden can’t connect to apps on your Mac",
            "Other can’t connect to apps on your Mac"
        ])
    }

    func testWhenLearnMoreIsPressedThenTheHelpPageOpensInANewTab() async throws {
        alertPresenter.response = .secondary
        let bitwarden = try await makeContext(named: "Bitwarden")

        await requestNativeMessaging(from: [bitwarden])

        XCTAssertEqual(windowControllersManager.showCalled?.url, .ddgLearnMore)
        XCTAssertEqual(windowControllersManager.showCalled?.newTab, true)
    }

    private func requestNativeMessaging(from contexts: [WKWebExtensionContext]) async {
        for context in contexts {
            _ = await prompt.confirmPermissions(WebExtensionPermissionRequest(unavailablePermissions: [.nativeMessaging]), for: context)
        }
    }

    private func makeContext(named name: String) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        try Data("{\"manifest_version\":3,\"name\":\"\(name)\",\"version\":\"1.0\"}".utf8).write(to: directory.appendingPathComponent("manifest.json"))
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        context.uniqueIdentifier = UUID().uuidString
        return context
    }
}

@MainActor
private final class WebExtensionAlertPresenterMock: WebExtensionAlertPresenterProtocol {
    var response: WebExtensionAlert.Response = .cancelled
    private(set) var presentedConfigurations: [WebExtensionAlert.Configuration] = []

    func present(_ configuration: WebExtensionAlert.Configuration) async -> WebExtensionAlert.Response {
        presentedConfigurations.append(configuration)
        return response
    }
}
