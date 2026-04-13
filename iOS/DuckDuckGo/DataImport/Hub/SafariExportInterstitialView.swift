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

struct SafariExportInterstitialView: View {

    var onOpenSettingsToExport: (() -> Void)?
    var onCancel: (() -> Void)?

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(UserText.actionCancel) {
                    onCancel?()
                }
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Spacer()

            ExportAnimationView(isAnimating: $isAnimating)

            Text(UserText.safariExportInterstitialTip)
                .daxTitle2()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            Spacer().frame(height: 24)

            Button {
                onOpenSettingsToExport?()
            } label: {
                Text(UserText.safariExportInterstitialButton)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 16)

            Spacer()
        }
        .background(Color(designSystemColor: .background))
        .onFirstAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = true
            }
        }
    }

    private struct ExportAnimationView: View {
        @Binding var isAnimating: Bool
        @Environment(\.colorScheme) private var colorScheme

        private var lottieFileName: String {
            colorScheme == .dark ? "export-passwords-dark-optimised" : "export-passwords-light-optimised"
        }

        var body: some View {
            LottieView(
                lottieFile: lottieFileName,
                loopMode: .mode(.repeat(1.0)),
                isAnimating: $isAnimating
            )
            .frame(width: 200, height: 200)
        }
    }
}
