//
//  BrowserToolInvokerTests.swift
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
@testable import AIChat

/// The invoker owns every reason a call can be refused, and the consent step between them.
@MainActor
final class BrowserToolInvokerTests: XCTestCase {

    private var permissions: InMemoryPermissionStore!
    private var elicitations: AIChatElicitationCoordinator!
    private var openedTabs: BrowserToolOpenedTabs!

    override func setUp() {
        super.setUp()
        permissions = InMemoryPermissionStore()
        elicitations = AIChatElicitationCoordinator(timeout: 5)
        openedTabs = BrowserToolOpenedTabs()
    }

    override func tearDown() {
        permissions = nil
        elicitations = nil
        openedTabs = nil
        super.tearDown()
    }

    // MARK: - Gating

    func testWhenParentFeatureIsDisabledThenCallIsUnavailableAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], isEnabled: false, enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenToolIsUnknownThenCallIsUnavailable() async {
        let invoker = makeInvoker(tools: [SpyBrowserTool(name: "alpha")], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "nope", arguments: nil, context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.unavailable))
    }

    /// A disabled sub-feature is indistinguishable from an unknown tool, on purpose.
    func testWhenToolSubFeatureIsDisabledThenCallIsUnavailableAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: [])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertFalse(tool.didExecute)
    }

    /// Fire is reported as plain `unavailable` — never a Fire-specific token — so the front end
    /// cannot infer that the user is browsing privately.
    func testWhenCallIsInAFireWindowThenItIsUnavailableAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(isBurner: true), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertFalse(tool.didExecute)
    }

    /// Fire is checked before consent, so a burner window can never leave a decision behind.
    func testWhenAskToolIsCalledInAFireWindowThenNoPromptIsPushedAndNothingIsPersisted() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "alwaysAllow"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(isBurner: true), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(pusher.pushedParams)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    // MARK: - Execution

    func testWhenToolIsEnabledThenItRunsAndItsResultIsReturned() async {
        let tool = SpyBrowserTool(name: "alpha", result: .success(["switched": true]))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "abc"], context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .success(["switched": true]))
        XCTAssertTrue(tool.didExecute)
        XCTAssertEqual(tool.receivedArguments, ["tabId": "abc"])
    }

    func testWhenToolRefusesThenItsFailureIsPassedThrough() async {
        let tool = SpyBrowserTool(name: "alpha", result: .failure(.invalidArguments))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.invalidArguments))
    }

    /// Tools scope to the window handle rather than to the owner tab id, because a shared pinned
    /// tab resolves in every window and would let a call act on the wrong one.
    func testWhenCallIsInvokedThenTheToolReceivesTheOwnerWindowHandle() async {
        let tool = SpyBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])
        let context = BrowserToolCallContext(ownerTabID: "owner-tab",
                                             ownerWindowToken: "window-1",
                                             isBurner: false,
                                             supportsElicitationForm: true)

        _ = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context, elicitationPusher: nil)

        XCTAssertEqual(tool.receivedContext?.ownerWindowToken, "window-1")
        XCTAssertEqual(tool.receivedContext?.ownerTabID, "owner-tab")
    }

    // MARK: - Permissions

    /// An `auto` tool ignores the store entirely — even a stray stored deny.
    func testWhenToolIsAutoThenItRunsWithoutPromptingRegardlessOfStoredDecisions() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .auto)
        permissions.setState(.deny, forToolNamed: "alpha")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success([:]))
        XCTAssertNil(pusher.pushedParams)
    }

    func testWhenAskToolHasStoredAllowThenItRunsWithoutPrompting() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        permissions.setState(.allow, forToolNamed: "alpha")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success([:]))
        XCTAssertNil(pusher.pushedParams)
    }

    func testWhenAskToolHasStoredDenyThenCallIsDeniedWithoutPrompting() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        permissions.setState(.deny, forToolNamed: "alpha")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.denied))
        XCTAssertNil(pusher.pushedParams)
        XCTAssertFalse(tool.didExecute)
    }

    // MARK: - Tabs Duck.ai opened

    func testWhenAskToolTargetsATabThisChatOpenedThenItRunsWithoutPrompting() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, skipsPromptForDuckAIOpenedTabs: true)
        openedTabs.add("duck-tab", ownerTabID: "owner-tab")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": " duck-tab "], context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success([:]))
        XCTAssertNil(pusher.pushedParams)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    /// No prompt is needed, so a front end that cannot show one can still read Duck.ai's tabs.
    func testWhenTabThisChatOpenedIsTargetedWithoutElicitationSupportThenItStillRuns() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, skipsPromptForDuckAIOpenedTabs: true)
        openedTabs.add("duck-tab", ownerTabID: "owner-tab")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "duck-tab"], context: context(supportsElicitationForm: false), elicitationPusher: nil)

        XCTAssertEqual(result, .success([:]))
    }

    func testWhenAskToolTargetsTheUsersOwnTabThenItStillPrompts() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, skipsPromptForDuckAIOpenedTabs: true)
        openedTabs.add("duck-tab", ownerTabID: "owner-tab")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "users-tab"], context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertNotNil(pusher.pushedParams)
        XCTAssertFalse(tool.didExecute)
    }

    /// Omitting `tabId` reads the chat's own host page, which is always the user's.
    func testWhenAskToolOmitsTheTabIdThenItStillPrompts() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, skipsPromptForDuckAIOpenedTabs: true)
        openedTabs.add("owner-tab", ownerTabID: "owner-tab")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: [:], context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertNotNil(pusher.pushedParams)
    }

    func testWhenAnotherChatOpenedTheTabThenItStillPrompts() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, skipsPromptForDuckAIOpenedTabs: true)
        openedTabs.add("duck-tab", ownerTabID: "other-chat")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "duck-tab"], context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertNotNil(pusher.pushedParams)
    }

    func testWhenTheToolDoesNotOptInThenATabThisChatOpenedStillPrompts() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        openedTabs.add("duck-tab", ownerTabID: "owner-tab")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "duck-tab"], context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertNotNil(pusher.pushedParams)
    }

    /// The user's Never covers every read, including pages Duck.ai opened in their session.
    func testWhenToolIsStoredAsNeverThenATabThisChatOpenedIsStillDenied() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, skipsPromptForDuckAIOpenedTabs: true)
        openedTabs.add("duck-tab", ownerTabID: "owner-tab")
        permissions.setState(.deny, forToolNamed: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: ["tabId": "duck-tab"], context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.denied))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenAskToolIsCalledWithoutElicitationSupportThenItIsUnsupportedAndNoPromptIsPushed() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(supportsElicitationForm: false), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.elicitationUnsupported))
        XCTAssertNil(pusher.pushedParams)
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenAskToolIsCalledThenThePromptCarriesTheToolReasonAndTheChoiceSchema() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, permissionReason: "Duck.ai wants alpha.")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        _ = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(pusher.pushedParams?.mode, "form")
        XCTAssertEqual(pusher.pushedParams?.message, "Duck.ai wants alpha.")
        XCTAssertEqual(pusher.pushedParams?.requestedSchema, BrowserToolPermissionElicitation.choiceSchema)
    }

    func testWhenPromptIsCancelledThenCallIsCancelledAndToolDoesNotRun() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertFalse(tool.didExecute)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    func testWhenPromptIsDeclinedThenCallIsDeniedAndNothingIsPersisted() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .decline)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.denied))
        XCTAssertFalse(tool.didExecute)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    func testWhenPromptIsAcceptedWithAllowOnceThenToolRunsAndNothingIsPersisted() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, result: .success(["ran": true]))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success(["ran": true]))
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    func testWhenPromptIsAcceptedWithAlwaysAllowThenToolRunsAndAllowIsPersisted() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask, result: .success(["ran": true]))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "alwaysAllow"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success(["ran": true]))
        XCTAssertEqual(permissions.storedDecisions, ["alpha": .allow])
    }

    func testWhenPromptIsAcceptedWithNeverAllowThenCallIsDeniedAndDenyIsPersisted() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "neverAllow"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.denied))
        XCTAssertFalse(tool.didExecute)
        XCTAssertEqual(permissions.storedDecisions, ["alpha": .deny])
    }

    func testWhenPromptIsAcceptedWithoutChoiceThenCallIsInvalidArguments() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: MCPElicitationResult(action: .accept, content: [:]))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.invalidArguments))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenPromptIsAcceptedWithUnknownChoiceThenCallIsInvalidPermissionChoice() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "maybe"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.invalidPermissionChoice))
        XCTAssertFalse(tool.didExecute)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    /// A shape the invoker does not recognise fails closed, as a cancellation.
    func testWhenPromptAnswerHasUnknownActionThenCallIsCancelled() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let unknown = try? JSONDecoder().decode(MCPElicitationResult.self, from: Data(#"{ "action": "shrug" }"#.utf8))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: unknown ?? .cancel)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenPromptCannotBeDeliveredThenCallIsCancelled() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = ScriptedPusher(elicitations: elicitations, answer: nil)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenThereIsNoPusherThenAskToolCallIsCancelled() async {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: nil)

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertFalse(tool.didExecute)
    }

    // MARK: - Approved call by call

    func testWhenToolIsApprovedEachCallThenItPromptsWithItsOwnPromptEvenWithAStoredAllow() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "Duck.ai wants to submit a form on Acme.", meta: ["formPreview": ["site": "Acme"]]))
        permissions.setState(.allow, forToolNamed: "alpha")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success([:]))
        XCTAssertTrue(tool.didExecute)
        XCTAssertEqual(pusher.pushedParams?.message, "Duck.ai wants to submit a form on Acme.")
        XCTAssertEqual(pusher.pushedParams?.meta, ["formPreview": ["site": "Acme"]])
        XCTAssertEqual(pusher.pushedParams?.requestedSchema, BrowserToolPermissionElicitation.allowOnceSchema)
    }

    /// An earlier Never must not decide a call the user has not seen, and neither may an Always.
    func testWhenToolIsApprovedEachCallThenAStoredDenyIsIgnored() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        permissions.setState(.deny, forToolNamed: "alpha")
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .success([:]))
        XCTAssertNotNil(pusher.pushedParams)
    }

    func testWhenAnApprovedEachCallToolIsListedThenItsStateIsAlwaysAsk() {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        permissions.setState(.allow, forToolNamed: "alpha")

        XCTAssertEqual(permissions.effectiveState(for: tool), .ask)
    }

    func testWhenTheApprovalIsAlwaysAllowThenTheCallIsRefusedAndNothingIsStored() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "alwaysAllow"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.invalidPermissionChoice))
        XCTAssertFalse(tool.didExecute)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    func testWhenTheApprovalIsDeclinedThenTheCallIsDeniedAndNothingIsStored() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .decline)
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.denied))
        XCTAssertFalse(tool.didExecute)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    func testWhenTheApprovalIsCancelledOrHasNoChoiceThenTheCallFails() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let cancelled = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(),
                                             elicitationPusher: ScriptedPusher(elicitations: elicitations, answer: .cancel))
        let noChoice = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(),
                                            elicitationPusher: ScriptedPusher(elicitations: elicitations, answer: MCPElicitationResult(action: .accept)))

        XCTAssertEqual(cancelled, .failure(.cancelled))
        XCTAssertEqual(noChoice, .failure(.invalidArguments))
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenTheToolRefusesBeforeAskingThenNoPromptIsShown() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .refuse(.restricted))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.restricted))
        XCTAssertNil(pusher.pushedParams)
        XCTAssertFalse(tool.didExecute)
    }

    func testWhenTheFrontEndCannotShowPromptsThenAnApprovedEachCallToolIsUnsupported() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(supportsElicitationForm: false), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.elicitationUnsupported))
        XCTAssertNil(pusher.pushedParams)
    }

    func testWhenAnApprovedEachCallToolIsCalledInAFireWindowThenItIsUnavailableWithoutAPrompt() async {
        let tool = ApprovedEachCallTool(name: "alpha", prompt: .ask(message: "m", meta: nil))
        let pusher = ScriptedPusher(elicitations: elicitations, answer: .accept(choice: "allowOnce"))
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])

        let result = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(isBurner: true), elicitationPusher: pusher)

        XCTAssertEqual(result, .failure(.unavailable))
        XCTAssertNil(pusher.pushedParams)
        XCTAssertFalse(tool.didPreparePrompt)
    }

    // MARK: - Cancellation

    func testWhenACallIsCancelledWhileItsPromptIsPendingThenItIsCancelledAndTheToolDoesNotRun() async throws {
        let tool = SpyBrowserTool(name: "alpha", permissionMode: .ask)
        let pusher = SilentPusher()
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])
        let call = Task { await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), callID: "call-1", elicitationPusher: pusher) }
        try await waitUntil { !self.elicitations.pendingPrompts.isEmpty }

        XCTAssertTrue(invoker.cancelCall(callID: "call-1", ownerTabID: "owner-tab"))
        let result = await call.value

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertFalse(tool.didExecute)
        XCTAssertTrue(elicitations.pendingPrompts.isEmpty)
        XCTAssertEqual(permissions.storedDecisions, [:])
    }

    /// The front end asked to stop, so even a tool that finishes regardless answers `cancelled`.
    func testWhenACallIsCancelledWhileTheToolRunsThenItAnswersCancelled() async throws {
        let tool = SlowBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])
        let call = Task { await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), callID: "call-1", elicitationPusher: nil) }
        try await waitUntil { tool.didStart }

        invoker.cancelCall(callID: "call-1", ownerTabID: "owner-tab")
        tool.finish()
        let result = await call.value

        XCTAssertEqual(result, .failure(.cancelled))
        XCTAssertTrue(tool.didFinish)
    }

    /// Call ids come from the front end, so one chat must not be able to stop another's call.
    func testWhenAnotherChatCancelsTheSameCallIdThenTheCallContinues() async throws {
        let tool = SlowBrowserTool(name: "alpha")
        let invoker = makeInvoker(tools: [tool], enabledToolNames: ["alpha"])
        let call = Task { await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), callID: "call-1", elicitationPusher: nil) }
        try await waitUntil { tool.didStart }

        XCTAssertFalse(invoker.cancelCall(callID: "call-1", ownerTabID: "other-chat"))
        tool.finish()
        let result = await call.value

        XCTAssertEqual(result, .success([:]))
    }

    func testWhenAllOfAChatsCallsAreCancelledThenEachAnswersCancelled() async throws {
        let first = SlowBrowserTool(name: "alpha")
        let second = SlowBrowserTool(name: "beta")
        let invoker = makeInvoker(tools: [first, second], enabledToolNames: ["alpha", "beta"])
        let firstCall = Task { await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), callID: "call-1", elicitationPusher: nil) }
        let secondCall = Task { await invoker.invoke(toolNamed: "beta", arguments: nil, context: context(), callID: "call-2", elicitationPusher: nil) }
        try await waitUntil { first.didStart && second.didStart }

        invoker.cancelCalls(ownerTabID: "owner-tab")
        first.finish()
        second.finish()
        let firstResult = await firstCall.value
        let secondResult = await secondCall.value

        XCTAssertEqual(firstResult, .failure(.cancelled))
        XCTAssertEqual(secondResult, .failure(.cancelled))
    }

    func testWhenNoCallHasTheIdThenCancellingReportsNothingWasCancelled() async {
        let invoker = makeInvoker(tools: [SpyBrowserTool(name: "alpha")], enabledToolNames: ["alpha"])
        _ = await invoker.invoke(toolNamed: "alpha", arguments: nil, context: context(), callID: "call-1", elicitationPusher: nil)

        XCTAssertFalse(invoker.cancelCall(callID: "call-1", ownerTabID: "owner-tab"))
        XCTAssertFalse(invoker.cancelCall(callID: "never-made", ownerTabID: "owner-tab"))
    }

    // MARK: - Envelope

    func testWhenCallSucceedsThenItMapsOntoTheMCPEnvelopeWithoutError() {
        let result = BrowserToolResult.success(["ok": true]).callToolResult

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.structuredContent, ["ok": true])
    }

    func testWhenCallFailsThenTheEnvelopeCarriesTheTokenAsTextAndNoStructuredContent() {
        let result = BrowserToolResult.failure(.notFound).callToolResult

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.content.first?.text, "not_found")
        XCTAssertNil(result.structuredContent)
    }

    // MARK: -

    private func makeInvoker(tools: [any BrowserTool],
                             isEnabled: Bool = true,
                             enabledToolNames: Set<String>) -> BrowserToolInvoker {
        let configuration = StubConfiguration(isEnabled: isEnabled, enabledToolNames: enabledToolNames)
        return BrowserToolInvoker(catalog: BrowserToolCatalog(tools: tools, configuration: configuration),
                                  configuration: configuration,
                                  permissions: permissions,
                                  elicitations: elicitations,
                                  openedTabs: openedTabs)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }

    private func context(isBurner: Bool = false, supportsElicitationForm: Bool = true) -> BrowserToolCallContext {
        BrowserToolCallContext(ownerTabID: "owner-tab",
                               ownerWindowToken: "window-1",
                               isBurner: isBurner,
                               supportsElicitationForm: supportsElicitationForm)
    }
}

// MARK: - Stubs

private final class StubConfiguration: BrowserToolsConfiguration {
    let isEnabled: Bool
    private let enabledToolNames: Set<String>

    init(isEnabled: Bool, enabledToolNames: Set<String>) {
        self.isEnabled = isEnabled
        self.enabledToolNames = enabledToolNames
    }

    func isToolEnabled(named name: String) -> Bool {
        isEnabled && enabledToolNames.contains(name)
    }
}

private final class SpyBrowserTool: BrowserTool {
    let name: String
    var title: String { "Spy" }
    var description: String { "Spy tool" }
    let permissionMode: BrowserToolPermissionMode
    let permissionReason: String
    let skipsPromptForDuckAIOpenedTabs: Bool
    var inputSchema: JSONValue { ["type": "object"] }

    private(set) var didExecute = false
    private(set) var receivedArguments: JSONValue?
    private(set) var receivedContext: BrowserToolCallContext?
    private let result: BrowserToolResult

    init(name: String,
         permissionMode: BrowserToolPermissionMode = .auto,
         permissionReason: String = "Duck.ai wants to use a browser tool.",
         skipsPromptForDuckAIOpenedTabs: Bool = false,
         result: BrowserToolResult = .success([:])) {
        self.name = name
        self.permissionMode = permissionMode
        self.permissionReason = permissionReason
        self.skipsPromptForDuckAIOpenedTabs = skipsPromptForDuckAIOpenedTabs
        self.result = result
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        didExecute = true
        receivedArguments = arguments
        receivedContext = context
        return result
    }
}

/// Builds its own prompt for every call, like `submitForm`.
private final class ApprovedEachCallTool: BrowserTool {
    let name: String
    var title: String { "Approved each call" }
    var description: String { "Approved each call" }
    let permissionMode = BrowserToolPermissionMode.ask
    let approvesEachCall = true
    var inputSchema: JSONValue { ["type": "object"] }

    private let prompt: BrowserToolApprovalPrompt
    private(set) var didPreparePrompt = false
    private(set) var didExecute = false

    init(name: String, prompt: BrowserToolApprovalPrompt) {
        self.name = name
        self.prompt = prompt
    }

    func approvalPrompt(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolApprovalPrompt {
        didPreparePrompt = true
        return prompt
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        didExecute = true
        return .success([:])
    }
}

/// Runs until `finish()`, and ignores cancellation, like a tool with no cancellation point of its own.
private final class SlowBrowserTool: BrowserTool {
    let name: String
    var title: String { "Slow" }
    var description: String { "Slow tool" }
    let permissionMode = BrowserToolPermissionMode.auto
    var inputSchema: JSONValue { ["type": "object"] }

    private(set) var didStart = false
    private(set) var didFinish = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(name: String) {
        self.name = name
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        didFinish = true
        return .success([:])
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

/// Delivers the prompt and never answers it.
private final class SilentPusher: AIChatElicitationPushing {
    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool { true }
}

private final class InMemoryPermissionStore: BrowserToolPermissionStoring {
    private(set) var storedDecisions: [String: BrowserToolPermissionState] = [:]

    func state(forToolNamed name: String) -> BrowserToolPermissionState {
        storedDecisions[name] ?? .ask
    }

    func setState(_ state: BrowserToolPermissionState, forToolNamed name: String) {
        if state == .ask {
            storedDecisions.removeValue(forKey: name)
        } else {
            storedDecisions[name] = state
        }
    }

    func clearAll() {
        storedDecisions.removeAll()
    }
}

/// Answers the prompt the moment it is pushed. `answer: nil` means delivery fails.
private final class ScriptedPusher: AIChatElicitationPushing {
    private let elicitations: AIChatElicitationCoordinator
    private let answer: MCPElicitationResult?
    private(set) var pushedParams: MCPElicitationCreateParams?

    init(elicitations: AIChatElicitationCoordinator, answer: MCPElicitationResult?) {
        self.elicitations = elicitations
        self.answer = answer
    }

    func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
        pushedParams = params
        guard let answer else { return false }
        elicitations.complete(id: params.id, result: answer)
        return true
    }
}

private extension MCPElicitationResult {
    static let decline = MCPElicitationResult(action: .decline)

    static func accept(choice: String) -> MCPElicitationResult {
        MCPElicitationResult(action: .accept, content: ["choice": .string(choice)])
    }
}
