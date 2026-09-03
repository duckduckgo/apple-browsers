//
//  SyncWithAnotherDeviceViewV2.swift
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

import AppKit
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons
#if DEBUG
import PreviewSnapshots
#endif

struct SyncWithAnotherDeviceViewV2: View {

    @EnvironmentObject private var model: ManagementDialogModel
    @EnvironmentObject private var recoveryCodeModel: RecoveryCodeViewModel

    private let codeForDisplayOrPasting: String
    private let stringForQRCode: String

    @State private var selectedTab: PairingTabV2
    @State private var showCopyConfirmation = false

    init(codeForDisplayOrPasting: String, stringForQRCode: String) {
        self.init(
            codeForDisplayOrPasting: codeForDisplayOrPasting,
            stringForQRCode: stringForQRCode,
            initialTab: .scanCode
        )
    }

    fileprivate init(
        codeForDisplayOrPasting: String,
        stringForQRCode: String,
        initialTab: PairingTabV2
    ) {
        self.codeForDisplayOrPasting = codeForDisplayOrPasting
        self.stringForQRCode = stringForQRCode
        _selectedTab = State(initialValue: initialTab)
    }

    private var title: String {
        switch selectedTab {
        case .scanCode:
            UserText.syncWithAnotherDeviceScanTitleV2
        case .enterCode:
            UserText.syncWithAnotherDeviceEnterTitleV2
        }
    }

    private var optionsPanelHeight: CGFloat {
        switch selectedTab {
        case .scanCode:
            Metrics.scanOptionsPanelHeight
        case .enterCode:
            Metrics.enterOptionsPanelHeight
        }
    }

    var body: some View {
        SyncDialogV2(spacing: .zero) {
            VStack(spacing: 20) {
                headerArtwork
                SyncUIViews.TextHeader(text: title)
                optionsPanel
            }
            .padding(.bottom, 16)
        } buttons: {
            Spacer()
            Button(UserText.cancel) {
                model.cancelPressed()
            }
            .buttonStyle(DismissActionButtonStyle())
        }
        .onChange(of: selectedTab) { _ in
            showCopyConfirmation = false
        }
    }

    @ViewBuilder
    private var headerArtwork: some View {
        switch selectedTab {
        case .scanCode:
            Image(.syncPairFeature128)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 72)
                .accessibilityHidden(true)
        case .enterCode:
            Image(.clipboardQRFeature128)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 72)
                .accessibilityHidden(true)
        }
    }

    private var optionsPanel: some View {
        VStack(spacing: 20) {
            tabPicker

            instructions

            switch selectedTab {
            case .scanCode:
                scanCodeCard
            case .enterCode:
                enterCodeCard
                    .onAppear {
                        model.delegate?.enterCodeViewDidAppear()
                    }
            }
        }
        .padding(20)
        .frame(width: 380, height: optionsPanelHeight)
        .syncRoundedBorder(cornerRadius: 24)
    }

    private var tabPicker: some View {
        HStack(spacing: .zero) {
            tabButton(.scanCode, title: UserText.syncWithAnotherDeviceScanTabV2)
            tabButton(.enterCode, title: UserText.syncWithAnotherDeviceEnterTabV2)
        }
        .padding(1)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background {
            Capsule()
                .fill(Color(designSystemColor: .containerFillTertiary))
        }
        .overlay {
            Capsule()
                .stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1)
        }
    }

    private func tabButton(_ tab: PairingTabV2, title: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(title)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Capsule()
                        .fill(selectedTab == tab
                              ? Color(designSystemColor: .controlsRaisedFillPrimary)
                              : .clear)
                }
                .overlay {
                    Capsule()
                        .stroke(selectedTab == tab
                                ? Color(designSystemColor: .surfaceDecorationPrimary)
                                : .clear,
                                lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch selectedTab {
            case .scanCode:
                InstructionStepV2(
                    number: 1,
                    prefix: UserText.syncWithAnotherDeviceScanStep1PrefixV2,
                    detail: UserText.syncWithAnotherDeviceScanStep1DetailV2,
                    showsAppIcon: true
                )
            case .enterCode:
                InstructionStepV2(
                    number: 1,
                    prefix: UserText.syncWithAnotherDeviceEnterStep1PrefixV2,
                    detail: UserText.syncWithAnotherDeviceEnterStep1DetailV2,
                    showsAppIcon: true
                )
            }

            InstructionStepV2(
                number: 2,
                prefix: UserText.syncWithAnotherDeviceStep2PrefixV2,
                detail: UserText.syncWithAnotherDeviceStep2DetailV2
            )

            InstructionStepV2(
                number: 3,
                prefix: selectedTab == .scanCode
                    ? UserText.syncWithAnotherDeviceScanStep3V2
                    : UserText.syncWithAnotherDeviceEnterStep3V2
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanCodeCard: some View {
        VStack(spacing: 0) {
            QRCode(string: stringForQRCode, desiredSize: 180)

            Text(codeForDisplay)
                .font(.system(size: 10, design: .monospaced))
                .kerning(1.5)
                .foregroundColor(Color(designSystemColor: .textTertiary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(width: 220)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 4) {
                Button {
                    shareContent(codeForDisplayOrPasting)
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size16.shareApple)
                        Text(UserText.share)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(DismissActionButtonStyle(showsBorder: false,
                                                      stateColors: .themedDismissButton))

                Button {
                    model.delegate?.copyCode(codeForDisplayOrPasting)
                    showCopyConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(nsImage: showCopyConfirmation
                              ? DesignSystemImages.Glyphs.Size16.check
                              : DesignSystemImages.Glyphs.Size16.copy)
                        Text(showCopyConfirmation ? UserText.syncWithAnotherDeviceCopiedV2 : UserText.copy)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(DismissActionButtonStyle(showsBorder: false,
                                                      stateColors: .themedDismissButton))
                .popover(isPresented: $showCopyConfirmation, arrowEdge: .bottom) {
                    copyConfirmation
                }
            }
            .padding(.top, 10)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(innerCardBackground)
        .environment(\.colorScheme, .light)
    }

    private var enterCodeCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(UserText.syncWithAnotherDeviceExampleCodeV2)
                    .font(.system(size: 10, design: .monospaced))
                    .kerning(-0.08)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                Text(verbatim: Metrics.exampleCode)
                    .font(.system(size: 10, design: .monospaced))
                    .kerning(-0.08)
                    .foregroundColor(Color(designSystemColor: .textTertiary))
            }
            .lineLimit(1)

            Button {
                recoveryCodeModel.paste()
                model.delegate?.recoveryCodePasted(recoveryCodeModel.recoveryCode, fromRecoveryScreen: false)
            } label: {
                HStack(spacing: 6) {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.paste)
                    Text(UserText.syncWithAnotherDevicePasteCodeV2)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
            }
            .buttonStyle(DismissActionButtonStyle())
            .keyboardShortcut(KeyEquivalent("v"), modifiers: .command)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(enterCodeCardBackground)
    }

    private var innerCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(designSystemColor: .surfaceTertiary))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1)
            }
    }

    private var enterCodeCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(designSystemColor: .containerFillSecondary))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(designSystemColor: .containerBorderPrimary), lineWidth: 1)
            }
    }

    private var copyConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UserText.syncWithAnotherDeviceCopyConfirmationTitleV2)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(designSystemColor: .textPrimary))
            Text(UserText.syncWithAnotherDeviceCopyConfirmationMessageV2)
                .font(.system(size: 13))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.leading)
        .frame(width: 240, alignment: .leading)
        .padding(16)
    }

    private func shareContent(_ sharedText: String) {
        guard let contentView = NSApp.keyWindow?.contentView else {
            return
        }

        let sharingPicker = NSSharingServicePicker(items: [sharedText])
        sharingPicker.show(relativeTo: contentView.frame, of: contentView, preferredEdge: .maxY)
    }

    private var codeForDisplay: String {
        guard let url = URL(string: codeForDisplayOrPasting),
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
              let pairingCode = fragment
                .split(separator: "&")
                .first(where: { $0.hasPrefix("code2=") })?
                .split(separator: "=", maxSplits: 1)
                .last else {
            return codeForDisplayOrPasting
        }

        return String(pairingCode).removingPercentEncoding ?? String(pairingCode)
    }
}

private struct InstructionStepV2: View {
    let number: Int
    let prefix: String
    var detail: String?
    var showsAppIcon: Bool = false

    private var text: Text {
        let prefix = Text(prefix)
            .foregroundColor(Color(designSystemColor: .textSecondary))

        guard let detail else {
            return prefix
        }

        return prefix
            + Text(verbatim: " ")
            + Text(detail)
                .foregroundColor(Color(designSystemColor: .textPrimary))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color(designSystemColor: .toneTintSecondary))
                    .frame(width: 16, height: 16)
                Text(verbatim: "\(number)")
                    .font(.system(size: 8.75, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .accentAltTextPrimary))
            }
            .frame(width: 16, height: 16)
            .frame(width: 24, alignment: .leading)

            HStack(alignment: .center, spacing: 4) {
                text
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)

                if showsAppIcon {
                    Image(nsImage: DesignSystemImages.Color.Size24.appDuckDuckGo)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum PairingTabV2: Hashable {
    case scanCode
    case enterCode
}

private enum Metrics {
    static let scanOptionsPanelHeight: CGFloat = 489
    static let enterOptionsPanelHeight: CGFloat = 393
    static let exampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ"
}

#if DEBUG
struct SyncWithAnotherDeviceViewV2_Previews: PreviewProvider {
    enum State: Equatable {
        case scanCode
        case enterCode
    }

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Scan Code", state: .scanCode),
            .init(name: "Enter Code", state: .enterCode)
        ],
        configure: { state in
            let sampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3IiwicHJpbWFyeV9rZXkiOiJBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWiJ9fQ=="
            let tab: PairingTabV2 = state == .scanCode ? .scanCode : .enterCode

            DesignSystemRebrand.isAppRebranded = { true }
            return SyncWithAnotherDeviceViewV2(
                codeForDisplayOrPasting: sampleCode,
                stringForQRCode: sampleCode,
                initialTab: tab
            )
            .environmentObject(ManagementDialogModel())
            .environmentObject(RecoveryCodeViewModel())
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
    )
}
#endif
