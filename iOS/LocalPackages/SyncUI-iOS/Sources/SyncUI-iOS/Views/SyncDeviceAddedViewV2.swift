//
//  SyncDeviceAddedViewV2.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import SwiftUI

struct SyncDeviceAddedViewV2: View {

    @ObservedObject var model: SyncSettingsViewModel

    private var autoRestoreBinding: Binding<Bool> {
        Binding {
            model.isAutoRestoreEnabled
        } set: { newValue in
            model.requestAutoRestoreUpdate(enabled: newValue)
        }
    }

    var body: some View {
        NavigationView {
            List {
                headerSection
                recoveryCodeSection

                if model.isAutoRestoreFeatureAvailable {
                    autoRestoreSection
                }
            }
            .applyListStyle()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    doneButton
                        .accessibilityLabel(UserText.doneButton)
                }
            }
        }
    }

    @ViewBuilder
    private var doneButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: model.deviceConnectedDoneFromConnectingSheet) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.check)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(designSystemColor: .accentPrimary))
        } else {
            Button(action: model.deviceConnectedDoneFromConnectingSheet) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.check)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(designSystemColor: .accentPrimary))
                    .clipShape(Circle())
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(rebrandable: "Sync-Start-128", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)

                Text(UserText.simplifiedDeviceAddedV2Title(model.thisDeviceName ?? UserText.simplifiedDeviceAddedV2FallbackDeviceName))
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text(UserText.simplifiedDeviceAddedV2Description)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color(designSystemColor: .background))
    }

    private var recoveryCodeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(UserText.simplifiedRecoveryCodeLabel)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    Text(model.recoveryCode)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }
                Spacer()
                Button {
                    model.simplifiedCopyRecoveryCode()
                } label: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.copy)
                        .foregroundColor(Color(designSystemColor: .icons))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(UserText.simplifiedCopyRecoveryCodeButton)
            }

            Button {
                model.saveRecoveryPDF()
            } label: {
                Text(UserText.simplifiedDownloadYourRecoveryCodeButton)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private var autoRestoreSection: some View {
        Section(footer: Text(UserText.autoRestoreScreenDescription)) {
            Toggle(UserText.autoRestoreSettingsRowLabel, isOn: autoRestoreBinding)
                .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accentPrimary)))
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .disabled(model.isAutoRestoreUpdating)
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }
}

#if DEBUG

private extension SyncSettingsViewModel {
    static func deviceAddedPreview(isAutoRestoreAvailable: Bool = true) -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: isAutoRestoreAvailable ? SyncAutoRestorePreviewProvider.enabled : SyncAutoRestorePreviewProvider.disabled
        )
        model.isSyncEnabled = true
        model.devices = [.init(id: "1", name: "iPhone 15 Pro", type: "phone", isThisDevice: true)]
        model.recoveryCode = "y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9"
        return model
    }
}

#Preview("Device Added") {
    RebrandedPreview(isRebranded: true) {
        SyncDeviceAddedViewV2(model: .deviceAddedPreview())
    }
}

#Preview("Device Added – No Auto-Restore") {
    RebrandedPreview(isRebranded: true) {
        SyncDeviceAddedViewV2(model: .deviceAddedPreview(isAutoRestoreAvailable: false))
    }
}

#endif
