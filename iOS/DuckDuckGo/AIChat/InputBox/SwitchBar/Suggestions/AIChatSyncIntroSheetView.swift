//
//  AIChatSyncIntroSheetView.swift
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

/// Intro bottom sheet shown after the user taps the Chat Sync promo card. "Scan QR Code" launches the existing
/// Sync pairing flow; "Not Now" simply dismisses the sheet (the promo is already dismissed by the CTA tap).
struct AIChatSyncIntroSheetView: View {

    let onScanTap: () -> Void
    let onNotNowTap: () -> Void

    @State private var bottomSafeArea: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Image(.syncDesktopMobilePairFeature128)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 96)
                    .padding(.bottom, 20)

                Text(UserText.aiChatSyncIntroSheetTitle)
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)

                Text(UserText.aiChatSyncIntroSheetBody)
                    .daxBodyRegular()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color(designSystemColor: .textPrimary))
            .padding(.horizontal, 24)
            .padding(.top, 56)

            Spacer()

            VStack(spacing: 8) {
                Button(action: onScanTap) {
                    HStack(spacing: 8) {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.qr)
                        Text(UserText.aiChatSyncIntroSheetScanButton)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: onNotNowTap) {
                    Text(UserText.aiChatSyncIntroSheetNotNow)
                }
                .buttonStyle(GhostButtonStyle())
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 30)
            .padding(.bottom, max(20 - bottomSafeArea, 0))
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { bottomSafeArea = geometry.safeAreaInsets.bottom }
            }
        )
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }
}

#Preview {
    AIChatSyncIntroSheetView(onScanTap: {}, onNotNowTap: {})
}
