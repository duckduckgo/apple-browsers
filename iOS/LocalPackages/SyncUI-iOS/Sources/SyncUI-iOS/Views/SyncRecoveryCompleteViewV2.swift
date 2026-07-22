//
//  SyncRecoveryCompleteViewV2.swift
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

struct SyncRecoveryCompleteViewV2: View {

    @ObservedObject var model: SyncSettingsViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(rebrandable: "Sync-Start-128", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)
                    .padding(.top, 56)

                Text(UserText.simplifiedRecoveryCompleteV2Title)
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text(UserText.simplifiedRecoveryCompleteV2Description)
                    .daxBodyRegular()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
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
            Button(action: model.recoveryCompleteDoneFromConnectingSheet) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.check)
            }
            .buttonStyle(.glassProminent)
            .tint(Color(designSystemColor: .accentPrimary))
        } else {
            Button(action: model.recoveryCompleteDoneFromConnectingSheet) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.check)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(designSystemColor: .accentPrimary))
                    .clipShape(Circle())
            }
        }
    }
}

#if DEBUG

private extension SyncSettingsViewModel {
    static func recoveryCompletePreview() -> SyncSettingsViewModel {
        let model = SyncSettingsViewModel(
            isOnDevEnvironment: { false },
            switchToProdEnvironment: {},
            autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
        )
        model.isSyncEnabled = true
        model.devices = [.init(id: "1", name: "iPhone 15 Pro", type: "phone", isThisDevice: true)]
        model.recoveryCode = "y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9y2cJyqsW3FPSJ9"
        return model
    }
}

#Preview("Recovery Complete") {
    RebrandedPreview(isRebranded: true) {
        SyncRecoveryCompleteViewV2(model: .recoveryCompletePreview())
    }
}

#Preview("Recovery Complete – Dark") {
    RebrandedPreview(isRebranded: true) {
        SyncRecoveryCompleteViewV2(model: .recoveryCompletePreview())
    }
    .preferredColorScheme(.dark)
}

#endif
