//
//  SimplifiedScanOrShowCodeView+ScanTab.swift
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

extension SimplifiedScanOrShowCodeView {

    var scanTabContent: some View {
        VStack(spacing: 24) {
            instructionsView
                .padding(.top, 24)

            cameraContainer
                .layoutPriority(1)

            manuallyEnterCodeButton
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Instructions

    private var instructionsView: some View {
        Text("\(UserText.simplifiedScanInstructions)\n\(UserText.simplifiedScanInstructionsLine2)")
            .daxSubheadRegular()
            .foregroundColor(SimplifiedSyncStyle.instructionText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity)
    }

    // MARK: - Camera

    private var cameraContainer: some View {
        ZStack(alignment: .bottom) {
            Group {
                if model.videoPermission == .denied {
                    cameraPermissionDeniedView
                } else if model.videoPermission == .authorised && !model.showCamera {
                    cameraUnavailableView
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

    // MARK: - Camera Permission Denied

    private var cameraPermissionDeniedView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("SyncCameraPermission")
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

    // MARK: - Camera Unavailable

    private var cameraUnavailableView: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("SyncCameraUnavailable")
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

    // MARK: - Manually Enter Code Button

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

    // MARK: - Blur View

    struct BlurView: UIViewRepresentable {
        var style: UIBlurEffect.Style

        func makeUIView(context: Context) -> UIVisualEffectView {
            return UIVisualEffectView(effect: UIBlurEffect(style: style))
        }

        func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
            uiView.effect = UIBlurEffect(style: style)
        }
    }
}
