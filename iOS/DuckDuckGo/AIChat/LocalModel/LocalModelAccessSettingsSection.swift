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

/// Settings → AI Features → Local Model Access: shown only while the model can be used on this device.
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
                Text(footer)
                    .environment(\.openURL, OpenURLAction { _ in
                        model.openLearnMore()
                        return .handled
                    })
            }
            .listRowBackground(Color(designSystemColor: .surfaceTertiary))
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            AppleIntelligenceGlyph(size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.modelName)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.localModelAccessAppleIntelligenceCaption)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
            }
            Spacer()
            Toggle(model.modelName, isOn: model.isOnBinding)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accentPrimary)))
                .accessibilityIdentifier("Settings.AIFeatures.LocalModelAccess.AppleIntelligenceToggle")
        }
        .alert(UserText.localModelAccessTurnOnConfirmationTitle, isPresented: $model.isConfirmingTurnOn) {
            Button(UserText.actionCancel, role: .cancel) { model.cancelTurnOn() }
            Button(UserText.localModelAccessTurnOn) { model.confirmTurnOn() }
        } message: {
            Text(isPad ? UserText.localModelAccessTurnOnConfirmationMessageIPad : UserText.localModelAccessTurnOnConfirmationMessageIPhone)
        }
    }

    private var footer: AttributedString {
        var footer = AttributedString(UserText.localModelAccessSettingsFooter + " ")
        var link = AttributedString(UserText.aiFeaturesLearnMore)
        link.foregroundColor = Color(designSystemColor: .accentPrimary)
        link.link = URL.aiChatHelpPages
        footer.append(link)
        return footer
    }
}
