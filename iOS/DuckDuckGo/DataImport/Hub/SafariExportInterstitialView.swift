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
                .padding(.bottom, 8)

            Text(UserText.safariExportInterstitialNoCompatibleBrowsersMessage)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .padding(.horizontal, 16)
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
        !(horizontalSizeClass == .compact && verticalSizeClass == .regular)
    }

    private struct ExportAnimationView: View {
        @Environment(\.colorScheme) private var colorScheme

        private var lottieFileName: String {
            colorScheme == .dark ? "export-passwords-dark-optimised" : "export-passwords-light-optimised"
        }

        var body: some View {
            Lottie.LottieView(animation: .named(lottieFileName))
                .playing(loopMode: .playOnce)
                .frame(width: 300, height: 200)
                .scaledToFit()
        }
    }
}
