//
//  Untitled.swift
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

import DuckUI
import Onboarding
import SwiftUI
import UIComponents
import DesignResourcesKitIcons

extension OnboardingPersonalizationContent.Item.ItemType {

    var icon: Image {
        switch self {
        case .recentlyVisitedSites:
            Image(uiImage: DesignSystemImages.Color.Size24.history)
        case .safeSearch:
            Image(uiImage: DesignSystemImages.Color.Size24.exclamation)
        case .searchAssist:
            Image("")
        case .aiGeneratedImages:
            Image("")
        case .youTubeAdBlocking:
            Image(uiImage: DesignSystemImages.Color.Size24.adsBlocked)
        case .duckPlayer:
            Image(uiImage: DesignSystemImages.Color.Size24.videoPlayer)
        }
    }

}


struct OnboardingPersonalizationToggleItemsList: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let items: [OnboardingPersonalizationToggleItem]

    var body: some View {
        VStack(spacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing) {
            ForEach(items) { item in
                OnboardingPersonalizationToggleItemView(icon: item.item.type.icon, title: item.item.title, subtitle: item.item.subtitle, toggleBinding: item.isOn)
                Divider()
                    .frame(height: 1.0)
                    .padding(.top, 16.0)
            }
        }
    }
}


struct OnboardingPersonalizationToggleItemView: View {
    private enum Metrics {
        static let iconTextHorizontalSpacing: CGFloat = 10.0
        static let copyVerticalSpacing: CGFloat = 8.0
    }

    @Environment(\.onboardingTheme) private var onboardingTheme

    let icon: Image
    let title: String
    let subtitle: String?
    let toggleBinding: Binding<Bool>

    var body: some View {
        CardItem(
            icon: CardItemIcon(
                position: .leadingColumn,
                visual: .image(icon),
                spacing: Metrics.iconTextHorizontalSpacing
            ),
            title: CardItemText(
                title,
                font: CardItemFont(onboardingTheme.typography.row)
            ),
            text: subtitle.map { CardItemText($0, font: CardItemFont(onboardingTheme.typography.rowDetails)) },
            titleTextSpacing: Metrics.copyVerticalSpacing,
            trailing: .toggle(toggleBinding, tint: Color(designSystemColor: .accentPrimary))
        )
    }

}
