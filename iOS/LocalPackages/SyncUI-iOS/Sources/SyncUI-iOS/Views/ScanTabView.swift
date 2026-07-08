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
import SwiftUI

struct ScanTabView: View {

    @ObservedObject var model: ScanOrPasteCodeViewModel

    var body: some View {
        ZStack(alignment: .top) {
            cameraContainer
            instructions
        }
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .ignoresSafeArea(.all, edges: .bottom)
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

            if model.showCamera && model.videoPermission != .denied {
                cameraPromptPill
                    .padding(.bottom, 16)
            }
        }
        .overlay(Color(designSystemColor: .shadowSecondary).opacity(0.7))
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

    return RebrandedPreview(isRebranded: true) {
        NavigationView {
            ScanTabView(
                model: ScanOrPasteCodeViewModel(codeForDisplayOrPasting: sampleCode, qrCodeString: sampleCode, source: .connect)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SimplifiedSyncStyle.screenBackground)
            .environment(\.colorScheme, .dark)
        }
    }
}
#endif
