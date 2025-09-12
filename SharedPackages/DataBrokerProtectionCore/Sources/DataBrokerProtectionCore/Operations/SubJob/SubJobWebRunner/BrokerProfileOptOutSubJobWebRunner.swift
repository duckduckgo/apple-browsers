//
//  BrokerProfileOptOutSubJobWebRunner.swift
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

public protocol BrokerProfileOptOutSubJobWebRunning {
    func optOut(profileQuery: BrokerProfileQueryData,
                extractedProfile: ExtractedProfile,
                showWebView: Bool,
                shouldRunNextStep: @escaping () -> Bool) async throws
}

public final class BrokerProfileOptOutSubJobWebRunner: SubJobWebRunning, BrokerProfileOptOutSubJobWebRunning {
    public typealias ReturnValue = Void
    public typealias InputValue = ExtractedProfile

    public let privacyConfig: PrivacyConfigurationManaging
    public let prefs: ContentScopeProperties
    public let context: SubJobContextProviding
    public let emailService: EmailServiceProtocol
    public let captchaService: CaptchaServiceProtocol
    public let cookieHandler: CookieHandler
    public let stageCalculator: StageDurationCalculator
    public var webViewHandler: WebViewHandler?
    public var actionsHandler: ActionsHandler?
    public var continuation: CheckedContinuation<Void, Error>?
    public var extractedProfile: ExtractedProfile?
    private let operationAwaitTime: TimeInterval
    public let shouldRunNextStep: () -> Bool
    public let clickAwaitTime: TimeInterval
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public var postLoadingSiteStartTime: Date?
    public let executionConfig: BrokerJobExecutionConfig
    public let featureFlagger: DBPFeatureFlagging

    public var retriesCountOnError: Int = 3

    public init(privacyConfig: PrivacyConfigurationManaging,
                prefs: ContentScopeProperties,
                context: SubJobContextProviding,
                emailService: EmailServiceProtocol,
                captchaService: CaptchaServiceProtocol,
                featureFlagger: DBPFeatureFlagging,
                cookieHandler: CookieHandler = BrokerCookieHandler(),
                operationAwaitTime: TimeInterval = 3,
                clickAwaitTime: TimeInterval = 40,
                stageCalculator: StageDurationCalculator,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                executionConfig: BrokerJobExecutionConfig,
                shouldRunNextStep: @escaping () -> Bool) {
        self.privacyConfig = privacyConfig
        self.prefs = prefs
        self.context = context
        self.emailService = emailService
        self.captchaService = captchaService
        self.operationAwaitTime = operationAwaitTime
        self.stageCalculator = stageCalculator
        self.shouldRunNextStep = shouldRunNextStep
        self.clickAwaitTime = clickAwaitTime
        self.cookieHandler = cookieHandler
        self.pixelHandler = pixelHandler
        self.executionConfig = executionConfig
        self.featureFlagger = featureFlagger
    }

    public func optOut(profileQuery: BrokerProfileQueryData,
                       extractedProfile: ExtractedProfile,
                       showWebView: Bool,
                       shouldRunNextStep: @escaping () -> Bool) async throws {
        try await run(inputValue: extractedProfile, showWebView: showWebView)
    }

    @MainActor
    public func run(inputValue: ExtractedProfile,
                    webViewHandler: WebViewHandler? = nil,
                    actionsHandler: ActionsHandler? = nil,
                    showWebView: Bool = false) async throws {
        var task: Task<Void, Never>?

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.extractedProfile = inputValue.merge(with: context.profileQuery)
                self.continuation = continuation

                guard self.shouldRunNextStep() else {
                    failed(with: DataBrokerProtectionError.cancelled)
                    return
                }

                task = Task {
                    do {
                        try await initialize(handler: webViewHandler,
                                         isFakeBroker: context.dataBroker.isFakeBroker,
                                         showWebView: showWebView)
                    } catch {
                        failed(with: error)
                    }

                    if let optOutStep = context.dataBroker.optOutStep() {
                        if let actionsHandler = actionsHandler {
                            self.actionsHandler = actionsHandler
                        } else {
                            self.actionsHandler = ActionsHandler.forOptOut(optOutStep, haltsAtEmailConfirmation: featureFlagger.isEmailConfirmationDecouplingFeatureOn)
                        }

                        if self.shouldRunNextStep() {
                            await executeNextStep()
                        } else {
                            failed(with: DataBrokerProtectionError.cancelled)
                        }

                    } else {
                        // If we try to run an optout on a broker without an optout step, we throw.
                        failed(with: DataBrokerProtectionError.noOptOutStep)
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
        // No - op
    }

    public func executeNextStep() async {
        resetRetriesCount()
        Logger.action.debug(loggerContext(), message: "Waiting \(self.operationAwaitTime) seconds...")
        try? await Task.sleep(nanoseconds: UInt64(operationAwaitTime) * 1_000_000_000)

        let shouldContinue = self.shouldRunNextStep()
        if let action = actionsHandler?.nextAction(), shouldContinue {
            stageCalculator.setLastActionId(action.id)
            Logger.action.debug(loggerContext(for: action), message: "Next action")
            await runNextAction(action)
        } else {
            Logger.action.debug(loggerContext(), message: "Releasing the web view")
            await webViewHandler?.finish() // If we executed all steps we release the web view

            if shouldContinue {
                Logger.action.debug(loggerContext(), message: "Job completed")
                complete(())
            } else {
                Logger.action.debug(loggerContext(), message: "Job canceled")
                failed(with: DataBrokerProtectionError.cancelled)
            }
        }
    }

    private func loggerContext(for action: Action? = nil) -> PIRActionLogContext {
        .init(stepType: .optOut, broker: context.dataBroker, attemptId: stageCalculator.attemptId, action: action)
    }
}
