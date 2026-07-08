//
//  ScanQRCodeViewV2.swift
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
import UIComponents

public struct ScanQRCodeViewV2: View {

    enum Tab {
        case scanQRCode
        case viewCode
    }

    @ObservedObject var model: ScanOrPasteCodeViewModel
    @State private var qrCodeModel: ShowQRCodeViewModel
    @State private var selectedTab: Tab = .scanQRCode
    @State private var showCopyConfirmation = false

    public init(model: ScanOrPasteCodeViewModel) {
        self.model = model
        self.qrCodeModel = model.showQRCodeModel
    }

    public var body: some View {
        VStack(spacing: 16) {
            segmentedControl
                .padding(.top, 8)

            contentPanel
        }
        .background(SimplifiedSyncStyle.screenBackground)
        .onChange(of: selectedTab) { _ in
            showCopyConfirmation = false
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(UserText.cancelButton, action: model.cancel)
                    .foregroundColor(.white)
            }
            ToolbarItem(placement: .principal) {
                Text(UserText.simplifiedScanTitle)
                    .daxHeadline()
                    .foregroundColor(.white)
            }
        }
        .modifier {
            if #available(iOS 16.0, *) {
                $0.toolbarBackground(.hidden, for: .navigationBar)
            } else {
                $0
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var segmentedControl: some View {
        Picker("", selection: $selectedTab) {
            Text(UserText.simplifiedScanTabScanQRCode).tag(Tab.scanQRCode)
                .padding(.horizontal, 4)
            Text(UserText.simplifiedScanTabViewCode).tag(Tab.viewCode)
                .padding(.horizontal, 4)
        }
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var contentPanel: some View {
        ZStack {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(baseColor: .gray85))
            }
            .ignoresSafeArea(edges: .bottom)

            switch selectedTab {
            case .scanQRCode:
                ScanTabView(model: model)
            case .viewCode:
                ViewCodeTabView(model: model, qrCodeModel: qrCodeModel, showCopyConfirmation: $showCopyConfirmation)
            }
        }
    }
}

private struct ScanTabView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel

    var body: some View {
        VStack(spacing: 24) {
            instructions
                .padding(.top, 24)

            cameraContainer
                .layoutPriority(1)

            manuallyEnterCodeButton
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
    }

    private var instructions: some View {
        Text("\(UserText.simplifiedScanInstructions)\n\(UserText.simplifiedScanInstructionsLine2)")
            .daxSubheadRegular()
            .foregroundColor(SimplifiedSyncStyle.instructionText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
    }

    private var cameraContainer: some View {
        ZStack(alignment: .bottom) {
            Group {
                if model.videoPermission == .denied {
                    CameraPermissionDeniedView(model: model)
                } else if model.videoPermission == .authorised && !model.showCamera {
                    CameraUnavailableView()
                } else if model.showCamera {
                    QRCodeScannerView {
                        return await model.codeScanned($0)
                    } onCameraUnavailable: {
                        model.cameraUnavailable()
                    }
                } else {
                    Color.black
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if model.showCamera && model.videoPermission != .denied {
                cameraPromptPill
                    .padding(.bottom, 16)
            }
        }
    }

    private var cameraPromptPill: some View {
        Text(UserText.simplifiedScanCameraPrompt)
            .daxSubheadSemibold()
            .foregroundColor(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 20)
            .background(
                Capsule()
                    .fill(.clear)
                    .background(
                        BlurView(style: .light)
                            .clipShape(Capsule())
                    )
            )
    }

    private var manuallyEnterCodeButton: some View {
        NavigationLink {
            SimplifiedManuallyEnterCodeView(model: model)
        } label: {
            Label {
                Text(UserText.simplifiedScanManuallyEnterCode)
                    .daxSubheadSemibold()
            } icon: {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.keyboard)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(designSystemColor: .controlsFillPrimary))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CameraPermissionDeniedView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(rebrandable: "SyncCameraPermission")
                .padding(.bottom, 20)

            Text(UserText.cameraPermissionRequired)
                .daxTitle3()
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(UserText.cameraPermissionInstructions)
                .daxSubheadRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                model.gotoSettings()
            } label: {
                HStack {
                    Image("SyncGotoButton")
                    Text(UserText.cameraGoToSettingsButton)
                }
            }
            .buttonStyle(SyncLabelButtonStyle())
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct CameraUnavailableView: View {

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(rebrandable: "SyncCameraUnavailable")
                .padding(.bottom, 20)

            Text(UserText.cameraIsUnavailableTitle)
                .daxTitle3()
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct ViewCodeTabView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel
    let qrCodeModel: ShowQRCodeViewModel
    @Binding var showCopyConfirmation: Bool

    var body: some View {
        VStack(spacing: 24) {
            instructionsWithAppChip
                .padding(.top, 24)

            qrCodeContainer

            shareButtons
                .padding(.bottom, Metrics.shareButtonsBottomPadding)
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .overlay(alignment: .bottomLeading) {
            if showCopyConfirmation {
                copyConfirmationCallout
                    .padding(.horizontal, Metrics.copyConfirmationHorizontalPadding)
                    .padding(.bottom, Metrics.shareButtonsBottomPadding + Metrics.copyButtonSize + Metrics.copyConfirmationSpacing)
                    .zIndex(1)
            }
        }
    }

    private var instructionsWithAppChip: some View {
        VStack(spacing: 8) {
            Text(UserText.simplifiedViewCodeInstructions)
                .daxSubheadRegular()
                .foregroundColor(SimplifiedSyncStyle.instructionText)
                .multilineTextAlignment(.center)

            appNameChip
        }
        .frame(minHeight: 72)
    }

    private var appNameChip: some View {
        HStack(spacing: 6) {
            Text(UserText.simplifiedViewCodeAppName)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)

            Image(uiImage: DesignSystemImages.Color.Size24.appDuckDuckGo)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundColor(.white)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SimplifiedSyncStyle.screenBackground)
        )
    }

    private var qrCodeContainer: some View {
        VStack(spacing: 16) {
            QRCodeView(string: qrCodeModel.qrCodeString, desiredSize: 240, backgroundColor: SimplifiedSyncStyle.qrCodeBackground, flexible: true)
                .padding(.top, 24)

            Text(qrCodeModel.codeForDisplayOrPasting)
                .font(.system(size: 16, design: .monospaced))
                .tracking(2)
                .lineSpacing(8)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .padding(.horizontal, 46)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(SimplifiedSyncStyle.qrCodeBackground)
        )
        .environment(\.colorScheme, .light)
    }

    private var shareButtons: some View {
        HStack(spacing: 12) {
            Button {
                model.copyCode()
                showCopyConfirmation = true
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.copy)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(designSystemColor: .controlsFillPrimary))
                    )
            }
            .buttonStyle(.plain)

            Button {
                model.showShareCodeSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(uiImage: DesignSystemImages.Glyphs.Size16.shareApple)

                    Text(UserText.simplifiedViewCodeShareButton)
                        .daxSubheadSemibold()
                }
                .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(SimplifiedSyncStyle.primaryActionBackground)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.copyConfirmationHorizontalPadding)
    }

    private var copyConfirmationCallout: some View {
        BubbleView(
            arrowLength: Metrics.copyConfirmationArrowLength,
            arrowWidth: Metrics.copyConfirmationArrowWidth,
            arrowEdge: .bottom,
            arrowOffset: 0,
            cornerRadius: Metrics.copyConfirmationCornerRadius,
            fillColor: Color(designSystemColor: .surface),
            contentPadding: EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20)
        ) {
            copyConfirmationContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .environment(\.colorScheme, .light)
    }

    private var copyConfirmationContent: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading) {
                Text(UserText.simplifiedViewCodeCopyConfirmationTitle)
                    .daxSubheadSemibold()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                Text(UserText.simplifiedViewCodeCopyConfirmationMessage)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                showCopyConfirmation = false
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
            }
            .buttonStyle(CloseButtonStyle())
        }
    }

    private enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let copyButtonSize: CGFloat = 40
        static let shareButtonsBottomPadding: CGFloat = 16
        static let copyConfirmationSpacing: CGFloat = 8
        static let copyConfirmationArrowLength: CGFloat = 10
        static let copyConfirmationArrowWidth: CGFloat = 14
        static let copyConfirmationCornerRadius: CGFloat = 27
        static let copyConfirmationHorizontalPadding: CGFloat = 12
    }
}

private struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

#if DEBUG
#Preview {
    let sampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3IiwicHJpbWFyeV9rZXkiOiJBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWiJ9fQ=="

    return NavigationView {
        ScanQRCodeViewV2(
            model: ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
        )
        .colorScheme(.dark)
    }
}
#endif
