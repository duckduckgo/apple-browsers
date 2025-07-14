//
//  BrokerProfileScanSubJobWebRunner.swift
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
import Common
import os.log

public protocol BrokerProfileScanSubJobWebRunning {
    func scan(_ profileQuery: BrokerProfileQueryData,
              showWebView: Bool,
              shouldRunNextStep: @escaping () -> Bool) async throws -> [ExtractedProfile]
}

public final class BrokerProfileScanSubJobWebRunner: SubJobWebRunning, BrokerProfileScanSubJobWebRunning {
    public typealias ReturnValue = [ExtractedProfile]
    public typealias InputValue = Void

    public let privacyConfig: PrivacyConfigurationManaging
    public let prefs: ContentScopeProperties
    public let query: BrokerProfileQueryData
    public let emailService: EmailServiceProtocol
    public let captchaService: CaptchaServiceProtocol
    public let cookieHandler: CookieHandler
    public let stageCalculator: StageDurationCalculator
    public var webViewHandler: WebViewHandler?
    public var actionsHandler: ActionsHandler?
    public var continuation: CheckedContinuation<[ExtractedProfile], Error>?
    public var extractedProfile: ExtractedProfile?
    private let operationAwaitTime: TimeInterval
    public let shouldRunNextStep: () -> Bool
    public var retriesCountOnError: Int = 0
    public let clickAwaitTime: TimeInterval
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public var postLoadingSiteStartTime: Date?
    public let executionConfig: BrokerJobExecutionConfig

    public init(privacyConfig: PrivacyConfigurationManaging,
                prefs: ContentScopeProperties,
                query: BrokerProfileQueryData,
                emailService: EmailServiceProtocol,
                captchaService: CaptchaServiceProtocol,
                cookieHandler: CookieHandler = BrokerCookieHandler(),
                operationAwaitTime: TimeInterval = 3,
                clickAwaitTime: TimeInterval = 0,
                stageDurationCalculator: StageDurationCalculator,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                executionConfig: BrokerJobExecutionConfig,
                shouldRunNextStep: @escaping () -> Bool
    ) {
        self.privacyConfig = privacyConfig
        self.prefs = prefs
        self.query = query
        self.emailService = emailService
        self.captchaService = captchaService
        self.operationAwaitTime = operationAwaitTime
        self.stageCalculator = stageDurationCalculator
        self.shouldRunNextStep = shouldRunNextStep
        self.clickAwaitTime = clickAwaitTime
        self.cookieHandler = cookieHandler
        self.pixelHandler = pixelHandler
        self.executionConfig = executionConfig
    }

    @MainActor
    public func scan(_ profileQuery: BrokerProfileQueryData,
                     showWebView: Bool,
                     shouldRunNextStep: @escaping () -> Bool) async throws -> [ExtractedProfile] {
        return try await self.run(inputValue: (), showWebView: showWebView)
    }

    @MainActor
    public func run(inputValue: InputValue,
                    webViewHandler: WebViewHandler? = nil,
                    actionsHandler: ActionsHandler? = nil,
                    showWebView: Bool) async throws -> [ExtractedProfile] {
        var task: Task<Void, Never>?

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                guard self.shouldRunNextStep() else {
                    failed(with: DataBrokerProtectionError.cancelled)
                    return
                }

                task = Task {
                    await initialize(handler: webViewHandler, isFakeBroker: query.dataBroker.isFakeBroker, showWebView: showWebView)
                    do {
                        let scanStep = try query.dataBroker.scanStep()
                        if let actionsHandler = actionsHandler {
                            self.actionsHandler = actionsHandler
                        } else {
                            self.actionsHandler = ActionsHandler(step: scanStep)
                        }
                        if self.shouldRunNextStep() {
                            await executeNextStep()
                        } else {
                            failed(with: DataBrokerProtectionError.cancelled)
                        }
                    } catch {
                        failed(with: DataBrokerProtectionError.unknown(error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                task?.cancel()
            }
        }
    }

    public func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {
        complete(profiles)
        await executeNextStep()
    }

    public func evaluateActionAndHaltIfNeeded(_ action: Action) async -> Bool {
        /// Certain brokers force a page reload with a random time interval when the user lands on the search result
        /// page. The first time the action runs the C-S-S context is lost as the page is reloading and C-S-S fails
        /// to respond to the native message. We will try to run the action one more time after the page has loaded
        /// and the C-S-S context is present again to receive the native message.
        ///
        /// To minimize the impact of this change, we set the number of retries to 1 for now.
        ///
        /// https://app.asana.com/1/137249556945/project/481882893211075/task/1210079565270206?focus=true
        if action is ExpectationAction, !stageCalculator.isRetrying {
            retriesCountOnError = 1
        }

        return false
    }

    public func executeNextStep() async {
        resetRetriesCount()
        Logger.action.debug("SCAN Waiting \(self.operationAwaitTime, privacy: .public) seconds...")

        try? await Task.sleep(nanoseconds: UInt64(operationAwaitTime) * 1_000_000_000)

        if let action = actionsHandler?.nextAction(), self.shouldRunNextStep() {
            Logger.action.debug("Next action: \(String(describing: action.actionType.rawValue), privacy: .public)")
            await runNextAction(action)
        } else {
            Logger.action.debug("Releasing the web view")
            await webViewHandler?.finish() // If we executed all steps we release the web view
        }
    }
}
