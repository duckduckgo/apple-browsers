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
import PrivacyConfig
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
    public let context: SubJobContextProviding
    public let emailConfirmationDataService: EmailConfirmationDataServiceProvider
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
    public lazy var clickAwaitTime: TimeInterval = {
        executionConfig.clickAwaitTimeForScan
    }()
    public let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    public var postLoadingSiteStartTime: Date?
    public let executionConfig: BrokerJobExecutionConfig
    public let featureFlagger: DBPFeatureFlagging

    public init(privacyConfig: PrivacyConfigurationManaging,
                prefs: ContentScopeProperties,
                context: SubJobContextProviding,
                emailConfirmationDataService: EmailConfirmationDataServiceProvider,
                captchaService: CaptchaServiceProtocol,
                featureFlagger: DBPFeatureFlagging,
                cookieHandler: CookieHandler = BrokerCookieHandler(),
                operationAwaitTime: TimeInterval = 3,
                stageDurationCalculator: StageDurationCalculator,
                pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                executionConfig: BrokerJobExecutionConfig,
                shouldRunNextStep: @escaping () -> Bool
    ) {
        self.privacyConfig = privacyConfig
        self.prefs = prefs
        self.context = context
        self.emailConfirmationDataService = emailConfirmationDataService
        self.captchaService = captchaService
        self.operationAwaitTime = operationAwaitTime
        self.stageCalculator = stageDurationCalculator
        self.shouldRunNextStep = shouldRunNextStep
        self.cookieHandler = cookieHandler
        self.pixelHandler = pixelHandler
        self.executionConfig = executionConfig
        self.featureFlagger = featureFlagger
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
                    do {
                        try await initialize(handler: webViewHandler, isFakeBroker: context.dataBroker.isFakeBroker, showWebView: showWebView)
                    } catch {
                        failed(with: error)
                    }

                    do {
                        let scanStep = try context.dataBroker.scanStep()
                        if let actionsHandler = actionsHandler {
                            self.actionsHandler = actionsHandler
                        } else {
                            self.actionsHandler = ActionsHandler.forScan(scanStep)
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

    public func executeNextStep() async {
        resetRetriesCount()
        Logger.action.debug(loggerContext(), message: "Waiting \(self.operationAwaitTime) seconds...")

        try? await Task.sleep(nanoseconds: UInt64(operationAwaitTime) * 1_000_000_000)

        let shouldContinue = self.shouldRunNextStep()
        if let action = actionsHandler?.nextAction(), shouldContinue {
            stageCalculator.setLastAction(action)
            Logger.action.debug(loggerContext(for: action), message: "Next action")
            await runNextAction(action)
        } else {
            Logger.action.debug(loggerContext(), message: "Releasing the web view")
            await webViewHandler?.finish() // If we executed all steps we release the web view

            if !shouldContinue {
                Logger.action.debug(loggerContext(), message: "Job cancelled")
                failed(with: DataBrokerProtectionError.cancelled)
            }
        }
    }

    private func loggerContext(for action: Action? = nil) -> PIRActionLogContext {
        .init(stepType: .scan, broker: context.dataBroker, attemptId: stageCalculator.attemptId, action: action)
    }
}
