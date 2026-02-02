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

// MARK: - Email Confirmation

extension RunDBPDebugModeViewModel: DebugModeEmailConfirming {
    var emailConfirmationStore: EmailConfirmationSupporting {
        debugEmailConfirmationStore
    }
}

extension RunDBPDebugModeViewModel {
    func emailConfirmationStatusText(for result: DebugScanResult) -> String? {
        guard result.dataBroker.requiresEmailConfirmationDuringOptOut() else { return nil }

        if confirmationURL(for: result) != nil {
            return "Confirmation link ready"
        }

        if isAwaitingEmailConfirmation(for: result) {
            return "Awaiting email confirmation"
        }

        return nil
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

    func continueOptOutAfterEmailConfirmation(for result: DebugScanResult) {
        guard let confirmationURL = confirmationURL(for: result) else { return }

        optOutInProgress.insert(result.id)
        updateWebViewAvailability()

        Task { @MainActor in
            defer {
                optOutInProgress.remove(result.id)
                updateWebViewAvailability()
                self.currentOptOutRunner = nil
                self.hideWebView()
                self.currentWebViewManager = nil
            }

            do {
                let brokerId = result.dataBroker.id ?? DebugHelper.stableId(for: result.dataBroker)
                let profileQueryId = result.profileQuery.id ?? DebugHelper.stableId(for: result.profileQuery)
                let brokerProfileQueryData = BrokerProfileQueryData(
                    dataBroker: result.dataBroker,
                    profileQuery: result.profileQuery,
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
                    extractedProfile: result.extractedProfile,
                    showWebView: true
                ) { true }

                showAlert(title: "Success",
                          message: "Opt-out process completed for \(result.extractedProfile.name ?? "profile").")
            } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                pixelHandler?.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                try await Task.sleep(interval: 1.0)
                fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
            } catch {
                showAlert(title: "Error", message: "Opt-out failed: \(error.localizedDescription)")
            }
        }
    }

    func ensureDebugProfileQuery(_ query: ProfileQuery, index: Int) -> ProfileQuery {
        if let id = query.id {
            return query.with(id: id)
        }

        let fallbackId = DebugHelper.stableId(for: query)
        return query.with(id: fallbackId == 0 ? Int64(index + 1) : fallbackId)
    }

    func ensureDebugExtractedProfile(_ profile: ExtractedProfile) -> ExtractedProfile {
        guard profile.id == nil else { return profile }
        return ExtractedProfile(id: DebugHelper.stableId(for: profile),
                                name: profile.name,
                                alternativeNames: profile.alternativeNames,
                                addressFull: profile.addressFull,
                                addresses: profile.addresses,
                                phoneNumbers: profile.phoneNumbers,
                                relatives: profile.relatives,
                                profileUrl: profile.profileUrl,
                                reportId: profile.reportId,
                                age: profile.age,
                                email: profile.email,
                                removedDate: profile.removedDate,
                                identifier: profile.identifier)
    }
}
