//
//  AIChatNativePermissionTests.swift
//  DuckDuckGo
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

@testable import AIChat
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatNativePermissionTests: XCTestCase {
    func testEveryNativeDecisionCompletesOriginalHandlerCall() async {
        for decision in [ClientToolPermissionDecision.allowOnce, .always, .never, .dismiss] {
            let fixture = BrowserToolsBridgeFixture()
            fixture.presenter.autoAnswer = decision
            let result = await fixture.invoke()
            switch decision {
            case .allowOnce, .always: XCTAssertEqual(result, fixture.success)
            case .never: XCTAssertEqual(result, .failure(callId: "call", error: .denied))
            default: XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
            }
            let stored: BrowserToolPermissionState? = decision == .always ? .allow : decision == .never ? .deny : nil
            XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), stored)
            XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
            fixture.cleanUp()
        }
    }

    func testNativeActionWaitsForDismissal() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = nil
        fixture.presenter.holdDismissal = true
        let shown = expectation(description: "Native prompt shown")
        fixture.presenter.onPresent = { shown.fulfill() }
        let task = Task { await fixture.invoke() }
        await fulfillment(of: [shown], timeout: 1)
        XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
        XCTAssertEqual(fixture.listings, 0)
        fixture.presenter.select(.always)
        XCTAssertEqual(fixture.listings, 0)
        XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
        fixture.presenter.completeDismissal()
        let result = await task.value
        XCTAssertEqual(result, fixture.success)
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .allow)
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
    }

    func testDisabledToolDuringDismissalCannotPersistAlwaysOrNever() async {
        for decision in [ClientToolPermissionDecision.always, .never] {
            let fixture = BrowserToolsBridgeFixture()
            fixture.presenter.autoAnswer = nil
            fixture.presenter.holdDismissal = true
            let shown = expectation(description: "Native prompt shown")
            fixture.presenter.onPresent = { shown.fulfill() }
            let task = Task { await fixture.invoke() }
            await fulfillment(of: [shown], timeout: 1)
            fixture.presenter.select(decision)
            fixture.flags.enabledFeatureFlags = [.aiChatBrowserTools]
            fixture.presenter.completeDismissal()
            let result = await task.value
            XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
            XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
            XCTAssertEqual(fixture.listings, 0)
            fixture.cleanUp()
        }
    }

    func testSourceDepartureDocumentLossAndFireCancelBeforeDismissalAndPermitFreshCalls() async {
        for cause in ["hide", "document", "fire", "detach", "task"] {
            let fixture = BrowserToolsBridgeFixture()
            fixture.presenter.autoAnswer = nil
            fixture.presenter.holdDismissal = true
            let shown = expectation(description: "Native prompt shown")
            fixture.presenter.onPresent = { shown.fulfill() }
            let task = Task { await fixture.invoke() }
            await fulfillment(of: [shown], timeout: 1)
            fixture.presenter.onPresent = nil
            fixture.presenter.select(.always)
            switch cause {
            case "hide": fixture.service.sourceWillDisappear(fixture.script)
            case "document": fixture.script.browserToolsDocumentDidCommit()
            case "fire":
                let token = fixture.service.beginClearing(.all)
                fixture.service.endClearing(token)
            case "detach": fixture.script.detachBrowserTools()
            default: task.cancel()
            }
            let result = await task.value
            XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
            XCTAssertTrue(fixture.presenter.isPresentingPermission)
            fixture.presenter.completeDismissal()
            XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
            XCTAssertEqual(fixture.listings, 0)
            fixture.presenter.holdDismissal = false
            fixture.presenter.autoAnswer = .allowOnce
            let source = cause == "detach" ? fixture.makeScript() : fixture.script
            let fresh = await fixture.handler.executeClientTool(params: fixture.params(), source: source)
            XCTAssertEqual(fresh, fixture.success)
            source.detachBrowserTools()
            fixture.cleanUp()
        }
    }

    func testStoredAllowCannotBypassHiddenOrBusyNativeSurface() async {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        fixture.presenter.isAvailable = false
        let result = await fixture.invoke()
        XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
        XCTAssertEqual(fixture.listings, 0)
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
    }

    func testSurfaceBecomingUnavailableAfterGrantRejectsOperationAndPermitsFreshCall() async {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = nil
        fixture.presenter.onPresent = {
            fixture.presenter.select(.allowOnce)
            fixture.presenter.isAvailable = false
        }
        let result = await fixture.invoke()
        XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
        XCTAssertEqual(fixture.listings, 0)
        XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
        fixture.presenter.onPresent = nil
        fixture.presenter.isAvailable = true
        fixture.presenter.autoAnswer = .allowOnce
        let fresh = await fixture.invoke()
        XCTAssertEqual(fresh, fixture.success)
        XCTAssertEqual(fixture.listings, 1)
    }

    func testSourceDepartureCancelsGrantedLease() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        guard case .granted(_, let performExecution) = try await fixture.authorizeListing() else {
            return XCTFail("Expected native authorization")
        }
        fixture.service.sourceWillDisappear(fixture.script)
        let result = await performExecution {
            XCTFail("Hidden source must not execute pending permission")
            return .success([:])
        }
        XCTAssertNil(result)
        let fresh = await fixture.invoke()
        XCTAssertEqual(fresh, fixture.success)
    }

    func testFullSourceCancellationStillCancelsExecutingOperation() async throws {
        for cause in ["document", "fire", "detach"] {
            let fixture = BrowserToolsBridgeFixture()
            guard case .granted(_, let performExecution) = try await fixture.authorizeListing() else {
                fixture.cleanUp()
                return XCTFail("Expected native authorization")
            }
            let result = await performExecution {
                switch cause {
                case "document": fixture.script.browserToolsDocumentDidCommit()
                case "fire":
                    let token = fixture.service.beginClearing(.all)
                    fixture.service.endClearing(token)
                default: fixture.script.detachBrowserTools()
                }
                XCTAssertTrue(Task.isCancelled)
                return .success([:])
            }
            XCTAssertNil(result)
            fixture.cleanUp()
        }
    }

    func testStoredAllowRunsWhilePreviousPromptIsDismissingOnAvailableSurface() async {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = nil
        fixture.presenter.holdDismissal = true
        let shown = expectation(description: "Native prompt shown")
        fixture.presenter.onPresent = { shown.fulfill() }
        let first = Task { await fixture.invoke() }
        await fulfillment(of: [shown], timeout: 1)
        fixture.presenter.onPresent = nil
        fixture.service.sourceWillDisappear(fixture.script)
        let cancelled = await first.value
        XCTAssertEqual(cancelled, .failure(callId: "call", error: .cancelled))
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let next = await fixture.invoke()
        XCTAssertEqual(next, fixture.success)
        XCTAssertEqual(fixture.listings, 1)
        XCTAssertEqual(fixture.presenter.prompts.count, 1)
        fixture.presenter.completeDismissal()
    }

    func testQueuedRequestDoesNotCancelAllowOnceWhileNextPromptIsVisible() async {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = nil
        let firstShown = expectation(description: "First native prompt shown")
        fixture.presenter.onPresent = { firstShown.fulfill() }
        let first = Task { await fixture.invoke() }
        await fulfillment(of: [firstShown], timeout: 1)

        let secondStarted = expectation(description: "Second request submitted")
        let second = Task {
            secondStarted.fulfill()
            return await fixture.invoke()
        }
        await fulfillment(of: [secondStarted], timeout: 1)
        XCTAssertEqual(fixture.presenter.prompts.count, 1)

        let secondShown = expectation(description: "Queued native prompt shown")
        fixture.presenter.onPresent = { secondShown.fulfill() }
        fixture.presenter.select(.allowOnce)
        await fulfillment(of: [secondShown], timeout: 1)
        let firstResult = await first.value
        XCTAssertEqual(firstResult, fixture.success)
        XCTAssertTrue(fixture.presenter.isPresentingPermission)
        XCTAssertEqual(fixture.listings, 1)

        fixture.presenter.select(.allowOnce)
        let secondResult = await second.value
        XCTAssertEqual(secondResult, fixture.success)
        XCTAssertEqual(fixture.listings, 2)
        XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
    }

    func testRebindingSameScriptRejectsDelayedOldDecision() async {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = nil
        fixture.presenter.holdDismissal = true
        let shown = expectation(description: "Native prompt shown")
        fixture.presenter.onPresent = { shown.fulfill() }
        let pending = Task { await fixture.invoke() }
        await fulfillment(of: [shown], timeout: 1)
        fixture.presenter.onPresent = nil
        fixture.presenter.select(.always)
        let replacement = MockAIChatNativePermissionPresenter()
        fixture.script.bindBrowserTools(to: fixture.service, owner: fixture.owner, presenter: replacement, makeScope: fixture.makeScope)
        let cancelled = await pending.value
        XCTAssertEqual(cancelled, .failure(callId: "call", error: .cancelled))
        fixture.presenter.completeDismissal()
        XCTAssertNil(fixture.service.permissions.state(forToolNamed: "listOpenTabs"))
        let fresh = await fixture.invoke()
        XCTAssertEqual(fresh, fixture.success)
        XCTAssertEqual(replacement.prompts.count, 1)
    }

    func testParentModalRejectsPromptAndDismissalRestoresSurfaceAvailability() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        let parent = PermissionModalOwner()
        let owner = UIViewController()
        window.rootViewController = parent
        parent.addChild(owner)
        parent.view.addSubview(owner.view)
        owner.didMove(toParent: parent)
        window.isHidden = false
        defer { window.isHidden = true }
        let presenter = AIChatToolPermissionPresenter(surface: { .init(owner) })
        let prompt = ClientToolPermissionPrompt(requestID: "first", callID: "call", toolName: "listOpenTabs", targetsOtherTab: false)
        XCTAssertTrue(presenter.isSurfaceAvailable)
        parent.modal = UIViewController()
        XCTAssertFalse(presenter.isSurfaceAvailable)
        XCTAssertFalse(presenter.present(prompt) { _ in })
        parent.modal = nil
        XCTAssertTrue(presenter.isSurfaceAvailable)
        XCTAssertFalse(presenter.isPresentingPermission)
        var withdrawn = false
        presenter.withdrawActive { withdrawn = true }
        XCTAssertTrue(withdrawn)
    }
}

private final class PermissionModalOwner: UIViewController {
    var modal: UIViewController?
    override var presentedViewController: UIViewController? { modal }
}

@MainActor
final class AIChatToolPermissionSelectionTests: XCTestCase {
    func testDirectToolPromptsApproveOnlyCurrentCall() throws {
        for toolName in ["readTabContent", "listOpenTabs", "searchHistory", "findInPage"] {
            let request = ClientToolPermissionPrompt(requestID: "permission", callID: "call", toolName: toolName, targetsOtherTab: false)
            let prompt = try XCTUnwrap(AIChatToolPermissionView.Prompt(request), toolName)
            let selection = AIChatToolPermissionView.Selection(toolNames: prompt.tools.map(\.id), allowsPartialSelection: false)

            XCTAssertEqual(prompt.tools.map(\.id), [toolName])
            XCTAssertEqual(prompt.approval.decision(for: selection), .allowOnce, toolName)
        }
    }

    func testDirectToolPromptsApproveForChatWhenOffered() throws {
        for toolName in ["readTabContent", "listOpenTabs", "searchHistory", "findInPage"] {
            let request = ClientToolPermissionPrompt(requestID: "permission", callID: "call", toolName: toolName,
                                                     targetsOtherTab: false, offersAllowForChat: true)
            let prompt = try XCTUnwrap(AIChatToolPermissionView.Prompt(request), toolName)
            let selection = AIChatToolPermissionView.Selection(toolNames: prompt.tools.map(\.id), allowsPartialSelection: false)

            XCTAssertEqual(prompt.tools.map(\.id), [toolName])
            XCTAssertEqual(prompt.approval.decision(for: selection), .allowForChat, toolName)
        }
    }

    func testAccessPromptsPreserveAccessDecisionForSingleAndMultipleTools() throws {
        for toolNames in [["readTabContent"], ["readTabContent", "listOpenTabs"]] {
            let request = ClientToolPermissionPrompt(requestID: "permission", callID: "call", toolName: "requestAccess",
                                                     targetsOtherTab: false, accessToolNames: toolNames, offersAllowForChat: true)
            let prompt = try XCTUnwrap(AIChatToolPermissionView.Prompt(request))
            var selection = AIChatToolPermissionView.Selection(toolNames: prompt.tools.map(\.id), allowsPartialSelection: true)

            XCTAssertEqual(prompt.tools.map(\.id), toolNames)
            XCTAssertEqual(prompt.approval.decision(for: selection), .allowAccess(excluding: []))
            selection.toggle("listOpenTabs")
            let excluded: Set<String> = toolNames.count > 1 ? ["listOpenTabs"] : []
            XCTAssertEqual(prompt.approval.decision(for: selection), .allowAccess(excluding: excluded))
        }
    }

    func testUnsupportedAndTargetedDirectRequestsDoNotUseCustomPrompt() {
        let unknown = ClientToolPermissionPrompt(requestID: "permission", callID: "call", toolName: "unknownTool", targetsOtherTab: false)
        XCTAssertNil(AIChatToolPermissionView.Prompt(unknown))

        for toolName in ["readTabContent", "listOpenTabs", "searchHistory", "findInPage"] {
            let request = ClientToolPermissionPrompt(requestID: "permission", callID: "call", toolName: toolName,
                                                     targetsOtherTab: false, target: "https://example.com")
            XCTAssertNil(AIChatToolPermissionView.Prompt(request), toolName)
        }
    }

    func testAllRequestedToolsStartSelected() {
        let toolNames = ["readTabContent", "listOpenTabs", "searchHistory"]
        let selection = AIChatToolPermissionView.Selection(toolNames: toolNames, allowsPartialSelection: true)

        for toolName in toolNames {
            XCTAssertTrue(selection.isSelected(toolName))
            XCTAssertTrue(selection.canToggle(toolName))
        }
        XCTAssertEqual(selection.allowDecision, .allowAccess(excluding: []))
    }

    func testDeselectedToolIsExcludedFromOriginalPromptDecision() throws {
        let prompt = ClientToolPermissionPrompt(requestID: "permission", callID: "call", toolName: "requestAccess", targetsOtherTab: false,
                                                accessToolNames: ["readTabContent", "listOpenTabs", "searchHistory"])
        var selection = AIChatToolPermissionView.Selection(toolNames: try XCTUnwrap(prompt.accessToolNames), allowsPartialSelection: true)

        selection.toggle("listOpenTabs")

        XCTAssertTrue(selection.isSelected("readTabContent"))
        XCTAssertFalse(selection.isSelected("listOpenTabs"))
        XCTAssertTrue(selection.isSelected("searchHistory"))
        XCTAssertEqual(selection.allowDecision, .allowAccess(excluding: ["listOpenTabs"]))
    }

    func testLastSelectedToolCannotBeDeselectedAndAnotherToolCanBeReselected() {
        var selection = AIChatToolPermissionView.Selection(toolNames: ["readTabContent", "listOpenTabs"], allowsPartialSelection: true)
        selection.toggle("listOpenTabs")

        XCTAssertFalse(selection.canToggle("readTabContent"))
        XCTAssertTrue(selection.canToggle("listOpenTabs"))
        selection.toggle("readTabContent")
        XCTAssertTrue(selection.isSelected("readTabContent"))
        XCTAssertEqual(selection.allowDecision, .allowAccess(excluding: ["listOpenTabs"]))

        selection.toggle("listOpenTabs")

        XCTAssertTrue(selection.isSelected("listOpenTabs"))
        XCTAssertTrue(selection.canToggle("readTabContent"))
        XCTAssertTrue(selection.canToggle("listOpenTabs"))
        XCTAssertEqual(selection.allowDecision, .allowAccess(excluding: []))
    }

    func testDisablingPartialSelectionKeepsEveryToolSelected() {
        let toolNames = ["readTabContent", "listOpenTabs"]
        var selection = AIChatToolPermissionView.Selection(toolNames: toolNames, allowsPartialSelection: false)

        for toolName in toolNames {
            XCTAssertFalse(selection.canToggle(toolName))
            selection.toggle(toolName)
            XCTAssertTrue(selection.isSelected(toolName))
        }
        XCTAssertEqual(selection.allowDecision, .allowAccess(excluding: []))
    }

    func testSingleToolRemainsSelected() {
        var selection = AIChatToolPermissionView.Selection(toolNames: ["readTabContent"], allowsPartialSelection: true)

        XCTAssertTrue(selection.isSelected("readTabContent"))
        XCTAssertFalse(selection.canToggle("readTabContent"))
        selection.toggle("readTabContent")

        XCTAssertTrue(selection.isSelected("readTabContent"))
        XCTAssertFalse(selection.canToggle("readTabContent"))
        XCTAssertEqual(selection.allowDecision, .allowAccess(excluding: []))
    }
}
