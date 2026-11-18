//
//  DataBrokerProtectionFeature.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Common
import ConcurrencyExtensions
import Foundation
import os.log
import UserScript
import WebKit

public protocol CCFCommunicationDelegate: AnyObject {
    func loadURL(url: URL) async
    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async
    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) async
    func solveCaptcha(with response: SolveCaptchaResponse) async
    func success(actionId: String, actionType: ActionType) async
    func conditionSuccess(actions: [Action]) async
    func onError(error: Error) async
    func userTurnNeeded(actionID: String) async
}

public extension CCFCommunicationDelegate {
    func userTurnNeeded(actionID: String) async {}
}

public enum CCFSubscribeActionName: String {
    case onActionReceived
}

public enum CCFReceivedMethodName: String {
    case actionCompleted
    case actionError
    case userTurnNeeded
}

public class DataBrokerProtectionFeature: Subfeature {
    public var messageOriginPolicy: MessageOriginPolicy = .all
    public var featureName: String = "brokerProtection"
    public weak var broker: UserScriptMessageBroker? // This broker is not related to DBP brokers. It's just a name we inherit from Subfeature

    weak var delegate: CCFCommunicationDelegate?

    private var actionResponseTimer: Timer?
    private var taskCancellationTimer: Timer?

    private var shouldContinueAction: () -> Bool

    @MainActor private var currentActionID: String?

    @MainActor var onActionResponse: (() -> Void)?

    private let executionConfig: BrokerJobExecutionConfig

    public init(delegate: CCFCommunicationDelegate,
                executionConfig: BrokerJobExecutionConfig,
                shouldContinueActionHandler shouldContinueAction: @escaping () -> Bool) {
        self.delegate = delegate
        self.executionConfig = executionConfig
        self.shouldContinueAction = shouldContinueAction
    }

    deinit {
        let actionResponseTimer = actionResponseTimer
        let taskCancellationTimer = taskCancellationTimer

        DispatchQueue.main.asyncOrNow {
            actionResponseTimer?.invalidate()
            taskCancellationTimer?.invalidate()
        }
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        let actionResult = CCFReceivedMethodName(rawValue: methodName)

        if let actionResult = actionResult {
            switch actionResult {
            case .actionCompleted: return onActionCompleted
            case .actionError: return onActionError
            case .userTurnNeeded: return onUserTurnNeeded
            }
        } else {
            Logger.action.log("Cant parse method: \(methodName, privacy: .public)")
            return nil
        }
    }

    func onActionCompleted(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard await acceptActionResponse(actionID: Self.actionID(inCompletedParams: params)) else { return nil }

        Logger.action.log("Action completed")

        await parseActionCompleted(params: params)
        return nil
    }

    func parseActionCompleted(params: Any) async {
        Logger.action.log("Parse action completed")

        guard let data = try? JSONSerialization.data(withJSONObject: params),
                let result = try? JSONDecoder().decode(CCFResult.self, from: data) else {
            await delegate?.onError(error: DataBrokerProtectionError.parsingErrorObjectFailed)
            return
        }

        switch result.result {
        case .success(let successResponse):
            await parseSuccess(success: successResponse)
        case .error(let error):
            let dataBrokerError: DataBrokerProtectionError = .actionFailed(actionID: error.actionID, message: error.message)
            await delegate?.onError(error: dataBrokerError)
        }
    }

    func parseSuccess(success: CCFSuccessResponse) async {
        Logger.action.log("Parse success: \(String(describing: success.actionType.rawValue), privacy: .public)")

        switch success.response {
        case .navigate(let navigate):
            if let url = URL(string: navigate.url) {
                await delegate?.loadURL(url: url)
            } else {
                await delegate?.onError(error: DataBrokerProtectionError.malformedURL)
            }
        case .extract(let profiles):
            await delegate?.extractedProfiles(profiles: profiles, meta: success.meta)
        case .getCaptchaInfo(let captchaInfo):
            await delegate?.captchaInformation(captchaInfo: captchaInfo)
        case .solveCaptcha(let response):
            await delegate?.solveCaptcha(with: response)
        case .fillForm, .click, .expectation, .executeScript, .userAssist:
            await delegate?.success(actionId: success.actionID, actionType: success.actionType)
        case .conditionSuccess(let response):
            await delegate?.conditionSuccess(actions: response.actions)
        case .none:
            break
        }
    }

    func onActionError(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        let actionID = (params as? [String: Any])?["actionID"] as? String
        guard await acceptActionResponse(actionID: actionID) else { return nil }

        let error = DataBrokerProtectionError.parse(params: params)
        Logger.action.log("Action Error: \(String(describing: error.localizedDescription), privacy: .public)")

        await delegate?.onError(error: error)
        return nil
    }

    func onUserTurnNeeded(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let actionID = (params as? [String: Any])?["actionID"] as? String,
              !(await isStale(actionID: actionID)) else { return nil }
        await delegate?.userTurnNeeded(actionID: actionID)
        return nil
    }

    private static func actionID(inCompletedParams params: Any) -> String? {
        guard let result = (params as? [String: Any])?["result"] as? [String: Any] else { return nil }
        let response = (result["success"] ?? result["error"]) as? [String: Any]
        return response?["actionID"] as? String
    }

    @MainActor
    private func isStale(actionID: String) -> Bool {
#if os(iOS)
        // iOS never runs userAssist, so it keeps accepting every reply as it did before.
        return false
#else
        guard let currentActionID else { return false }
        return actionID != currentActionID
#endif
    }

    @MainActor
    private func acceptActionResponse(actionID: String?) -> Bool {
        if let actionID, isStale(actionID: actionID) { return false }
        removeTimers()
        onActionResponse?()
        return true
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    @MainActor
    func pushAction(method: CCFSubscribeActionName, webView: WKWebView, params: Encodable) {
        guard let broker = broker else {
            assertionFailure("Cannot continue without broker instance")
            return
        }

        guard shouldContinueAction() else {
            handleJobCancellation()
            return
        }

        installTaskCancellationTimer()

        Logger.action.log("Pushing into WebView: \(method.rawValue) params \(DebugHelper.prettyPrintedJSON(from: params), privacy: .public)")

        let action = (params as? Params)?.state.action
        currentActionID = action?.id
        broker.push(method: method.rawValue, params: params, for: self, into: webView)

        // C-S-S has no timeout for userAssist; the assisted attempt owns it.
        installActionTimer(for: action is UserAssistAction ? nil : action)
    }

    @MainActor
    private func installActionTimer(for action: Action?) {
        actionResponseTimer?.invalidate()
        actionResponseTimer = nil

        guard let action else { return }

        let timer = Timer(timeInterval: executionConfig.cssActionTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeMainThread {
                self?.handleTimeout(for: action)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        actionResponseTimer = timer
    }

    @MainActor
    private func installTaskCancellationTimer() {
        taskCancellationTimer?.invalidate()
        taskCancellationTimer = nil

        let timer = Timer(timeInterval: executionConfig.cssActionCancellationCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeMainThread {
                guard let self else { return }
                if !self.shouldContinueAction() {
                    self.handleJobCancellation()
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        taskCancellationTimer = timer
    }

    @MainActor
    private func handleTimeout(for action: Action) {
        Logger.action.log("Action timeout: \(String(describing: action))")

        removeTimers()
        Task {
            await delegate?.onError(error: DataBrokerProtectionError.actionFailed(actionID: action.id,
                                                                                  message: "Action timed out"))
        }
    }

    @MainActor
    private func handleJobCancellation() {
        Logger.action.log("Job cancelled")

        removeTimers()
        Task {
            await delegate?.onError(error: DataBrokerProtectionError.cancelled)
        }
    }

    @MainActor
    func failCurrentAction(with error: Error) {
        removeTimers()
        Task {
            await delegate?.onError(error: error)
        }
    }

    @MainActor
    private func removeTimers() {
        actionResponseTimer?.invalidate()
        actionResponseTimer = nil

        taskCancellationTimer?.invalidate()
        taskCancellationTimer = nil
    }
}
