//
//  ScanTabView.swift
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
import Lottie
import SwiftUI
import DuckUI

struct ScanTabView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel
    var isCameraActive = true

    @Binding var showIntroAnimation: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if showIntroAnimation {
                introAnimation
            } else {
                cameraContainer
            }

            instructions
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .ignoresSafeArea(.all, edges: .bottom)
    }

    private var introAnimation: some View {
        ZStack(alignment: .bottom) {
            LottieView {
                try await DotLottieFile.named("SyncScanQRCode", bundle: .module)
            }
            .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
            .animationDidFinish { _ in
                dismissIntroAnimation()
            }
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Button {
                dismissIntroAnimation()
            } label: {
                Text(UserText.simplifiedScanQRReadyButton)
            }
            .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
            .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissIntroAnimation()
        }
        .transition(.opacity)
    }

    private func dismissIntroAnimation() {
        guard showIntroAnimation else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            showIntroAnimation = false
        }
        model.introAnimationCompleted()
    }

    private var cameraContainer: some View {
        ZStack(alignment: .bottom) {
            Group {
                if model.videoPermission == .denied {
                    CameraPermissionDeniedView(model: model)
                } else if model.videoPermission == .authorised && !model.showCamera {
                    CameraUnavailableView()
                } else if model.showCamera && isCameraActive {
                    QRCodeScannerView {
                        return await model.codeScanned($0)
                    } onCameraUnavailable: {
                        model.cameraUnavailable()
                    }
                } else {
                    Color(designSystemColor: .surfaceSecondary)
                }
            }
        }
        .overlay(Color(designSystemColor: .shadowSecondary).opacity(0.7))
    }

    private var instructions: some View {
        VStack(spacing: 16) {
            Text(UserText.simplifiedScanQRHeading)
                .daxTitle2()
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(UserText.simplifiedScanQROpenInstruction)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))

                    SyncAppNameChip(name: UserText.simplifiedScanQRAppName)
                }

                SyncInstructionText(markdown: UserText.simplifiedScanQRStepsInstruction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
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
private func scanTabPreviewModel(
    permission: ScanOrPasteCodeViewModel.VideoPermission,
    showCamera: Bool
) -> ScanOrPasteCodeViewModel {
    let sampleCode = "eyJyZWNvdmVyeSI6eyJ1c2VyX2lkIjoiNjgwRDQ1QjUtNUU2RS00MzQ3LTlDNDQtQjZGQkU4MEZDNEE3IiwicHJpbWFyeV9rZXkiOiJBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWiJ9fQ=="
    let model = ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
    model.videoPermission = permission
    model.showCamera = showCamera
    return model
}

private struct ScanTabPreview: View {
    let model: ScanOrPasteCodeViewModel
    @State var showIntroAnimation = false

    var body: some View {
        RebrandedPreview(isRebranded: true) {
            NavigationView {
                ScanTabView(model: model, showIntroAnimation: $showIntroAnimation)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SimplifiedSyncStyle.screenBackground)
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}

#Preview("Camera") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .authorised, showCamera: true))
}

#Preview("Camera Unavailable") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .authorised, showCamera: false))
}

#Preview("Permission Denied") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .denied, showCamera: false))
}

#Preview("Initializing") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .unknown, showCamera: false))
}

#Preview("Intro Animation") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .authorised, showCamera: true), showIntroAnimation: true)
}
#endif
