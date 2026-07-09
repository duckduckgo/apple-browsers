//
//  SessionRestorePromptView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Common
import SwiftUI
import SwiftUIExtensions
import DesignResourcesKitIcons

struct SessionRestorePromptView: View {

    struct Metrics {
        let width: CGFloat
        let containerTopPadding: CGFloat
        let containerBottomPadding: CGFloat
        let containerHorizontalPadding: CGFloat
        let iconBottomPadding: CGFloat
        let titleBottomPadding: CGFloat
        let messageBottomPadding: CGFloat
        let buttonHeight: CGFloat
        let popoverSize: CGSize

        static func current(isAppRebranded: Bool) -> Metrics {
            let popoverSize = NSSize(width: 294, height: 256)
            guard isAppRebranded else {
                let containerBottomPadding: CGFloat = AppVersion.isLiquidGlassSupported ? 20 : 16
                let containerHorizontalPadding: CGFloat = AppVersion.isLiquidGlassSupported ? 20 : 16

                return Metrics(width: 320, containerTopPadding: 8, containerBottomPadding: containerBottomPadding, containerHorizontalPadding: containerHorizontalPadding, iconBottomPadding: 8, titleBottomPadding: 12, messageBottomPadding: 8, buttonHeight: 28, popoverSize: popoverSize)
            }

            return Metrics(width: 320, containerTopPadding: 16, containerBottomPadding: 16, containerHorizontalPadding: 16, iconBottomPadding: 16, titleBottomPadding: 13, messageBottomPadding: 36, buttonHeight: 22, popoverSize: popoverSize)
        }
    }

    @ObservedObject var model: SessionRestorePromptViewModel
    let isAppRebranded: Bool
    var dismiss: () -> Void

    var body: some View {
        let metrics = Metrics.current(isAppRebranded: isAppRebranded)

        VStack(spacing: 0) {
            if isAppRebranded {
                Image(nsImage: DesignSystemImages.Color.Size96.browserWarn)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .padding(.bottom, metrics.iconBottomPadding)
            } else {
                Image(nsImage: .browserError128)
                    .padding(.bottom, metrics.iconBottomPadding)
            }

            Text(UserText.sessionRestorePromptTitle)
                .font(.title3)
                .bold()
                .multilineText()
                .padding(.bottom, metrics.titleBottomPadding)

            Text(UserText.sessionRestorePromptMessage)
                .multilineText()
                .font(.body)
                .padding(.bottom, metrics.messageBottomPadding)

            if !isAppRebranded {
                Text(.init(UserText.sessionRestorePromptExplanation))
                    .multilineText()
                    .font(.body)
                    .padding(.bottom, 20)
            }

            HStack {
                Button {
                    model.startFresh()
                    dismiss()
                } label: {
                    Text(UserText.sessionRestorePromptButtonReject)
                        .multilineText()
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.buttonHeight)
                }
                .buttonStyle(StandardButtonStyle(pillShape: true))
                .accessibilityIdentifier("session.restore.prompt.reject")

                Button {
                    model.restoreSession()
                    dismiss()
                } label: {
                    Text(UserText.sessionRestorePromptButtonAccept)
                        .multilineText()
                        .frame(maxWidth: .infinity)
                        .frame(height: metrics.buttonHeight)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, pillShape: true))
                .accessibilityIdentifier("session.restore.prompt.accept")
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, metrics.containerTopPadding)
        .padding(.horizontal, metrics.containerHorizontalPadding)
        .padding(.bottom, metrics.containerBottomPadding)
        .frame(width: metrics.width)
    }
}
