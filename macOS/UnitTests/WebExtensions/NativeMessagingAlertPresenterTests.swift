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
@_spi(Testing) import PixelKit
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
    private var pixels: PixelKitMock!
    private var presenter: NativeMessagingAlertPresenter!

    override func setUp() {
        super.setUp()
        alertPresenter = WebExtensionAlertPresenterMock()
        limitation = NativeMessagingLimitationMock()
        windowControllersManager = WindowControllersManagerMock()
        pixels = PixelKitMock()
        presenter = NativeMessagingAlertPresenter(
            limitationProvider: { [unowned self] in limitation },
            alertPresenter: alertPresenter,
            windowControllersManager: windowControllersManager,
            pixelFiring: pixels
        )
    }

    override func tearDown() {
        presenter = nil
        pixels = nil
        windowControllersManager = nil
        limitation = nil
        alertPresenter = nil
        super.tearDown()
    }

    func testWhenOKIsPressedWithTheCheckboxThenOnlyThatExtensionStopsShowingTheAlert() async throws {
        alertPresenter.response = .confirmed(isChecked: true)
        let bitwarden = try await limitedContext(named: "Bitwarden")
        let onePassword = try await limitedContext(named: "1Password")

        await explain(bitwarden, bitwarden, onePassword)

        XCTAssertEqual(alertPresenter.presentedConfigurations.map(\.title), [
            "Bitwarden can’t connect to other apps on your Mac",
            "1Password can’t connect to other apps on your Mac"
        ])
        XCTAssertEqual(alertPresenter.presentedConfigurations.first?.checkbox, .suppression("Don’t show again for Bitwarden"))
        XCTAssertEqual(limitation.suppressed, [bitwarden.uniqueIdentifier, onePassword.uniqueIdentifier])
    }

    func testWhenLearnMoreIsPressedWithTheCheckboxThenTheHelpPageOpensAndTheAlertIsSuppressed() async throws {
        alertPresenter.response = .secondary(isChecked: true)
        let bitwarden = try await limitedContext(named: "Bitwarden")

        await presenter.explain(bitwarden)

        XCTAssertEqual(windowControllersManager.showCalled?.url, .ddgLearnMore)
        XCTAssertEqual(windowControllersManager.showCalled?.newTab, true)
        XCTAssertEqual(limitation.suppressed, [bitwarden.uniqueIdentifier])
        XCTAssertEqual(pixels.actualFireCalls, [
            alertShownPixel(source: .permissionRequest),
            ExpectedFireCall(pixel: WebExtensionPixel.nativeMessagingAlertLearnMoreClicked(extension: .catalog(.bitwarden)), frequency: .dailyAndCount)
        ])
    }

    func testWhenTheActionIsClickedThenOnlyLimitedExtensionsThatRequireNativeMessagingShowTheAlert() async throws {
        let onePassword = try await limitedContext(named: "1Password", nativeMessaging: .required)
        let bitwarden = try await limitedContext(named: "Bitwarden", nativeMessaging: .optional)
        let neverLimited = try await makeContext(named: "Never Limited", nativeMessaging: .required)

        await clickAction(of: onePassword, bitwarden, neverLimited)

        XCTAssertEqual(alertPresenter.presentedConfigurations.map(\.title), ["1Password can’t connect to other apps on your Mac"])
        XCTAssertEqual(pixels.actualFireCalls, [alertShownPixel(source: .toolbarClick)])
    }

    private func alertShownPixel(source: NativeMessagingAlertSource) -> ExpectedFireCall {
        ExpectedFireCall(pixel: WebExtensionPixel.nativeMessagingAlertShown(extension: .catalog(.bitwarden), source: source), frequency: .dailyAndCount)
    }

    private func explain(_ contexts: WKWebExtensionContext...) async {
        for context in contexts {
            await presenter.explain(context)
        }
    }

    private func clickAction(of contexts: WKWebExtensionContext...) async {
        for context in contexts {
            await presenter.explainOnActionClick(context)
        }
    }

    private func limitedContext(named name: String, nativeMessaging: NativeMessagingPermission? = nil) async throws -> WKWebExtensionContext {
        let context = try await makeContext(named: name, nativeMessaging: nativeMessaging)
        limitation.limited.insert(context.uniqueIdentifier)
        return context
    }

    private func makeContext(named name: String, nativeMessaging: NativeMessagingPermission? = nil) async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
            nativeMessaging?.rawValue ?? "permissions": nativeMessaging == nil ? [] : ["nativeMessaging"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: directory))
        context.uniqueIdentifier = UUID().uuidString
        return context
    }
}

private enum NativeMessagingPermission: String {
    case required = "permissions"
    case optional = "optional_permissions"
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
    func pixelExtension(identifier: String) -> WebExtensionPixelExtension { .catalog(.bitwarden) }
}
