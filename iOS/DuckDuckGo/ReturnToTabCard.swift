//
//  ReturnToTabCard.swift
//  DuckDuckGo
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

import SwiftUI
import Core
import DesignResourcesKit
import DesignResourcesKitIcons

struct ReturnToTabCard: View {
    let model: EscapeHatchModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center) {
                iconView
                VStack(alignment: .leading, spacing: Metrics.labelToContentSpacing) {
                    returnToLabel
                    VStack(alignment: .leading, spacing: Metrics.titleToSubtitleSpacing) {
                        Text(model.title)
                            .daxHeadline()
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                            .lineLimit(1)
                        Text(model.subtitle)
                            .daxFootnoteRegular()
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(uiImage: DesignSystemImages.Glyphs.Size16.undo)
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                    .fill(Color(designSystemColor: .surface))
                    .shadow(color: Color(designSystemColor: .shadowPrimary), radius: Metrics.shadowRadius1, x: 0, y: Metrics.shadowOffset1)
                    .shadow(color: Color(designSystemColor: .shadowPrimary), radius: Metrics.shadowRadius2, x: 0, y: Metrics.shadowOffset2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityHint(Text("Switches to this tab"))
        .accessibilityIdentifier("NTP.escapeHatch.card")
    }

    private var accessibilityLabelText: String {
        if model.subtitle.isEmpty {
            return "Return to \(model.title)"
        }
        return "Return to \(model.title), \(model.subtitle)"
    }

    private var returnToLabel: some View {
        Text(returnToLabelText)
            .daxFootnoteRegular()
            .foregroundColor(Color(designSystemColor: .textSecondary))
    }

    /// Favicon from .tabs cache, or Duck.ai logo when `model.isAITab`, matching tab switcher (TabsBarCell).
    private var iconView: some View {
        Group {
            if model.isAITab {
                Image(uiImage: DesignSystemImages.Color.Size24.aiChatGradient)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let domain = model.domain {
                DomainFaviconView(domain: domain)
            } else {
                RoundedRectangle(cornerRadius: Metrics.iconCornerRadius)
                    .fill(Color(designSystemColor: .controlsFillSecondary))
            }
        }
        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.iconCornerRadius))
    }

    private var returnToLabelText: String {
        "Return to..."
    }
}

/// Holds FaviconViewModel in @StateObject so it's created once per domain instead of on every body.
private struct DomainFaviconView: View {
    let domain: String

    @StateObject private var viewModel: FaviconViewModel

    init(domain: String) {
        self.domain = domain
        _viewModel = StateObject(wrappedValue: FaviconViewModel(domain: domain, useFakeFavicon: true, cacheType: .tabs))
    }

    var body: some View {
        FaviconView(viewModel: viewModel)
    }
}

private enum Metrics {
    static let cornerRadius: CGFloat = 16
    static let shadowRadius1: CGFloat = 12
    static let shadowRadius2: CGFloat = 48
    static let shadowOffset1: CGFloat = 4
    static let shadowOffset2: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let labelToContentSpacing: CGFloat = 0
    static let titleToSubtitleSpacing: CGFloat = 2
    static let iconSize: CGFloat = 24
    static let iconCornerRadius: CGFloat = 4
}

// MARK: - Previews

#Preview("Return to tab card") {
    ReturnToTabCard(
        model: EscapeHatchModel(
            title: "Tokamak - Wikipedia",
            subtitle: "en.wikipedia.org/wiki/Tokamak",
            isAITab: false,
            domain: "en.wikipedia.org",
            targetTab: Tab(fireTab: false)
        ),
        onTap: {}
    )
    .padding()
    .frame(width: 360)
}

#Preview("Return to Duck.ai") {
    ReturnToTabCard(
        model: EscapeHatchModel(
            title: "Good Dog Name Ideas",
            subtitle: "Duck.ai",
            isAITab: true,
            domain: nil,
            targetTab: Tab(fireTab: false)
        ),
        onTap: {}
    )
    .padding()
    .frame(width: 360)
}
