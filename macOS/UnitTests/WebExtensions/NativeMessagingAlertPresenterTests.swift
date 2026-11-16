//
//  NativeMessagingAlertPresenterTests.swift
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
final class NativeMessagingAlertPresenterTests: XCTestCase {
    private var alertPresenter: WebExtensionAlertPresenterMock!
    private var limitation: NativeMessagingLimitationMock!
    private var windowControllersManager: WindowControllersManagerMock!
    private var presenter: NativeMessagingAlertPresenter!

    override func setUp() {
        super.setUp()
        alertPresenter = WebExtensionAlertPresenterMock()
        limitation = NativeMessagingLimitationMock()
        windowControllersManager = WindowControllersManagerMock()
        presenter = NativeMessagingAlertPresenter(
            limitationProvider: { [unowned self] in limitation },
            alertPresenter: alertPresenter,
            windowControllersManager: windowControllersManager
        )
    }

    override func tearDown() {
        presenter = nil
        windowControllersManager = nil
        limitation = nil
        alertPresenter = nil
        super.tearDown()
    }

    func testWhenOKIsPressedWithoutTheCheckboxThenThePlainAlertIsShownAgain() async throws {
        alertPresenter.response = .confirmed(isChecked: false)
        let bitwarden = try await limitedContext(named: "Bitwarden")

        await explain(bitwarden, bitwarden)

        XCTAssertEqual(alertPresenter.presentedConfigurations.map(\.title), Array(repeating: "Bitwarden can’t connect to apps on your Mac", count: 2))
        XCTAssertEqual(alertPresenter.presentedConfigurations.first?.checkbox, .suppression("Don’t show this again for Bitwarden"))
    }

    func testWhenOKIsPressedWithTheCheckboxThenOnlyThatExtensionStopsShowingTheAlert() async throws {
        alertPresenter.response = .confirmed(isChecked: true)
        let bitwarden = try await limitedContext(named: "Bitwarden")
        let onePassword = try await limitedContext(named: "1Password")

        await explain(bitwarden, bitwarden, onePassword)

        XCTAssertEqual(alertPresenter.presentedConfigurations.map(\.title), [
            "Bitwarden can’t connect to apps on your Mac",
            "1Password can’t connect to apps on your Mac"
        ])
        XCTAssertEqual(limitation.suppressed, [bitwarden.uniqueIdentifier, onePassword.uniqueIdentifier])
    }

    func testWhenLearnMoreIsPressedThenTheHelpPageOpensInANewTab() async throws {
        alertPresenter.response = .secondary
        let bitwarden = try await limitedContext(named: "Bitwarden")

        await presenter.explain(bitwarden)

        XCTAssertEqual(windowControllersManager.showCalled?.url, .ddgLearnMore)
        XCTAssertEqual(windowControllersManager.showCalled?.newTab, true)
    }

    func testWhenTheExtensionNeverHitTheLimitationThenNoAlertIsShown() async throws {
        let darkReader = try await makeContext(named: "Dark Reader")

        await presenter.explain(darkReader)

        XCTAssertTrue(alertPresenter.presentedConfigurations.isEmpty)
    }

    private func explain(_ contexts: WKWebExtensionContext...) async {
        for context in contexts {
            await presenter.explain(context)
        }
    }

    private func limitedContext(named name: String) async throws -> WKWebExtensionContext {
        let context = try await makeContext(named: name)
        limitation.limited.insert(context.uniqueIdentifier)
        return context
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

private final class NativeMessagingLimitationMock: NativeMessagingLimitationProviding {
    var limited: Set<String> = []
    private(set) var suppressed: [String] = []

    func hasHitNativeMessagingLimitation(identifier: String) -> Bool { limited.contains(identifier) }
    func isNativeMessagingAlertSuppressed(identifier: String) -> Bool { suppressed.contains(identifier) }
    func suppressNativeMessagingAlert(identifier: String) { suppressed.append(identifier) }
}
