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

import DataBrokerProtectionCore
import Foundation
import PIRDebugKit

extension DataBrokerRunCustomJSONViewModel: DebugModeEmailConfirming {
    var emailConfirmationStore: EmailConfirmationSupporting {
        session?.emailConfirmationStore ?? placeholderEmailConfirmationStore
    }

    func checkForEmailConfirmation() {
        updateProgress("Checking email confirmations...")
        guard let session = session else {
            progressText = "Idle"
            isProgressActive = false
            return
        }
        Task {
            do {
                _ = try await session.checkEmailConfirmation()
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

    func continueOptOutAfterEmailConfirmation(scanResult: DebugScanResult) {
        guard let confirmationURL = confirmationURL(for: scanResult),
              let session = session else { return }
        isProgressActive = true
        progressText = "Continuing opt-out..."
        currentStepType = .optOut
        Task { @MainActor in
            do {
                let result = try await session.continueOptOut(afterEmailURL: confirmationURL)
                if result.success {
                    self.addOptOutConfirmedEvent(for: scanResult)
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    self.showAlert = true
                    self.alert = AlertUI(title: "Success!", description: "We finished the opt out process for the selected profile.")
                } else {
                    let error = DataBrokerProtectionError.unknown(result.error ?? "Unknown error")
                    self.addOptOutErrorEvent(for: scanResult, error: error)
                    self.isProgressActive = false
                    self.progressText = "Idle"
                    self.showAlert(for: error)
                }
            } catch {
                self.addOptOutErrorEvent(for: scanResult, error: error)
                self.isProgressActive = false
                self.progressText = "Idle"
                self.showAlert(for: error)
            }
        }
    }

}
