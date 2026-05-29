//
//  AIChatSyncPromoView.swift
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

struct AIChatSyncPromoView: View {

    let onCTATap: () -> Void
    let onCloseTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 16) {
                Image(rebrandable: "Sync-AI-Feature-96")
                    .resizable()
                    .frame(width: 72, height: 72)

                Text(UserText.aiChatSyncPromoTitle)
                    .daxHeadline()
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)

                Button(action: onCTATap) {
                    Text(UserText.aiChatSyncPromoButton)
                }
                .buttonStyle(PrimaryButtonStyle(compact: true, fullWidth: false))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 8)

            Button(action: onCloseTap) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .foregroundColor(Color(designSystemColor: .icons))
            }
            .frame(width: 36, height: 36)
            .padding(4)
            .accessibilityLabel(UserText.aiChatSyncPromoCloseAccessibilityLabel)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(designSystemColor: .surface))
        )
    }
}

#Preview {
    AIChatSyncPromoView(onCTATap: {}, onCloseTap: {})
}

#Preview {
    AIChatSyncPromoView(onCTATap: {}, onCloseTap: {})
        .colorScheme(.dark)
}
