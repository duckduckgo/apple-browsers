//
//  LocalModelAccessSettingsSection.swift
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

import AIChat
import DesignResourcesKit
import SwiftUI

/// Settings → AI Features → On-Device Model: shown only while the model can be used on this device.
struct LocalModelAccessSettingsSection: View {

    @ObservedObject var model: LocalModelAccessSettingsViewModel
    let isPad: Bool

    var body: some View {
        if model.isAvailable {
            Section {
                row
            } header: {
                Text(UserText.localModelAccessSettingsTitle)
            } footer: {
                Text(isPad ? UserText.localModelAccessSettingsFooterIPad : UserText.localModelAccessSettingsFooterIPhone)
            }
            .listRowBackground(Color(designSystemColor: .surfaceTertiary))
        }
    }

    private var row: some View {
        Toggle(isOn: model.isOnBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(UserText.localModelAccessSystemModelTitle)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(String(format: UserText.localModelAccessSystemModelCaption, model.modelName))
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accentPrimary)))
        .accessibilityIdentifier("Settings.AIFeatures.LocalModelAccess.AppleIntelligenceToggle")
        .alert(UserText.localModelAccessTurnOnConfirmationTitle, isPresented: $model.isConfirmingTurnOn) {
            Button(UserText.actionCancel, role: .cancel) { model.cancelTurnOn() }
            Button(UserText.localModelAccessTurnOn) { model.confirmTurnOn() }
        } message: {
            Text(isPad ? UserText.localModelAccessTurnOnConfirmationMessageIPad : UserText.localModelAccessTurnOnConfirmationMessageIPhone)
        }
    }
}
