//
//  SyncRecoveryAlternativeView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UIKit
import DesignResourcesKit
import DuckUI
import SyncUI_iOS

struct SyncRecoveryAlternativeView: View {
    let onSyncFlowSelected: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onCancel) {
                            Text(UserText.actionCancel)
                        }
                        Spacer()
                    }
                    .frame(height: 56)

                    Image(.syncRecover128)
                        .padding(24)

                    Text(UserText.syncRecoveryAlternativePromptTitle)
                        .daxTitle1()
                        .padding(.bottom, 24)

                    Text(UserText.syncRecoveryAlternativePromptMessage)
                        .font(.callout)
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    + Text(verbatim: " ")
                    + Text(linkAttributedString())

                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .foregroundStyle(Color(designSystemColor: .textPrimary))
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: { onSyncFlowSelected(SyncSettingsViewController.Constants.startSyncFlow) }) {
                    Text(UserText.syncRecoveryAlternativePromptSyncButton)
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: { onSyncFlowSelected(SyncSettingsViewController.Constants.startBackupFlow) }) {
                    Text(UserText.syncRecoveryAlternativePromptBackupButton)
                }
                .buttonStyle(GhostButtonStyle())
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(designSystemColor: .accent),
                                lineWidth: 1)
                        .padding(1)
                )

                Text(UserText.syncRecoveryAlternativePromptFooter)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .multilineTextAlignment(.center)

            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 30)
        }
        .padding(.bottom)
        .background(Color(designSystemColor: .backgroundSheets))
    }

    private func linkAttributedString() -> AttributedString {
        let markdownString = UserText.syncRecoveryAlternativePromptMessageLink

        do {
            var attributedString = try AttributedString(markdown: markdownString)
            attributedString.foregroundColor = Color(designSystemColor: .accent)

            return attributedString
        } catch {
            return ""
        }
    }
}


#Preview {
    SyncRecoveryAlternativeView(onSyncFlowSelected: { _ in }, onCancel: {})
}
