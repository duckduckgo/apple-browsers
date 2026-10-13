//
//  AutoRestoreReadyView.swift
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

import SwiftUI
import DuckUI
import DesignResourcesKit
import DesignResourcesKitIcons

public struct AutoRestoreReadyView: View {

    @ObservedObject public var model: SyncSettingsViewModel
    var onCancel: () -> Void

    public init(
        model: SyncSettingsViewModel,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.onCancel = onCancel
    }

    public var body: some View {
        NavigationView {
            UnderflowContainer {
                VStack(spacing: 0) {
                    Image(rebrandable: "Sync-Pending-128")
                        .padding(20)

                    Text(UserText.autoRestoreReadyTitle)
                        .daxTitle1()
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 12)

                    Text(UserText.autoRestoreReadyDescription)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(designSystemColor: .textPrimary))
                }
                .padding(.horizontal, 20)
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            } foregroundContent: {
                VStack(spacing: 8) {
                    Button {
                        model.startAutoRestore()
                    } label: {
                        Text(UserText.autoRestoreReadyRestoreButton)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 8)

                    Button {
                        model.startAutoRestoreSecondaryAction()
                    } label: {
                        Text(UserText.autoRestoreReadyScanCodeLink)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 8)
                }
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
        .background(Color(designSystemColor: .backgroundSheets))
        .syncPasscodeRequiredAlert(isPresented: $model.shouldShowPasscodeRequiredAlert)
    }
}
