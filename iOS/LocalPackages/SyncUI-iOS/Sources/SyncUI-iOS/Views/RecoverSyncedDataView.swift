//
//  RecoverSyncedDataView.swift
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

import SwiftUI
import DuckUI
import DesignResourcesKit
import DesignResourcesKitIcons

public struct RecoverSyncedDataView: View {

    @ObservedObject public var model: SyncSettingsViewModel
    var onCancel: () -> Void

    @State private var bottomSafeArea: CGFloat = 0

    public init(model: SyncSettingsViewModel, onCancel: @escaping () -> Void) {
        self.model = model
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationView {
            UnderflowContainer {
                VStack(spacing: 0) {
                    SyncUIImages.recover
                        .padding(20)

                    Text(UserText.recoverSyncedDataTitle)
                        .daxTitle1()
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)

                    Text(UserText.recoverSyncedDataDescription)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            } foregroundContent: {
                Button {
                    model.delegate?.fireSyncSetupPixel(event: .recoveryConfirmedTapped)
                    model.continueRecoverFlow()
                } label: {
                    Text(UserText.recoverSyncedDataButton)
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 360)
                .padding(.horizontal, 30)
                .padding(.bottom, max(24 - bottomSafeArea, 0))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onCancel) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    }
                    .accessibilityLabel(UserText.simplifiedScanCloseButton)
                }
            }
        }
        .onAppear {
            model.autoRestoreManualRecoveryShown()
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { bottomSafeArea = geometry.safeAreaInsets.bottom }
            }
        )
        .background(Color(designSystemColor: .backgroundSheets))
    }
}

#if DEBUG
#Preview {
    let model = SyncSettingsViewModel(
        isOnDevEnvironment: { false },
        switchToProdEnvironment: {},
        autoRestoreProvider: SyncAutoRestorePreviewProvider.disabled
    )

    return RebrandedPreview(isRebranded: true) {
        RecoverSyncedDataView(model: model, onCancel: {})
    }
}
#endif
