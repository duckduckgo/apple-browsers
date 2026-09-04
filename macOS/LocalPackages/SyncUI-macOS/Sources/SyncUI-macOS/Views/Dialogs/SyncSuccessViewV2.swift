//
//  SyncSuccessViewV2.swift
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
import SwiftUI
import SwiftUIExtensions

struct SyncSuccessViewV2: View {

    @EnvironmentObject private var model: ManagementDialogModel

    let code: String

    private var title: String {
        UserText.syncSuccessTitleV2(
            deviceName: model.thisDeviceName ?? UserText.syncSuccessFallbackDeviceNameV2
        )
    }

    var body: some View {
        SyncDialogV2(spacing: 20) {
            VStack(spacing: 20) {
                Image(.syncSetupSuccess)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 72)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("SyncSuccessTitle")

                Text(UserText.syncSuccessDescriptionV2)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                recoveryCodeCard
            }
        } buttons: {
            Spacer()
            Button(UserText.done) {
                model.endFlow()
            }
            .buttonStyle(DismissActionButtonStyle(showsBorder: true, stateColors: .themedDismissButton))
            .accessibilityIdentifier("SyncSuccessDoneButton")
        }
    }

    private var recoveryCodeCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(.qrDownloadHero)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(UserText.syncSuccessRecoveryCodeLabelV2)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))

                Text(code)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .padding(.top, 2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("SyncSuccessRecoveryCode")

                HStack(spacing: 8) {
                    Button {
                        model.delegate?.copyCode(code)
                    } label: {
                        Text(UserText.syncSuccessCopyCodeButtonV2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(DismissActionButtonStyle(pillShape: true, showsBorder: true))
                    .accessibilityIdentifier("SyncSuccessCopyCodeButton")

                    Button {
                        model.delegate?.saveRecoveryPDF()
                    } label: {
                        Text(UserText.syncSuccessDownloadPDFButtonV2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                    }
                    .buttonStyle(DismissActionButtonStyle(pillShape: true, showsBorder: true))
                    .accessibilityIdentifier("SyncSuccessDownloadPDFButton")
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(designSystemColor: .containerFillSecondary))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(designSystemColor: .containerBorderPrimary), lineWidth: 1)
                }
        }
    }
}

#if DEBUG
#Preview("Device Added") {
    DesignSystemRebrand.isAppRebranded = { true }
    let model = ManagementDialogModel()
    model.thisDeviceName = "Dax’s MacBook Pro"
    return SyncSuccessViewV2(code: "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ")
        .environmentObject(model)
}
#endif
