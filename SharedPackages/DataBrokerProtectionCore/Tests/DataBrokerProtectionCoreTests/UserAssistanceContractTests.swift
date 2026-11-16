//
//  UserAssistanceContractTests.swift
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

import BrowserServicesKit
import BrowserServicesKitTestsUtils
import DataBrokerProtectionCoreTestsUtils
import Foundation
import Testing
import UserScript
import WebKit

@testable import DataBrokerProtectionCore

struct UserAssistanceContractTests {
#if os(macOS)
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func parsedUserAssistPreservesCompleteWhenAndStepInRequestsAndSteps() throws {
        let step = try JSONDecoder().decode(Step.self, from: Data(Self.stepJSON.utf8))
        let action = try #require(step.actions.first as? UserAssistAction)
        #expect(action.id == "assist")
        #expect(action.actionType == .userAssist)
        #expect(action.highlight == "#form")
        #expect(action.handOffAfterMs == 500)
        #expect(action.step == "Submit request")

        let request = Params(state: ActionRequest(action: action, data: Self.requestData))
        let object = try request.toDictionary()
        let payload = try #require((object["state"] as? [String: Any])?["action"] as? [String: Any])
        let actionJSON = try #require(action.json)
        let original = try #require(try JSONSerialization.jsonObject(with: actionJSON) as? NSDictionary)
        #expect(NSDictionary(dictionary: payload) == original)

        let roundTrip = try JSONDecoder().decode(Step.self, from: JSONEncoder().encode(step))
        let roundTripJSON = try #require(roundTrip.actions.first?.json)
        #expect(try JSONSerialization.jsonObject(with: roundTripJSON) as? NSDictionary == original)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func titlesIncludeNestedConditionLabelsOnceInFirstAppearanceOrder() throws {
        let json = """
        [
          {"id":"start","actionType":"click","step":"Find record"},
          {"id":"condition","actionType":"condition","step":"Review details","actions":[
            {"id":"nested","actionType":"condition","actions":[
              {"id":"assist","actionType":"userAssist","step":"Submit request"}
            ]},
            {"id":"repeat","actionType":"click","step":"Find record"}
          ]},
          {"id":"unlabeled","actionType":"click"}
        ]
        """
        let objects = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let actions = try Step.parse(objects)
        let steps = AssistedOptOutSteps(actions: actions)
        #expect(steps.titles == ["Find record", "Review details", "Submit request"])
        #expect(steps.index(of: actions[1]) == 1)
        #expect(steps.index(of: actions[2]) == nil)
    }
#endif

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: ["success", "error", "userTurnNeeded", "actionError"])
    func staleResponsesDoNotFinishCurrentAction(kind: String) async throws {
        let delegate = AssistanceCommunicationDelegate()
        let feature = DataBrokerProtectionFeature(delegate: delegate,
                                                  executionConfig: BrokerJobExecutionConfig(),
                                                  shouldContinueActionHandler: { true },
                                                  rejectsStaleReplies: true)
        let broker = UserScriptMessageBroker(context: "contract-test")
        feature.with(broker: broker)
        let webView = WKWebView()
        Self.push(UserAssistAction(id: "current"), to: feature, webView: webView)
        var acceptedResponses = 0
        feature.onActionResponse = { acceptedResponses += 1 }

        switch kind {
        case "success":
            _ = try await feature.onActionCompleted(params: Self.completion(actionID: "old"), original: WKScriptMessage.mock())
        case "error":
            let params = ["result": ["error": ["actionID": "old", "message": "Failure"]]]
            _ = try await feature.onActionCompleted(params: params, original: WKScriptMessage.mock())
        case "userTurnNeeded":
            _ = try await feature.onUserTurnNeeded(params: ["actionID": "old"], original: WKScriptMessage.mock())
        default:
            _ = try await feature.onActionError(params: ["actionID": "old", "error": "No action found."], original: WKScriptMessage.mock())
        }
        #expect(delegate.errors.isEmpty)
        #expect(delegate.successIDs.isEmpty)
        #expect(delegate.userTurnIDs.isEmpty)
        #expect(acceptedResponses == 0)

        _ = try await feature.onUserTurnNeeded(params: ["actionID": "current"], original: WKScriptMessage.mock())
        #expect(delegate.userTurnIDs == ["current"])
        _ = try await feature.onActionCompleted(params: Self.completion(actionID: "current"), original: WKScriptMessage.mock())
        #expect(delegate.successIDs == ["current"])
        #expect(acceptedResponses == 1)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func regularRunsAcceptRepliesForAnEarlierAction() async throws {
        let delegate = AssistanceCommunicationDelegate()
        let feature = DataBrokerProtectionFeature(delegate: delegate, executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true })
        let broker = UserScriptMessageBroker(context: "contract-test")
        feature.with(broker: broker)
        let webView = WKWebView()
        Self.push(ClickAction(id: "current", actionType: .click), to: feature, webView: webView)
        var acceptedResponses = 0
        feature.onActionResponse = { acceptedResponses += 1 }

        _ = try await feature.onActionCompleted(params: Self.completion(actionID: "old"), original: WKScriptMessage.mock())

        #expect(delegate.successIDs == ["old"])
        #expect(acceptedResponses == 1)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func userAssistDoesNotUseTheActionTimeout() async throws {
        let delegate = AssistanceCommunicationDelegate()
        let config = BrokerJobExecutionConfig(cssActionTimeout: 0.01)
        let feature = DataBrokerProtectionFeature(delegate: delegate, executionConfig: config, shouldContinueActionHandler: { true })
        let broker = UserScriptMessageBroker(context: "contract-test")
        feature.with(broker: broker)
        let webView = WKWebView()
        Self.push(UserAssistAction(id: "assist"), to: feature, webView: webView)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(delegate.errors.isEmpty)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func regularOptOutFailsUserAssistBeforeLoadingThePage(nestedInCondition: Bool) async throws {
        let nested = #"{"id":"condition","actionType":"condition","actions":[{"id":"assist","actionType":"userAssist"}]}"#
        let actions: [Action] = [ClickAction(id: "click", actionType: .click),
                                 nestedInCondition ? ConditionAction(id: "condition", actionType: .condition, json: Data(nested.utf8))
                                                   : UserAssistAction(id: "assist")]
        let runner = Self.makeRunner(actions: actions)
        let stageCalculator = try #require(runner.stageCalculator as? MockStageDurationCalculator)
        runner.retriesCountOnError = 1
        let handler = WebViewHandlerMock()
        await #expect(throws: DataBrokerProtectionError.userAssistanceRequired) {
            try await runner.run(inputValue: .mockWithoutRemovedDate, webViewHandler: handler, actionsHandler: nil, showWebView: false)
        }
        #expect(handler.wasInitializeWebViewCalled == false)
        #expect(handler.executeCallCount == 0)
        #expect(stageCalculator.incrementTriesCalled == false)
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func assistedRunnerNotifiesObserverAndDispatchesUserAssist() async throws {
        let observer = AssistanceObserver()
        let action = UserAssistAction(id: "assist")
        let runner = Self.makeRunner(actions: [action], observer: observer)
        try await runner.initialize(handler: nil, showWebView: false)
        #expect(observer.webView != nil)
        await runner.webViewHandler?.finish()

        let handler = WebViewHandlerMock()
        runner.webViewHandler = handler
        await runner.runNextAction(action)
        #expect(observer.actionIDs == ["assist"])
        #expect(handler.executeCallCount == 1)
        await runner.userTurnNeeded(actionID: "assist")
        #expect(observer.userTurnIDs == ["assist"])
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func visualizationIsOptedInPerBrokerProtectionWebView() throws {
        let manager = PrivacyConfigurationManagingMock()
        manager.currentConfig = Data(#"{"features":{}}"#.utf8)
        let initialConfig = manager.currentConfig
        let enabled = try DataBrokerUserScript(privacyConfig: manager, prefs: .mock, delegate: AssistanceCommunicationDelegate(),
                                              executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true },
                                              contentBlocking: nil, visualizeActions: true)
        let regular = try DataBrokerUserScript(privacyConfig: manager, prefs: .mock, delegate: AssistanceCommunicationDelegate(),
                                              executionConfig: BrokerJobExecutionConfig(), shouldContinueActionHandler: { true }, contentBlocking: nil)
        let injectedSetting = #"\"visualizeActions\":\"enabled\""#
        #expect(enabled.contentScopeUserScriptIsolated.source.contains(injectedSetting))
        #expect(regular.contentScopeUserScriptIsolated.source.contains(injectedSetting) == false)
        #expect(enabled.contentScopeUserScriptIsolated.scriptContext == .brokerProtection)
        #expect(regular.contentScopeUserScriptIsolated.scriptContext == .brokerProtection)
        #expect(manager.currentConfig == initialConfig)
    }

    private static let stepJSON = """
    {"stepType":"optOut","actions":[{
      "id":"assist","actionType":"userAssist","highlight":"#form","handOffAfterMs":500,"step":"Submit request",
      "completeWhen":{"type":"element","selector":"#done","visible":true},"futureField":{"enabled":false}
    }]}
    """

    private static var requestData: CCFRequestData {
        .userData(ProfileQuery(firstName: "", lastName: "", city: "", state: "", birthYear: 1970), nil, nil, [:])
    }

    private static func completion(actionID: String) -> [String: Any] {
        ["result": ["success": ["actionID": actionID, "actionType": "userAssist"]]]
    }

    @MainActor
    private static func push(_ action: Action, to feature: DataBrokerProtectionFeature, webView: WKWebView) {
        feature.pushAction(method: .onActionReceived, webView: webView, params: Params(state: ActionRequest(action: action, data: requestData)))
    }

    @MainActor
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func debugObserverReportsTheUserTurnWithItsStepAndTheReturnToAutomation() async throws {
        var userTurns: [String?] = []
        var agentTurns = 0
        let observer = DebugAssistanceObserver(showsWebView: false, onUserTurn: { _, step in userTurns.append(step) }, onAgentTurn: { agentTurns += 1 })
        let action = UserAssistAction(id: "assist", json: Data(#"{"step":"Prove you're human"}"#.utf8))
        let runner = Self.makeRunner(actions: [action], observer: observer)
        runner.webViewHandler = WebViewHandlerMock()
        await runner.runNextAction(action)
        await runner.userTurnNeeded(actionID: "assist")
        #expect(userTurns == ["Prove you're human"])
        #expect(agentTurns == 0)
        await runner.runNextAction(UserAssistAction(id: "next"))
        #expect(agentTurns == 1)
    }

    private static func makeRunner(actions: [Action], observer: OptOutAssistanceObserving? = nil) -> BrokerProfileOptOutSubJobWebRunner {
        BrokerProfileOptOutSubJobWebRunner(privacyConfig: PrivacyConfigurationManagingMock(), prefs: .mock,
                                          context: BrokerProfileQueryData.mock(with: [Step(type: .optOut, actions: actions)]),
                                          emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(), captchaService: CaptchaServiceMock(),
                                          featureFlagger: MockDBPFeatureFlagger(), operationAwaitTime: 0, stageCalculator: MockStageDurationCalculator(),
                                          pixelHandler: MockDataBrokerProtectionPixelsHandler(), executionConfig: BrokerJobExecutionConfig(),
                                          actionsHandlerMode: .optOut, assistanceObserver: observer, shouldRunNextStep: { true })
    }
}

private final class AssistanceCommunicationDelegate: CCFCommunicationDelegate {
    var successIDs: [String] = []
    var userTurnIDs: [String] = []
    var errors: [DataBrokerProtectionError] = []

    func loadURL(url: URL) async {}
    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {}
    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) async {}
    func solveCaptcha(with response: SolveCaptchaResponse) async {}
    func conditionSuccess(actions: [Action]) async {}
    func success(actionId: String, actionType: ActionType) async { successIDs.append(actionId) }
    func userTurnNeeded(actionID: String) async { userTurnIDs.append(actionID) }
    func onError(error: Error) async {
        if let error = error as? DataBrokerProtectionError { errors.append(error) }
    }
}

@MainActor
private final class AssistanceObserver: OptOutAssistanceObserving {
    var webView: WKWebView?
    var actionIDs: [String] = []
    var userTurnIDs: [String] = []

    func attemptDidCreate(webView: WKWebView) { self.webView = webView }
    func attemptWillRun(_ action: Action) { actionIDs.append(action.id) }
    func attemptNeedsUser(actionID: String) { userTurnIDs.append(actionID) }
}
