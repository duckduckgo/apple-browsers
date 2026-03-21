//
//  SaveRecoveryKeyViewModel.swift
//  DuckDuckGo
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
import UIKit

public class SaveRecoveryKeyViewModel: ObservableObject {

    let key: String
    let showRecoveryPDFAction: () -> Void
    let isAutoRestoreFeatureEnabled: Bool

    @Published var isAutoRestoreEnabled = false

    private let onDismiss: () -> Void
    private let autoRestoreToggleShownAction: () -> Void
    private let autoRestoreToggleOptedOutAction: () -> Void
    private let autoRestoreProvider: SyncAutoRestoreProviding

    public init(
        key: String,
        showRecoveryPDFAction: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        autoRestoreProvider: SyncAutoRestoreProviding,
        onAutoRestoreToggleShown: @escaping () -> Void = {},
        onAutoRestoreToggleOptedOut: @escaping () -> Void = {}
    ) {
        self.key = key
        self.showRecoveryPDFAction = showRecoveryPDFAction
        self.onDismiss = onDismiss
        self.autoRestoreToggleShownAction = onAutoRestoreToggleShown
        self.autoRestoreToggleOptedOutAction = onAutoRestoreToggleOptedOut
        self.autoRestoreProvider = autoRestoreProvider
        self.isAutoRestoreFeatureEnabled = autoRestoreProvider.isAutoRestoreFeatureEnabled

        if isAutoRestoreFeatureEnabled {
            if let decision = autoRestoreProvider.existingDecision() {
                self.isAutoRestoreEnabled = decision
            } else {
                do {
                    try autoRestoreProvider.persistDecision(true)
                    self.isAutoRestoreEnabled = true
                } catch {
                    self.isAutoRestoreEnabled = false
                }
            }
        }
    }

    func copyKey() {
        UIPasteboard.general.string = key
    }

    func autoRestoreViewShown() {
        guard isAutoRestoreFeatureEnabled else { return }
        autoRestoreToggleShownAction()
    }

    func nextButtonPressed() {
        if isAutoRestoreFeatureEnabled && !isAutoRestoreEnabled {
            autoRestoreToggleOptedOutAction()
        }
        onDismiss()
    }

    func autoRestoreToggled(_ isEnabled: Bool) {
        guard isEnabled != isAutoRestoreEnabled else { return }

        do {
            try autoRestoreProvider.persistDecision(isEnabled)
            isAutoRestoreEnabled = isEnabled
        } catch {
            return
        }
    }

}
