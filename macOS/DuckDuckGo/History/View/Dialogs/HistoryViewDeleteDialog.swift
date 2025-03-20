//
//  HistoryViewDeleteDialog.swift
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

import SwiftUIExtensions

struct HistoryViewDeleteDialog: ModalView {

    @ObservedObject var model: HistoryViewDeleteDialogModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(.historyBurn)

            VStack(spacing: 12) {
                Text(model.title)
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 15).weight(.semibold))

                Text(.init(model.message))
                    .multilineTextAlignment(.center)
                    .fixMultilineScrollableText()
                    .font(.system(size: 13))

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(UserText.deleteCookiesAndSiteData, isOn: $model.shouldBurn)
                        .font(.system(size: 13))
                        .fixMultilineScrollableText()
                        .toggleStyle(.checkbox)

                    Text(model.dataClearingExplanation)
                        .fixMultilineScrollableText()
                        .foregroundColor(.blackWhite60)
                        .font(.system(size: 11))
                        .padding(.leading, 19)
                }
                .padding(.init(top: 16, leading: 12, bottom: 16, trailing: 12))
                .background(RoundedRectangle(cornerRadius: 8.0).stroke(.blackWhite5))
            }
            .padding(.bottom, 16)

            HStack(spacing: 8) {
                Button {
                    model.cancel()
                    dismiss()
                } label: {
                    Text(UserText.cancel)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(StandardButtonStyle(topPadding: 0, bottomPadding: 0))
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("ClearAllHistoryAndDataAlert.cancelButton")

                Button {
                    model.delete()
                    dismiss()
                } label: {
                    Text(UserText.delete)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(DestructiveActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0))
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("ClearAllHistoryAndDataAlert.clearButton")

            }
        }
        .padding(16)
        .frame(width: 330)
    }
}
