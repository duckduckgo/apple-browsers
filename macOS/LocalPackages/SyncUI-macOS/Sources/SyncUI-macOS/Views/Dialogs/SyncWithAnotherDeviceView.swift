//
//  SyncWithAnotherDeviceView.swift
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
import SwiftUIExtensions

struct SyncWithAnotherDeviceView: View {

    @EnvironmentObject var model: ManagementDialogModel
    @EnvironmentObject var recoveryCodeModel: RecoveryCodeViewModel
    let codeForDisplayOrPasting: String
    let stringForQRCode: String

    @State private var selectedSegment = 0
    @State private var showQRCode = true

    var body: some View {
        SyncDialog(spacing: 20.0) {
            VStack(spacing: 8.0) {
                Image(.sync96)
                SyncUIViews.TextHeader(text: UserText.syncWithAnotherDeviceTitle)
            }
            if #available(macOS 12.0, *) {
                Text(syncWithAnotherDeviceInstruction)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            } else {
                Text(UserText.syncWithAnotherDeviceSubtitle(syncMenuPath: UserText.syncWithAnotherDevicePath))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }

            pickerView()

            VStack(spacing: 20) {
                if selectedSegment == 0 {
                    if showQRCode {
                        scanQRCodeView()
                    } else {
                        showTextCodeView()
                    }
                } else {
                    enterCodeView().onAppear {
                        model.delegate?.enterCodeViewDidAppear()
                    }
                }
            }
            .padding(16)
            .frame(height: 332)
            .frame(minWidth: 380)
            .roundedBorder()

        }
    buttons: {
        Button(UserText.cancel) {
            model.cancelPressed()
        }
    }
    .frame(width: 420)
    }

    @available(macOS 12, *)
    private var syncWithAnotherDeviceInstruction: AttributedString {
        let baseString = UserText.syncWithAnotherDeviceSubtitle(syncMenuPath: UserText.syncWithAnotherDevicePath)
        var instructions = AttributedString(baseString)
        if let range = instructions.range(of: UserText.syncWithAnotherDevicePath) {
            instructions[range].foregroundColor = .primary
        }
        return instructions
    }

    fileprivate func pickerView() -> some View {
        return HStack(spacing: 0) {
            pickerOptionView(imageName: "QR-Icon", title: UserText.syncWithAnotherDeviceShowQRCodeButton, tag: 0)
            pickerOptionView(imageName: "Keyboard-16D", title: UserText.syncWithAnotherDeviceEnterCodeButton, tag: 1)
        }
        .padding(4)
        .frame(height: 32)
        .frame(minWidth: 348)
        .roundedBorder()
    }

    @ViewBuilder
    fileprivate func pickerOptionView(imageName: String, title: String, tag: Int) -> some View {
        Button {
            selectedSegment = tag
        } label: {
            HStack {
                Image(imageName)
                Text(title)
            }
            .frame(height: 28)
            .frame(minWidth: 172)
            .padding(.horizontal, 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedSegment == tag ? Color(.blackWhite10) : .clear, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedSegment == tag ? Color(.pickerViewSelected) : Color(.blackWhite1))
                }
            )
        }
        .buttonStyle(.plain)
    }

    fileprivate func scanQRCodeView() -> some View {
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(UserText.syncWithAnotherDeviceShowQRCodeExplanationPrefix)
                HStack(alignment: .center, spacing: 10) {
                    Text(UserText.syncWithAnotherDeviceShowQRCodeExplanationApp)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Image(.duckDuckGo24)
                        .resizable()
                        .frame(width: 24, height: 24)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.blackWhite5))
                .cornerRadius(8)
            }
            .padding(.top, 8)
            Spacer()
            QRCode(string: stringForQRCode, desiredSize: 180)
            Spacer()
            Text(UserText.syncWithAnotherDeviceUseTextCode)
                .fontWeight(.semibold)
                .foregroundColor(Color(.linkBlue))
                .onTapGesture {
                    showQRCode = false
                }
        }
    }

    fileprivate func enterCodeView() -> some View {
        Group {
            Text(UserText.syncWithAnotherDeviceEnterCodeExplanation)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button {
                recoveryCodeModel.paste()
                model.delegate?.recoveryCodePasted(recoveryCodeModel.recoveryCode, fromRecoveryScreen: false)
            } label: {
                HStack {
                    Image(.paste)
                    Text(UserText.paste)
                }
            }
            .buttonStyle(CopyPasteButtonStyle(verticalPadding: 8.0))
            .keyboardShortcut(KeyEquivalent("v"), modifiers: .command)
        }
    }

    fileprivate func showTextCodeView() -> some View {
        Group {
            VStack(spacing: 0) {
                Text(UserText.syncWithAnotherDeviceShowCodeToPasteExplanation)
                Spacer()
                Text(codeForDisplayOrPasting)
                    .font(
                    Font.custom("SF Mono", size: 13)
                    .weight(.medium)
                    )
                    .kerning(2)
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 20)
                HStack(spacing: 10) {
                    Button {
                        shareContent(codeForDisplayOrPasting)
                    } label: {
                        HStack {
                            Image(.share)
                            Text(UserText.share)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                    Button {
                        model.delegate?.copyCode()
                    } label: {
                        HStack {
                            Image(.copy)
                            Text(UserText.copy)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                    }
                }
                .frame(width: 348, height: 32)
                Spacer()
                Text(UserText.syncWithAnotherDeviceUseQRCode)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(.linkBlue))
                    .onTapGesture {
                        showQRCode = true
                    }
            }
            .padding(.top, 8)
        }
        .frame(width: 348)
    }

    private func shareContent(_ sharedText: String) {
        guard let contentView = NSApp.keyWindow?.contentView else {
            return
        }
        let sharingPicker = NSSharingServicePicker(items: [sharedText])

        sharingPicker.show(relativeTo: contentView.frame, of: contentView, preferredEdge: .maxY)
    }
}
