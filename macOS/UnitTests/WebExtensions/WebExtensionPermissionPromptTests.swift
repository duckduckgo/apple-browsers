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
    private var nativeMessagingAlertPresenter: NativeMessagingAlertPresenterMock!
    private var prompt: WebExtensionPermissionPrompt!

    override func setUp() {
        super.setUp()
        nativeMessagingAlertPresenter = NativeMessagingAlertPresenterMock()
        prompt = WebExtensionPermissionPrompt(
            windowProvider: { nil },
            themeManager: ThemeManager(appearancePreferences: .mock),
            nativeMessagingAlertPresenter: nativeMessagingAlertPresenter
        )
    }

    override func tearDown() {
        prompt = nil
        nativeMessagingAlertPresenter = nil
        super.tearDown()
    }

    func testWhenOnlyNativeMessagingIsRequestedThenTheNativeMessagingAlertExplainsIt() async throws {
        let context = try await makeContext()

        _ = await prompt.confirmPermissions(WebExtensionPermissionRequest(unavailablePermissions: [.nativeMessaging]), for: context)

        XCTAssertEqual(nativeMessagingAlertPresenter.explainedIdentifiers, [context.uniqueIdentifier])
    }

    private func makeContext() async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        try Data("{\"manifest_version\":3,\"name\":\"Bitwarden\",\"version\":\"1.0\"}".utf8).write(to: directory.appendingPathComponent("manifest.json"))
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        context.uniqueIdentifier = UUID().uuidString
        return context
    }
}

@available(macOS 15.4, *)
@MainActor
private final class NativeMessagingAlertPresenterMock: NativeMessagingAlertPresenterProtocol {
    private(set) var explainedIdentifiers: [String] = []

    func explain(_ context: WKWebExtensionContext) async {
        explainedIdentifiers.append(context.uniqueIdentifier)
    }

    func explainOnActionClick(_ context: WKWebExtensionContext) async {}
}
