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
            VStack(spacing: 20.0) {
                Image(.sync96)
                SyncUIViews.TextHeader(text: UserText.syncWithAnotherDeviceTitle)
            }

            VStack(alignment: .leading, spacing: 10) {
                instructionStepView(number: 1, markdown: UserText.syncWithAnotherDeviceStep1, showAppIcon: true)
                instructionStepView(number: 2, markdown: UserText.syncWithAnotherDeviceStep2)
            }
            .frame(minWidth: Metrics.contentMinWidth, alignment: .leading)
            .padding(.leading, 4)
            .padding(.bottom, 10)

            VStack(spacing: 20) {
                pickerView()

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
            .frame(minWidth: Metrics.contentMinWidth)
            .roundedBorder()

            singleDeviceSyncPromo()
        }
        buttons: {
            Button(UserText.cancel) {
                model.cancelPressed()
            }
        }
        .frame(width: 420)
    }

    fileprivate func pickerView() -> some View {
        return HStack(spacing: 0) {
            pickerOptionView(imageName: "QR-Icon", title: UserText.syncWithAnotherDeviceScanThisQRCodeButton, tag: 0)
            pickerOptionView(imageName: "Keyboard-16D", title: UserText.syncWithAnotherDeviceEnterCodeButton, tag: 1)
        }
        .padding(2)
        .frame(height: 32)
        .frame(minWidth: 348)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.pickerOuterRadius)
                    .stroke(Color(.blackWhite10), lineWidth: 1)
                RoundedRectangle(cornerRadius: Metrics.pickerOuterRadius)
                    .fill(Color.black.opacity(0.09))
            }
        )
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
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.pickerInnerRadius)
                        .stroke(selectedSegment == tag ? Color(.blackWhite10) : .clear, lineWidth: 1)
                    RoundedRectangle(cornerRadius: Metrics.pickerInnerRadius)
                        .fill(selectedSegment == tag ? Color(.pickerViewSelected) : .clear)
                }
            )
        }
        .buttonStyle(.plain)
    }

    fileprivate func scanQRCodeView() -> some View {
        return VStack(spacing: 0) {
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

    @ViewBuilder
    fileprivate func instructionStepView(number: Int, markdown: String, showAppIcon: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 14) {
            NumberBadge(number: number)

            if #available(macOS 12.0, *) {
                HStack(spacing: 4) {
                    Text(parseBoldMarkdown(markdown))
                        .fixedSize(horizontal: false, vertical: true)
                    if showAppIcon {
                        Image(.duckDuckGo24)
                            .resizable()
                            .frame(width: Metrics.appIconSize, height: Metrics.appIconSize)
                    }
                }
            } else {
                fallbackInstructionStepText(markdown, showAppIcon: showAppIcon)
            }
        }
    }

    /// Fallback view for macOS 11.
    ///
    fileprivate func fallbackInstructionStepText(_ markdown: String, showAppIcon: Bool) -> some View {
        HStack(spacing: 4) {
            Text(markdown.replacingOccurrences(of: "**", with: ""))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showAppIcon {
                Image(.duckDuckGo24)
                    .resizable()
                    .frame(width: Metrics.appIconSize, height: Metrics.appIconSize)
            }
        }
    }

    /// Parses bold markdown text and replaces bold styling with primary color.
    ///
    @available(macOS 12.0, *)
    fileprivate func parseBoldMarkdown(_ string: String) -> AttributedString {
        guard var result = try? AttributedString(markdown: string) else {
            var plain = AttributedString(string.replacingOccurrences(of: "**", with: ""))
            plain.foregroundColor = .secondary
            return plain
        }
        for run in result.runs {
            let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
            result[run.range].foregroundColor = isBold ? .primary : .secondary
            result[run.range].inlinePresentationIntent = nil
        }
        return result
    }

    fileprivate func singleDeviceSyncPromo() -> some View {
        Button {
            model.delegate?.turnOnSync()
        } label: {
            HStack {
                Text(UserText.syncSingleDeviceSetupAction)
                    .foregroundColor(.primary)
                Spacer()
                Image(.chevronMediumRight16)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .frame(minWidth: Metrics.contentMinWidth)
            .roundedBorder()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func shareContent(_ sharedText: String) {
        guard let contentView = NSApp.keyWindow?.contentView else {
            return
        }
        let sharingPicker = NSSharingServicePicker(items: [sharedText])

        sharingPicker.show(relativeTo: contentView.frame, of: contentView, preferredEdge: .maxY)
    }
}

/// A simple badge with a number inside a circle.
///
private struct NumberBadge: View {
    let number: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.06))
            Text(verbatim: "\(number)")
                .font(.system(size: 8.75, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(width: 16, height: 16)
    }
}

private enum Metrics {
    static let pickerOuterRadius: CGFloat = 8
    static let pickerInnerRadius: CGFloat = 6
    static let appIconSize: CGFloat = 16
    static let contentMinWidth: CGFloat = 380
}
