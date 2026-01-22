//
//  DataBrokerRunCustomJSONViewModel+EmailConfirmation.swift
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
import UserScript

extension DataBrokerRunCustomJSONViewModel {

    func canCheckEmailConfirmation(for scanResult: ScanResult) -> Bool {
        guard let extractedProfileId = scanResult.extractedProfile.id,
              scanResult.dataBroker.requiresEmailConfirmationDuringOptOut() else {
            return false
        }
        return awaitingEmailConfirmationProfileIds.contains(extractedProfileId)
    }

    func canContinueOptOutAfterEmailConfirmation(for scanResult: ScanResult) -> Bool {
        guard canCheckEmailConfirmation(for: scanResult) else { return false }
        return confirmationURL(for: scanResult) != nil
    }

    func checkForEmailConfirmation() {
        updateProgress("Checking email confirmations...")
        let emailConfirmationDataService = emailConfirmationDataService
        Task {
            do {
                try await emailConfirmationDataService.checkForEmailConfirmationData()
                await MainActor.run { [weak self] in
                    self?.progressText = "Idle"
                    self?.isProgressActive = false
                    self?.showAlert = true
                    self?.alert = AlertUI(title: "Email confirmation check complete",
                                          description: "Use \"Continue opt-out\" to resume the process.")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.progressText = "Idle"
                    self?.isProgressActive = false
                    self?.showAlert(for: error)
                }
            }
        }
    }

    func continueOptOutAfterEmailConfirmation(scanResult: ScanResult) {
        guard let confirmationURL = confirmationURL(for: scanResult) else { return }
        isProgressActive = true
        progressText = "Continuing opt-out..."
        let brokerProfileQueryData = BrokerProfileQueryData(
            dataBroker: scanResult.dataBroker,
            profileQuery: scanResult.profileQuery,
            scanJobData: ScanJobData(
                brokerId: DebugHelper.stableId(for: scanResult.dataBroker),
                profileQueryId: DebugHelper.stableId(for: scanResult.profileQuery),
                historyEvents: [HistoryEvent]()
            )
        )
        Task {
            do {
                let stageCalculator = FakeStageDurationCalculator { [weak self] kind, actionType, details in
                    let profileQuery = self?.profileQueryText(for: brokerProfileQueryData.profileQuery) ?? "-"
                    let summary = self?.actionSummary(stepType: .optOut, actionType: actionType) ?? "-"
                    let progressText = self?.currentActionText(stepType: .optOut,
                                                               actionType: actionType,
                                                               prefix: kind.rawValue) ?? "-"
                    self?.addDebugEvent(kind: kind,
                                        summary: summary,
                                        profileQueryLabel: profileQuery,
                                        details: details,
                                        progressText: progressText)
                }
                let runner = BrokerProfileOptOutSubJobWebRunner(
                    privacyConfig: self.privacyConfigManager,
                    prefs: self.contentScopeProperties,
                    context: brokerProfileQueryData,
                    emailConfirmationDataService: self.emailConfirmationDataService,
                    captchaService: self.captchaService,
                    featureFlagger: self.featureFlagger,
                    stageCalculator: stageCalculator,
                    pixelHandler: fakePixelHandler,
                    executionConfig: .init(),
                    actionsHandlerMode: .emailConfirmation(confirmationURL),
                    shouldRunNextStep: { true }
                )

                try await runner.optOut(profileQuery: brokerProfileQueryData,
                                        extractedProfile: scanResult.extractedProfile,
                                        showWebView: true) { true }

                addOptOutConfirmedEvent(for: scanResult)
                Task { @MainActor in
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    self.showAlert = true
                    self.alert = AlertUI(title: "Success!", description: "We finished the opt out process for the selected profile.")
                }
            } catch let UserScriptError.failedToLoadJS(jsFile, error) {
                pixelHandler.fire(.userScriptLoadJSFailed(jsFile: jsFile, error: error))
                try await Task.sleep(interval: 1.0) // give time for the pixel to be sent
                fatalError("Failed to load JS file \(jsFile): \(error.localizedDescription)")
            } catch {
                addOptOutErrorEvent(for: scanResult, error: error)
                Task { @MainActor in
                    self.isProgressActive = false
                    self.progressText = "Idle"
                }
                showAlert(for: error)
            }
        }
    }

    @MainActor
    func updateEmailConfirmationState(for event: HistoryEvent) {
        guard let extractedProfileId = event.extractedProfileId else { return }
        switch event.type {
        case .optOutSubmittedAndAwaitingEmailConfirmation:
            awaitingEmailConfirmationProfileIds.insert(extractedProfileId)
        case .optOutConfirmed, .matchRemovedByUser:
            awaitingEmailConfirmationProfileIds.remove(extractedProfileId)
        default:
            break
        }
    }

    private func confirmationURL(for scanResult: ScanResult) -> URL? {
        guard let extractedProfileId = scanResult.extractedProfile.id else { return nil }
        let brokerId = DebugHelper.stableId(for: scanResult.dataBroker)
        let profileQueryId = DebugHelper.stableId(for: scanResult.profileQuery)
        guard let confirmations = try? emailConfirmationStore.fetchOptOutEmailConfirmationsWithLink(),
              let match = confirmations.first(where: {
                  $0.brokerId == brokerId &&
                  $0.profileQueryId == profileQueryId &&
                  $0.extractedProfileId == extractedProfileId
              }),
              let link = match.emailConfirmationLink else { return nil }
        return URL(string: link)
    }
}
