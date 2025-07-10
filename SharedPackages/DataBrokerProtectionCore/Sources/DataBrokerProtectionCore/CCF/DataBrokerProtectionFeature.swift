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

import Foundation
import WebKit
import BrowserServicesKit
import UserScript
import os.log
import Common

public protocol CCFCommunicationDelegate: AnyObject {
    func loadURL(url: URL) async
    func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async
    func captchaInformation(captchaInfo: GetCaptchaInfoResponse) async
    func solveCaptcha(with response: SolveCaptchaResponse) async
    func success(actionId: String, actionType: ActionType) async
    func onError(error: Error) async
}

public enum CCFSubscribeActionName: String {
    case onActionReceived
}

public enum CCFReceivedMethodName: String {
    case actionCompleted
    case actionError
}

public class DataBrokerProtectionFeature: Subfeature {
    public var messageOriginPolicy: MessageOriginPolicy = .all
    public var featureName: String = "brokerProtection"
    public weak var broker: UserScriptMessageBroker? // This broker is not related to DBP brokers. It's just a name we inherit from Subfeature

    weak var delegate: CCFCommunicationDelegate?

    private var actionResponseTimer: Timer?
    private let actionResponseTimeout: TimeInterval

    public struct Constants {
        /// Default timeout for C-S-S action responses that can hang due to page reloads or script context loss
        public static let defaultActionResponseTimeout: TimeInterval = 60
    }

    public init(delegate: CCFCommunicationDelegate,
                actionResponseTimeout: TimeInterval = Constants.defaultActionResponseTimeout) {
        self.delegate = delegate
        self.actionResponseTimeout = actionResponseTimeout
    }

    deinit {
        removeTimer()
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        let actionResult = CCFReceivedMethodName(rawValue: methodName)

        if let actionResult = actionResult {
            switch actionResult {
            case .actionCompleted: return onActionCompleted
            case .actionError: return onActionError
            }
        } else {
            Logger.action.log("Cant parse method: \(methodName, privacy: .public)")
            return nil
        }
    }

    func onActionCompleted(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        removeTimer()

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
        case .fillForm, .click, .expectation:
            await delegate?.success(actionId: success.actionID, actionType: success.actionType)
        default: return
        }
    }

    func onActionError(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        removeTimer()

        let error = DataBrokerProtectionError.parse(params: params)
        Logger.action.log("Action Error: \(String(describing: error.localizedDescription), privacy: .public)")

        await delegate?.onError(error: error)
        return nil
    }

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    func pushAction(method: CCFSubscribeActionName, webView: WKWebView, params: Encodable, canTimeOut: Bool) {
        guard let broker = broker else {
            assertionFailure("Cannot continue without broker instance")
            return
        }
        Logger.action.log("Pushing into WebView: \(method.rawValue) params \(String(describing: params))")

        broker.push(method: method.rawValue, params: params, for: self, into: webView)

        if canTimeOut {
            installTimer(for: (params as? Params)?.state.action)
        }
    }

    private func installTimer(for action: Action?) {
        guard let action else { return }

        removeTimer()
        actionResponseTimer = Timer.scheduledTimer(withTimeInterval: actionResponseTimeout, repeats: false) { [weak self] _ in
            self?.handleTimeout(for: action)
        }
    }

    private func handleTimeout(for action: Action) {
        Logger.action.log("Action timeout: \(String(describing: action))")

        removeTimer()
        Task {
            await delegate?.onError(error: DataBrokerProtectionError.actionFailed(actionID: action.id,
                                                                                  message: "Action timed out"))
        }
    }

    private func removeTimer() {
        actionResponseTimer?.invalidate()
        actionResponseTimer = nil
    }
}
