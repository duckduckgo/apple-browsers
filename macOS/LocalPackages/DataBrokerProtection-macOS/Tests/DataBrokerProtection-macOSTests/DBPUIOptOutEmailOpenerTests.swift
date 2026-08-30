//
//  DBPUIOptOutEmailOpenerTests.swift
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
@testable import DataBrokerProtection_macOS
import DataBrokerProtectionCore

@MainActor
final class DBPUIOptOutEmailOpenerTests: XCTestCase {

    func testWhenMailHandlerIsMissingThenNoMailHandlerFailureIsReturned() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: nil)
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload())

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.providerName, "none")
        XCTAssertEqual(result.failure, .noMailHandler)
        XCTAssertNil(workspace.openedURL)
    }

    func testWhenMailHandlerIsUnsupportedThenUnsupportedFailureIsReturned() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.example.mail")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload())

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.providerName, "unsupported")
        XCTAssertEqual(result.failure, .unsupportedMailHandler("com.example.mail"))
        XCTAssertNil(workspace.openedURL)
    }

    func testWhenMailHandlerIsAppleMailThenAppleMailComposerIsUsed() throws {
        let composer = MockAppleMailComposer()
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.apple.mail")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: composer)
        let payload = try makePayload()

        let result = opener.open(payload)

        XCTAssertTrue(result.didOpen)
        XCTAssertEqual(result.providerName, "Apple Mail")
        XCTAssertEqual(composer.openedPayload?.to, payload.to)
        XCTAssertNil(workspace.openedURL)
    }

    func testWhenAppleMailComposerFailsThenFailureIsReturned() throws {
        let composer = MockAppleMailComposer()
        composer.result = .failed(providerName: "Apple Mail", failure: .appleMailComposeUnavailable)
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.apple.mail")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: composer)

        let result = try opener.open(makePayload())

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.providerName, "Apple Mail")
        XCTAssertEqual(result.failure, .appleMailComposeUnavailable)
        XCTAssertNil(workspace.openedURL)
    }

    func testWhenMailHandlerIsChromeThenGmailComposeURLIsOpened() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.google.Chrome")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload())

        XCTAssertTrue(result.didOpen)
        XCTAssertEqual(result.providerName, "Gmail")
        XCTAssertEqual(workspace.openedURL?.host, "mail.google.com")
        XCTAssertEqual(workspace.openedURL?.path, "/mail/")
        XCTAssertEqual(queryValue("view", in: workspace.openedURL), "cm")
        XCTAssertEqual(queryValue("fs", in: workspace.openedURL), "1")
        XCTAssertEqual(queryValue("to", in: workspace.openedURL), "support@example.com")
        XCTAssertEqual(queryValue("su", in: workspace.openedURL), "Removal request")
        XCTAssertEqual(queryValue("body", in: workspace.openedURL), "Please remove me.")
    }

    func testWhenMailHandlerIsChromeThenGmailComposeURLPercentEncodesPlusSigns() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.google.Chrome")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload(to: "privacy+requests@example.com",
                                                 subject: "Removal + identity request",
                                                 body: "Profile https://example.com/a+b"))

        XCTAssertTrue(result.didOpen)
        let absoluteString = try XCTUnwrap(workspace.openedURL?.absoluteString)
        XCTAssertTrue(absoluteString.contains("to=privacy%2Brequests@example.com"))
        XCTAssertTrue(absoluteString.contains("su=Removal%20%2B%20identity%20request"))
        XCTAssertTrue(absoluteString.contains("body=Profile%20https://example.com/a%2Bb"))
    }

    func testWhenMailHandlerIsOutlookThenOutlookComposeURLIsOpened() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.microsoft.Outlook")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload())

        XCTAssertTrue(result.didOpen)
        XCTAssertEqual(result.providerName, "Outlook")
        XCTAssertEqual(workspace.openedURL?.host, "outlook.office.com")
        XCTAssertEqual(workspace.openedURL?.path, "/mail/deeplink/compose")
        XCTAssertEqual(queryValue("to", in: workspace.openedURL), "support@example.com")
        XCTAssertEqual(queryValue("subject", in: workspace.openedURL), "Removal request")
        XCTAssertEqual(queryValue("body", in: workspace.openedURL), "Please remove me.")
    }

    func testWhenMailHandlerIsOutlookThenOutlookComposeURLPercentEncodesPlusSigns() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.microsoft.Outlook")
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload(to: "privacy+requests@example.com",
                                                 subject: "Removal + identity request",
                                                 body: "Profile https://example.com/a+b"))

        XCTAssertTrue(result.didOpen)
        let absoluteString = try XCTUnwrap(workspace.openedURL?.absoluteString)
        XCTAssertTrue(absoluteString.contains("to=privacy%2Brequests@example.com"))
        XCTAssertTrue(absoluteString.contains("subject=Removal%20%2B%20identity%20request"))
        XCTAssertTrue(absoluteString.contains("body=Profile%20https://example.com/a%2Bb"))
    }

    func testWhenWebComposeURLCannotOpenThenWorkspaceFailureIsReturned() throws {
        let workspace = MockOptOutEmailWorkspace(bundleIdentifier: "com.google.Chrome")
        workspace.openResult = false
        let opener = DBPUIOptOutEmailOpener(workspace: workspace, appleMailComposer: MockAppleMailComposer())

        let result = try opener.open(makePayload())

        XCTAssertFalse(result.didOpen)
        XCTAssertEqual(result.providerName, "Gmail")
        XCTAssertEqual(result.failure, .workspaceOpenFailed(providerName: "Gmail"))
    }

    private func makePayload(to: String = "support@example.com",
                             subject: String = "Removal request",
                             body: String = "Please remove me.") throws -> DBPUIOptOutEmail {
        let data = try XCTUnwrap("""
        {
            "brokerName": "Example Broker",
            "to": "\(to)",
            "subject": "\(subject)",
            "body": "\(body)"
        }
        """.data(using: .utf8))

        return try JSONDecoder().decode(DBPUIOptOutEmail.self, from: data)
    }

    private func queryValue(_ name: String, in url: URL?) -> String? {
        guard let url,
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }

        return queryItems.first(where: { $0.name == name })?.value
    }
}

private final class MockOptOutEmailWorkspace: DBPUIOptOutEmailWorkspace {
    private let bundleIdentifier: String?
    var openResult = true
    private(set) var openedURL: URL?

    init(bundleIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
    }

    @MainActor
    func defaultMailAppBundleIdentifier() -> String? {
        bundleIdentifier
    }

    @MainActor
    func open(_ url: URL) -> Bool {
        openedURL = url
        return openResult
    }
}

private final class MockAppleMailComposer: DBPUIAppleMailComposing {
    var result = DBPUIOptOutEmailOpenResult.opened(providerName: "Apple Mail")
    private(set) var openedPayload: DBPUIOptOutEmail?

    @MainActor
    func open(_ payload: DBPUIOptOutEmail) -> DBPUIOptOutEmailOpenResult {
        openedPayload = payload
        return result
    }
}
