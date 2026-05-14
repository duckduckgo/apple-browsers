//
//  FireModePromotionCardView.swift
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

struct FireModePromotionCardView: View {

    let onTryFireTabs: () -> Void
    let onDismiss: () -> Void
    let onClose: () -> Void
    let onDidAppear: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: Metrics.contentGap) {
                contentSection
                buttonsSection
            }
            .padding(Metrics.cardInnerPadding)

            closeButton
        }
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardCornerRadius)
                .fill(Color(designSystemColor: .surface))
                .shadow(color: Color(designSystemColor: .shadowPrimary),
                        radius: Metrics.shadow1Radius,
                        x: 0, y: Metrics.shadow1OffsetY)
                .shadow(color: Color(designSystemColor: .shadowPrimary),
                        radius: Metrics.shadow2Radius,
                        x: 0, y: Metrics.shadow2OffsetY)
        )
        .onAppear {
            onDidAppear()
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        VStack(spacing: Metrics.contentGap) {
            Image(uiImage: DesignSystemImages.Color.Size96.fireTab)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)

            Text(UserText.fireModePromotionTitle)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Text(UserText.fireModeNTPPromotionDescription)
                .daxSubheadRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Metrics.contentHorizontalPadding)
        .padding(.top, Metrics.contentTopPadding)
    }

    // MARK: - Buttons

    private var buttonsSection: some View {
        HStack(spacing: Metrics.buttonSpacing) {
            Button(action: onDismiss) {
                Text(UserText.fireModeNTPPromotionDismiss)
                    .daxButton()
                    .foregroundColor(Color(designSystemColor: .buttonsPrimaryDefault))
            }
            .frame(height: Metrics.buttonHeight)
            .padding(.horizontal, Metrics.buttonHorizontalPadding)
            .contentShape(Rectangle())

            Button(action: onTryFireTabs) {
                Text(UserText.fireModeNTPPromotionPrimaryAction)
                    .daxButton()
                    .foregroundColor(Color(designSystemColor: .accentContentPrimary))
            }
            .frame(height: Metrics.buttonHeight)
            .padding(.horizontal, Metrics.buttonHorizontalPadding)
            .background(Color(designSystemColor: .buttonsPrimaryDefault))
            .cornerRadius(Metrics.buttonCornerRadius)
        }
        .padding(Metrics.buttonSectionPadding)
    }

    // MARK: - Close

    private var closeButton: some View {
        Button(action: onClose) {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                .foregroundColor(.primary)
        }
        .frame(width: Metrics.closeButtonSize, height: Metrics.closeButtonSize)
        .contentShape(Rectangle())
        .padding(.top, Metrics.cardInnerPadding)
        .padding(.trailing, Metrics.cardInnerPadding)
    }
}

// MARK: - Metrics

private enum Metrics {
    static let cardCornerRadius: CGFloat = 16
    static let cardInnerPadding: CGFloat = 8

    static let contentGap: CGFloat = 4
    static let contentHorizontalPadding: CGFloat = 16
    static let contentTopPadding: CGFloat = 8

    static let iconSize: CGFloat = 48

    static let buttonSpacing: CGFloat = 8
    static let buttonHeight: CGFloat = 40
    static let buttonHorizontalPadding: CGFloat = 16
    static let buttonCornerRadius: CGFloat = 12
    static let buttonSectionPadding: CGFloat = 8

    static let closeButtonSize: CGFloat = 36

    static let shadow1Radius: CGFloat = 12
    static let shadow1OffsetY: CGFloat = 4
    static let shadow2Radius: CGFloat = 48
    static let shadow2OffsetY: CGFloat = 16
}

// MARK: - Preview

#if DEBUG
#Preview {
    FireModePromotionCardView(
        onTryFireTabs: {},
        onDismiss: {},
        onClose: {},
        onDidAppear: {}
    )
    .padding()
}
#endif
