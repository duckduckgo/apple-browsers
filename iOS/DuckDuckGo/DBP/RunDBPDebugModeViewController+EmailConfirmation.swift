//
//  RunDBPDebugModeViewController+EmailConfirmation.swift
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

import Foundation
import DataBrokerProtectionCore
import enum UserScript.UserScriptError

extension RunDBPDebugModeViewModel: DebugModeEmailConfirming {
    var emailConfirmationStore: EmailConfirmationSupporting {
        debugEmailConfirmationStore
    }

    func checkForEmailConfirmation() {
        Task { @MainActor in
            do {
                try await emailConfirmationDataService.checkForEmailConfirmationData()
                showAlert(title: "Email Confirmation Check Complete",
                          message: "If a link is ready, you can continue the opt-out.")
            } catch {
                showAlert(title: "Error", message: error.localizedDescription)
            }
        }
    }

    func continueOptOutAfterEmailConfirmation(scanResult: DebugScanResult) {
        guard let confirmationURL = confirmationURL(for: scanResult) else { return }

        optOutInProgress.insert(scanResult.id)
        updateWebViewAvailability()

        Task { @MainActor in
            defer {
                optOutInProgress.remove(scanResult.id)
                updateWebViewAvailability()
                self.currentOptOutRunner = nil
                self.hideWebView()
                self.currentWebViewManager = nil
            }

            do {
                let brokerId = DebugHelper.stableId(for: scanResult.dataBroker)
                let profileQueryId = DebugHelper.stableId(for: scanResult.profileQuery)
                let brokerProfileQueryData = BrokerProfileQueryData(
                    dataBroker: scanResult.dataBroker,
                    profileQuery: scanResult.profileQuery,
                    scanJobData: ScanJobData(
                        brokerId: brokerId,
                        profileQueryId: profileQueryId,
                        historyEvents: []
                    )
                )

                let runner = BrokerProfileOptOutSubJobWebRunner(
                    privacyConfig: privacyConfigManager,
                    prefs: contentScopeProperties,
                    context: brokerProfileQueryData,
                    emailConfirmationDataService: emailConfirmationDataService,
                    captchaService: captchaService,
                    featureFlagger: featureFlagger,
                    stageCalculator: FakeStageDurationCalculator(),
                    pixelHandler: fakePixelHandler,
                    executionConfig: executionConfig,
                    actionsHandlerMode: .emailConfirmation(confirmationURL)
                ) { true }

                self.currentOptOutRunner = runner

                try await runner.optOut(
                    profileQuery: brokerProfileQueryData,
                    extractedProfile: scanResult.extractedProfile,
                    showWebView: true
                ) { true }

                showAlert(title: "Success",
                          message: "Opt-out process completed for \(scanResult.extractedProfile.name ?? "profile").")
            } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                pixelHandler?.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                try await Task.sleep(interval: 1.0)
                fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
            } catch {
                showAlert(title: "Error", message: "Opt-out failed: \(error.localizedDescription)")
            }
        }
    }

}
