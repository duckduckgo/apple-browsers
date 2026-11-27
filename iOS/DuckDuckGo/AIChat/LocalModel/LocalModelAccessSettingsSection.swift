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
import DesignResourcesKitIcons
import SwiftUI

/// Settings → AI Features → On-Device Model: shown only while the model can be used on this device.
struct LocalModelAccessSettingsSection: View {

    @ObservedObject var model: LocalModelAccessSettingsViewModel
    let isPad: Bool

    var body: some View {
        if model.isAvailable {
            Section {
                if let installState = model.downloadableModelState {
                    DownloadableLocalModelRow(modelName: model.modelName,
                                              totalBytes: model.downloadableModelBytes,
                                              state: installState,
                                              isPad: isPad,
                                              install: model.installDownloadableModel,
                                              cancel: model.cancelDownloadableModelInstall,
                                              uninstall: model.uninstallDownloadableModel)
                } else {
                    row
                }
            } header: {
                Text(UserText.localModelAccessSettingsTitle)
            } footer: {
                Text(UserText.localModelAccessSettingsFooter)
            }
            .listRowBackground(Color(designSystemColor: .surfaceTertiary))
        }
    }

    private var row: some View {
        Toggle(isOn: model.isOnBinding) {
            Text(String(format: UserText.localModelAccessUseModelTitle, model.modelName))
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
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

/// The model for devices without Apple Intelligence: Install, then progress with a stop button, then Uninstall.
private struct DownloadableLocalModelRow: View {

    let modelName: String
    let totalBytes: Int64
    let state: AIChatLocalModelInstallState
    let isPad: Bool
    let install: () -> Void
    let cancel: () -> Void
    let uninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(UserText.localModelSettingsLocalAITitle)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    Text(sizeLabel)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                detail
            }
            Spacer(minLength: 16)
            action
        }
    }

    private var sizeLabel: String {
        if case .downloading(let received, let total) = state {
            return String(format: UserText.localModelSettingsProgressFormat, Self.formatted(received), Self.formatted(total))
        }
        return String(format: UserText.localModelSettingsSizeFormat, Self.formatted(totalBytes))
    }

    @ViewBuilder
    private var detail: some View {
        switch state {
        case .downloading(let received, let total):
            SwiftUI.ProgressView(value: Double(received), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .tint(Color(designSystemColor: .accentPrimary))
        case .failed(let error):
            caption(error == .diskFull ? diskFullMessage : UserText.localModelSettingsDownloadFailed)
        case .notInstalled, .installed:
            caption(String(format: UserText.localModelSettingsModelCaption, modelName))
        }
    }

    private var diskFullMessage: String {
        isPad ? UserText.localModelSettingsDiskFullIPad : UserText.localModelSettingsDiskFullIPhone
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .daxFootnoteRegular()
            .foregroundColor(Color(designSystemColor: .textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }

    // Borderless, so a tap elsewhere in the row doesn't trigger it.
    @ViewBuilder
    private var action: some View {
        switch state {
        case .notInstalled:
            Button(UserText.localModelSettingsInstall, action: install)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("Settings.AIFeatures.LocalModelAccess.DownloadableModel.Install")
        case .downloading:
            Button(action: cancel) {
                Image(uiImage: DesignSystemImages.Glyphs.Size20.closeSolid)
                    .foregroundColor(Color(designSystemColor: .iconsTertiary))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(UserText.localModelSettingsCancelDownload)
            .accessibilityIdentifier("Settings.AIFeatures.LocalModelAccess.DownloadableModel.Cancel")
        case .installed:
            Button(UserText.localModelSettingsUninstall, action: uninstall)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("Settings.AIFeatures.LocalModelAccess.DownloadableModel.Uninstall")
        case .failed:
            Button(UserText.localModelSettingsTryAgain, action: install)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("Settings.AIFeatures.LocalModelAccess.DownloadableModel.TryAgain")
        }
    }

    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
