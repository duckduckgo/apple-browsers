//
//  DebugScanJob.swift
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
import DataBrokerProtectionCore

struct DebugScanReturnValue {
    let brokerURL: String
    let extractedProfiles: [ExtractedProfile]
    let error: Error?
    let context: SubJobContextProviding
    let meta: [String: Any]?

    init(brokerURL: String,
         extractedProfiles: [ExtractedProfile] = [ExtractedProfile](),
         error: Error? = nil,
         context: SubJobContextProviding,
         meta: [String: Any]? = nil) {
        self.brokerURL = brokerURL
        self.extractedProfiles = extractedProfiles
        self.error = error
        self.context = context
        self.meta = meta
    }
}

struct EmptyCookieHandler: CookieHandler {
    func getAllCookiesFromDomain(_ url: URL) async -> [HTTPCookie]? {
        return nil
    }
}

final class DebugScanJob: SubJobWebRunning {
    typealias ReturnValue = DebugScanReturnValue
    typealias InputValue = Void

    let privacyConfig: PrivacyConfigurationManaging
    let prefs: ContentScopeProperties
    let context: SubJobContextProviding
    let emailConfirmationDataService: EmailConfirmationDataServiceProvider
    let captchaService: CaptchaServiceProtocol
    let stageCalculator: StageDurationCalculator
    let executionConfig: BrokerJobExecutionConfig
    var webViewHandler: WebViewHandler?
    var actionsHandler: ActionsHandler?
    var continuation: CheckedContinuation<DebugScanReturnValue, Error>?
    var extractedProfile: ExtractedProfile?
    private let operationAwaitTime: TimeInterval
    let shouldRunNextStep: () -> Bool
    var retriesCountOnError: Int = 0
    var scanURL: String?
    let clickAwaitTime: TimeInterval
    let cookieHandler: CookieHandler
    let pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>
    var postLoadingSiteStartTime: Date?
    let featureFlagger: DBPFeatureFlagging

    private let fileManager = FileManager.default
    private let debugScanContentPath: String?

    init(privacyConfig: PrivacyConfigurationManaging,
         prefs: ContentScopeProperties,
         context: SubJobContextProviding,
         emailConfirmationDataService: EmailConfirmationDataServiceProvider,
         captchaService: CaptchaServiceProtocol,
         featureFlagger: DBPFeatureFlagging,
         executionConfig: BrokerJobExecutionConfig = BrokerJobExecutionConfig(),
         operationAwaitTime: TimeInterval = 3,
         clickAwaitTime: TimeInterval = 0,
         shouldRunNextStep: @escaping () -> Bool
    ) {
        self.privacyConfig = privacyConfig
        self.prefs = prefs
        self.context = context
        self.emailConfirmationDataService = emailConfirmationDataService
        self.captchaService = captchaService
        self.executionConfig = executionConfig
        self.operationAwaitTime = operationAwaitTime
        self.shouldRunNextStep = shouldRunNextStep
        self.clickAwaitTime = clickAwaitTime
        self.featureFlagger = featureFlagger
        if let desktopPath = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first?.relativePath {
            self.debugScanContentPath = desktopPath + "/PIR-Debug"
        } else {
            self.debugScanContentPath = nil
        }
        self.cookieHandler = EmptyCookieHandler()
        stageCalculator = FakeStageDurationCalculator()
        pixelHandler =  EventMapping(mapping: { _, _, _, _ in
            // We do not need the pixel handler for the debug
        })
    }

    public func run(inputValue: Void,
                    webViewHandler: WebViewHandler? = nil,
                    actionsHandler: ActionsHandler? = nil,
                    showWebView: Bool) async throws -> DebugScanReturnValue {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task {
                do {
                    try await initialize(handler: webViewHandler, isFakeBroker: context.dataBroker.isFakeBroker, showWebView: showWebView)
                } catch {
                    if case let UserScriptError.failedToLoadJS(jsFile, error) = error {
                        pixelHandler.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                        try await Task.sleep(interval: 1.0) // give time for the pixel to be sent
                    }
                    fatalError("Failed to initialize handler for DebugScanJob: \(error.localizedDescription)")
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
    }

    public func runNextAction(_ action: Action) async {
        if action is ExtractAction {
            do {
                if let path = self.debugScanContentPath {
                    let fileName = "\(context.profileQuery.id ?? 0)_\(context.dataBroker.name)"
                    try await webViewHandler?.takeSnaphost(path: path + "/screenshots/", fileName: "\(fileName).png")
                    try await webViewHandler?.saveHTML(path: path + "/html/", fileName: "\(fileName).html")
                }
            } catch {
                print("Error: \(error)")
            }
        }

        await webViewHandler?.execute(action: action,
                                      ofType: actionsHandler?.stepType,
                                      data: .userData(context.profileQuery, self.extractedProfile))
    }

    public func extractedProfiles(profiles: [ExtractedProfile], meta: [String: Any]?) async {
        if let scanURL = self.scanURL {
            let debugScanReturnValue = DebugScanReturnValue(
                brokerURL: scanURL,
                extractedProfiles: profiles,
                context: context,
                meta: meta
            )
            complete(debugScanReturnValue)
        }

        await executeNextStep()
    }

    public func completeWith(error: Error) async {
        if let scanURL = self.scanURL {
            let debugScanReturnValue = DebugScanReturnValue(brokerURL: scanURL, error: error, context: context)
            complete(debugScanReturnValue)
        }

        await executeNextStep()
    }

    func evaluateActionAndHaltIfNeeded(_ action: Action) async -> Bool {
        if action.actionType == .expectation, !stageCalculator.isRetrying {
            retriesCountOnError = 1
        }

        return false
    }

    public func executeNextStep() async {
        resetRetriesCount()
        Logger.action.debug("SCAN Waiting \(self.operationAwaitTime, privacy: .public) seconds...")

        try? await Task.sleep(nanoseconds: UInt64(operationAwaitTime) * 1_000_000_000)

        if let action = actionsHandler?.nextAction() {
            Logger.action.debug("Next action: \(String(describing: action.actionType.rawValue), privacy: .public)")
            await runNextAction(action)
        } else {
            Logger.action.debug("Releasing the web view")
            await webViewHandler?.finish() // If we executed all steps we release the web view
            continuation = nil
            webViewHandler = nil
        }
    }

    public func loadURL(url: URL) async {
        do {
            self.scanURL = url.absoluteString
            try await webViewHandler?.load(url: url)
            await executeNextStep()
        } catch {
            await completeWith(error: error)
        }
    }

    deinit {
        Logger.action.debug("DebugScanOperation Deinit")
    }
}
