//
//  SafariExportInterstitialView.swift
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

import SwiftUI
import UIKit
import DesignResourcesKit
import DuckUI
import Lottie

struct SafariExportInterstitialView: View {

    var onOpenSettingsToExport: (() -> Void)?
    var onCancel: (() -> Void)?
    var onContentHeightChange: ((CGFloat) -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            Button(UserText.actionCancel) {
                onCancel?()
            }
            .daxBodyRegular()
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ExportAnimationView()

            Text(UserText.safariExportInterstitialTip)
                .daxTitle1()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)

            Button {
                onOpenSettingsToExport?()
            } label: {
                Text(UserText.safariExportInterstitialButton)
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: shouldUseExpandedButtonLayout ? 360 : .infinity)
            .padding(.horizontal, shouldUseExpandedButtonLayout ? 32 : 16)
            .padding(.bottom, shouldUseExpandedButtonLayout ? 32 : 12)

        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy -> Color in
            DispatchQueue.main.async {
                onContentHeightChange?(proxy.size.height)
            }
            return Color.clear
        })
        .background(Color(designSystemColor: .background))
    }

    private var shouldUseExpandedButtonLayout: Bool {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return true
        }

        return !(horizontalSizeClass == .compact && verticalSizeClass == .regular)
    }

    fileprivate struct ExportAnimationView: View {
        @Environment(\.colorScheme) private var colorScheme
        @StateObject private var loopCoordinator = AnimationLoopCoordinator()

        private var lottieFileName: String {
            colorScheme == .dark ? "export-passwords-dark-optimised" : "export-passwords-light-optimised"
        }

        var body: some View {
            Lottie.LottieView(animation: .named(lottieFileName))
                .configure { animationView in
                    loopCoordinator.attach(animationView: animationView)
                }
                .frame(width: 300, height: 200)
                .scaledToFit()
                .onAppear {
                    loopCoordinator.start(initialDelay: Constants.initialDelay,
                                          pauseBetweenLoops: Constants.pauseBetweenLoops)
                }
                .onDisappear {
                    loopCoordinator.stop()
                }
                .onChange(of: lottieFileName) { _ in
                    loopCoordinator.restart(initialDelay: Constants.initialDelay)
                }
        }

        private enum Constants {
            static let initialDelay: TimeInterval = 1.0
            static let pauseBetweenLoops: TimeInterval = 1.0
        }

        private final class AnimationLoopCoordinator: ObservableObject {
            private weak var animationView: LottieAnimationView?
            private var pendingWorkItem: DispatchWorkItem?
            private var pauseBetweenLoops: TimeInterval = 1.0
            private var isRunning = false

            func attach(animationView: LottieAnimationView) {
                self.animationView = animationView
                animationView.stop()
                animationView.currentProgress = 0

                if isRunning {
                    scheduleNextPlay(after: 0)
                }
            }

            func start(initialDelay: TimeInterval, pauseBetweenLoops: TimeInterval) {
                self.pauseBetweenLoops = pauseBetweenLoops
                isRunning = true
                scheduleNextPlay(after: initialDelay)
            }

            func restart(initialDelay: TimeInterval) {
                guard isRunning else { return }
                scheduleNextPlay(after: initialDelay)
            }

            func stop() {
                isRunning = false
                pendingWorkItem?.cancel()
                pendingWorkItem = nil
                animationView?.stop()
                animationView?.currentProgress = 0
            }

            private func scheduleNextPlay(after delay: TimeInterval) {
                pendingWorkItem?.cancel()

                let workItem = DispatchWorkItem { [weak self] in
                    guard let self,
                          self.isRunning,
                          let animationView = self.animationView else {
                        return
                    }

                    animationView.play(fromProgress: 0, toProgress: 1, loopMode: .playOnce) { [weak self] completed in
                        guard let self,
                              completed,
                              self.isRunning else {
                            return
                        }

                        self.scheduleNextPlay(after: self.pauseBetweenLoops)
                    }
                }

                pendingWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }
    }
}

#Preview {
    SafariExportInterstitialView(onOpenSettingsToExport: {}, onCancel: {})
}

#Preview("Export Animation") {
    SafariExportInterstitialView.ExportAnimationView()
}
