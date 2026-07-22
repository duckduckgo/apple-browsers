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

    @State private var instructionsHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            if shouldRenderCamera {
                cameraContainer
            }

            if showIntroAnimation {
                introAnimation
            }

            instructions
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: InstructionsHeightKey.self, value: geometry.size.height)
                    }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .ignoresSafeArea(.all, edges: .bottom)
        .onPreferenceChange(InstructionsHeightKey.self) { instructionsHeight = $0 }
        .onAppear {
            model.resetScanningGate()
            model.prepareCameraForIntroIfAuthorized()
        }
    }

    private var shouldRenderCamera: Bool {
        !showIntroAnimation || model.videoPermission == .authorised
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
            .padding(.top, instructionsHeight)

            Button {
                dismissIntroAnimation()
            } label: {
                Text(UserText.simplifiedScanQRReadyButton)
            }
            .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SimplifiedSyncStyle.screenBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissIntroAnimation()
        }
        .transition(.opacity)
    }

    private func dismissIntroAnimation() {
        guard showIntroAnimation else { return }
        showIntroAnimation = false
        model.introAnimationCompleted()
    }

    private var isScanningActive: Bool {
        model.videoPermission == .authorised && model.showCamera
    }

    private var cameraContainer: some View {
        ZStack(alignment: .bottom) {
            Group {
                if model.videoPermission == .denied {
                    CameraPermissionDeniedView(model: model)
                } else if model.videoPermission == .authorised && !model.showCamera {
                    CameraUnavailableView()
                } else if model.videoPermission == .authorised && model.showCamera && isCameraActive {
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
        .overlay {
            if isScanningActive && !showIntroAnimation {
                QRScannerOverlay(topInset: instructionsHeight) {
                    model.scanningCanBegin()
                }
            } else {
                Color(designSystemColor: .shadowSecondary).opacity(0.7)
                    .allowsHitTesting(false)
            }
        }
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

            Image(rebrandable: "SyncCameraPermission", bundle: .module)
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
                    Image("SyncGotoButton", bundle: .module)
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

            Image(rebrandable: "SyncCameraUnavailable", bundle: .module)
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

private struct InstructionsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct QRScannerOverlay: View {

    let topInset: CGFloat
    var onAnimationComplete: (() -> Void)?

    private let cornerRadius: CGFloat = 26
    private let armLength: CGFloat = 28
    private let lineWidth: CGFloat = 6
    private let sideRatio: CGFloat = 0.6
    private let initialScale: CGFloat = 0.5
    private let animationDelay: TimeInterval = 0.5
    private let animationResponse: TimeInterval = 0.5

    @State private var isExpanded = false

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width * sideRatio
            let scale = isExpanded ? 1 : initialScale
            let center = CGPoint(x: proxy.size.width / 2, y: topInset + (proxy.size.height - topInset) / 2)

            Color(designSystemColor: .shadowSecondary).opacity(0.7)
                .mask {
                    Rectangle()
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .frame(width: side, height: side)
                                .scaleEffect(scale)
                                .position(center)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                }

            QRCornerBrackets(cornerRadius: cornerRadius, armLength: armLength)
                .stroke(Color(designSystemColor: .accentPrimary), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)
                .scaleEffect(scale)
                .position(center)
        }
        .onAppear {
            withAnimation(.spring(response: animationResponse, dampingFraction: 0.6).delay(animationDelay)) {
                isExpanded = true
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64((animationDelay + animationResponse) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            onAnimationComplete?()
        }
    }
}

private struct QRCornerBrackets: Shape {

    let cornerRadius: CGFloat
    let armLength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius + armLength))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + cornerRadius + armLength, y: rect.minY),
                    radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius + armLength, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - cornerRadius - armLength, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius + armLength),
                    radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius + armLength))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius - armLength))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - cornerRadius - armLength, y: rect.maxY),
                    radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius - armLength, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + cornerRadius + armLength, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius - armLength),
                    radius: cornerRadius)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius - armLength))

        return path
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

#Preview("Permission Denied") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .denied, showCamera: false))
}

#Preview("Intro Animation") {
    ScanTabPreview(model: scanTabPreviewModel(permission: .authorised, showCamera: true), showIntroAnimation: true)
}

#Preview("Scanner Overlay") {
    QRScannerOverlay(topInset: 0)
        .background(SimplifiedSyncStyle.screenBackground)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
}
#endif
