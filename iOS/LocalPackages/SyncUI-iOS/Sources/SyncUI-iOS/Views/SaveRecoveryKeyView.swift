//
//  SaveRecoveryKeyView.swift
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

public struct SaveRecoveryKeyView: View {

    @Environment(\.presentationMode) var presentation
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var isCopied = false

    var isCompact: Bool {
        verticalSizeClass == .compact
    }

    @ObservedObject var model: SaveRecoveryKeyViewModel

    public init(model: SaveRecoveryKeyViewModel) {
        self.model = model
    }

    @ViewBuilder
    func recoveryInfo() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 0) {
                Image("Sync-QR-24")
                    .accessibilityHidden(true)
                    .padding(.leading, 16)
                    .padding(.trailing, 8)

                VStack(alignment: .leading, spacing: 0) {
                    Text(UserText.saveRecoveryCodeCardTitle)
                        .daxBodyRegular()
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .padding(.bottom, 2)

                    Text(model.key)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .monospaceSystemFont(ofSize: 16)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                }

                Button(action: copyRecoveryCode) {
                    Image("Sync-Copy-24")
                }
                .padding(.leading, 12)
                .padding(.trailing, 16)
                .buttonStyle(.plain)
                .accessibilityLabel(UserText.saveRecoveryCodeCopyCodeButton)
            }
            .padding(.top, 11)

            Divider()
                .padding(.leading, 48)

            Button(UserText.saveRecoveryCodeSaveAsPdfButton) {
                model.showRecoveryPDFAction()
            }
            .padding(.leading, 48)
            .padding(.bottom, 16)
            .buttonStyle(.plain)
            .foregroundColor(Color(designSystemColor: .accent))
            .daxBodyRegular()
        }
        .background(RoundedRectangle(cornerRadius: 12).foregroundColor(Color(designSystemColor: .backgroundTertiary)))
    }

    func copyRecoveryCode() {
        model.copyKey()
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    @ViewBuilder
    func nextButton() -> some View {
        Button {
            presentation.wrappedValue.dismiss()
            model.nextButtonPressed()
        } label: {
            Text(UserText.nextButton)
        }
        .buttonStyle(PrimaryButtonStyle())
        .overlay(
            isCopied ?
            codeCopiedToast()
            : nil
        )
        .frame(maxWidth: 360)
        .padding(.horizontal, 30)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    func mainContent() -> some View {
        VStack(spacing: 0) {
            Image("Sync-QR-Download-128")
                .padding(.bottom, 16)

            Text(UserText.saveRecoveryCodeSheetTitle)
                .daxTitle1()
                .padding(.bottom, 24)

            Text(UserText.saveRecoveryCodeSheetDescription)
                .lineLimit(nil)
                .daxBodyRegular()
                .lineSpacing(1.32)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            recoveryInfo()
                .padding(.bottom, 16)
            if model.isAutoRestoreFeatureEnabled {
                autoRestoreSection()
            } else {
                Text(UserText.saveRecoveryCodeSheetFooter)
                    .daxCaption()
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, isCompact ? 0 : 56)
        .padding(.horizontal, 20)
        .foregroundStyle(Color(designSystemColor: .textPrimary))
    }

    @ViewBuilder
    func autoRestoreSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.isAutoRestoreEnabled },
                set: { model.autoRestoreToggled($0) }
            )) {
                Text(UserText.autoRestoreToggleLabel)
                    .daxBodyRegular()
            }
            .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accent)))
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 12).foregroundColor(Color(designSystemColor: .backgroundTertiary)))

            Text(UserText.autoRestoreFooter)
                .daxCaption1()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func codeCopiedToast() -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black)
                .frame(height: 45)
            Text(UserText.saveRecoveryCodeSaveCodeCopiedToast)
                .foregroundColor(.white)
                .padding()

        }
        .padding(.bottom, 50)
    }


    public var body: some View {
        UnderflowContainer {
            mainContent()
        } foregroundContent: {
            nextButton()
        }
        .onAppear {
            model.autoRestoreViewShown()
        }
        .background(Color(designSystemColor: .backgroundSheets))
    }

}
