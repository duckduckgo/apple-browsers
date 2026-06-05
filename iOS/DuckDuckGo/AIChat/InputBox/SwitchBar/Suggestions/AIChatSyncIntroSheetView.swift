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
import MetricBuilder
import SwiftUI

struct AIChatSyncIntroSheetView: View {

    let onScanTap: () -> Void
    let onNotNowTap: () -> Void

    var body: some View {
        VStack(spacing: SheetMetrics.contentSpacing) {
            VStack(spacing: SheetMetrics.contentSpacing) {
                Image(rebrandable: "Sync-Desktop-Mobile-Pair-Feature-128")

                Text(UserText.aiChatSyncIntroSheetTitle)
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LocalizedStringKey(UserText.aiChatSyncIntroSheetBody))
                    .daxBodyRegular()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 20)
            .foregroundStyle(Color(designSystemColor: .textPrimary))

            VStack(spacing: ButtonStackMetrics.interButtonSpacing) {
                Button(action: onScanTap) {
                    HStack {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ButtonStackMetrics.containerPadding)
        .padding(.top, 20)
        .background(Color(designSystemColor: .backgroundSheets).ignoresSafeArea())
    }
}


#Preview {
    AIChatSyncIntroSheetView(onScanTap: {}, onNotNowTap: {})
}

#Preview {
     AIChatSyncIntroSheetView(onScanTap: {}, onNotNowTap: {})
        .colorScheme(.dark)
}
