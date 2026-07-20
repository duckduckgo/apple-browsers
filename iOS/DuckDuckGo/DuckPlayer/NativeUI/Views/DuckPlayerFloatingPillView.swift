//
//  DuckPlayerFloatingPillView.swift
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

/// Floating-pill thumbnail. Renders an already-downloaded image (the presenter waits for it before
/// sliding the pill in), so it moves as one unit with the pill instead of loading on its own timeline.
private struct FloatingPillThumbnailImage: View {
    let image: UIImage?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Rectangle().foregroundColor(.gray.opacity(0.3))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }
}

/// Shared black rounded-rect pill for the Floating UI Duck Player prompts.
/// The whole pill is tappable; `DuckPlayerContainer` provides swipe-down-to-dismiss.
private struct DuckPlayerFloatingPillContent: View {
    let showsLogo: Bool
    let title: String
    let subtitle: String
    let thumbnailImage: UIImage?
    let accessibilityID: String
    let action: () -> Void

    struct Constants {
        static let cornerRadius: CGFloat = 26
        static let logoSize: CGFloat = 40
        static let thumbnailSize: (w: CGFloat, h: CGFloat) = (72, 48)
        static let thumbnailCornerRadius: CGFloat = 16
        static let thumbnailStrokeOpacity: CGFloat = 0.25
        static let hStackSpacing: CGFloat = 12
        static let vStackSpacing: CGFloat = 2
        static let contentPadding: CGFloat = 12
        static let playIconSize: CGFloat = 24
        static let playIconShadowOpacity: CGFloat = 0.1
        static let playIconShadowRadius: CGFloat = 4
        static let playIconShadowOffset = CGSize(width: 0, height: 1)
    }

    private var thumbnail: some View {
        FloatingPillThumbnailImage(
            image: thumbnailImage,
            width: Constants.thumbnailSize.w,
            height: Constants.thumbnailSize.h
        )
        .frame(width: Constants.thumbnailSize.w, height: Constants.thumbnailSize.h)
        .clipShape(RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(Constants.thumbnailStrokeOpacity), lineWidth: 1)
        )
        .overlay(
            Image(uiImage: DesignSystemImages.Glyphs.Size20.videoPlaySolid)
                .renderingMode(.template)
                .foregroundColor(.white)
                .frame(width: Constants.playIconSize, height: Constants.playIconSize)
                .shadow(
                    color: Color.black.opacity(Constants.playIconShadowOpacity),
                    radius: Constants.playIconShadowRadius,
                    x: Constants.playIconShadowOffset.width,
                    y: Constants.playIconShadowOffset.height
                )
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.hStackSpacing) {
                if showsLogo {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.duckDuckGoDaxColor)
                        .resizable()
                        .frame(width: Constants.logoSize, height: Constants.logoSize)
                }

                VStack(alignment: .leading, spacing: Constants.vStackSpacing) {
                    Text(title)
                        .daxSubheadSemibold()
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    Text(subtitle)
                        .daxFootnoteRegular()
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .layoutPriority(1)

                thumbnail
            }
            .padding(Constants.contentPadding)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// The Floating UI entry pill ("Play this video in Duck Player").
struct DuckPlayerFloatingEntryPillView: View {
    @ObservedObject var viewModel: DuckPlayerEntryPillViewModel

    var body: some View {
        DuckPlayerFloatingPillContent(
            showsLogo: true,
            title: UserText.duckPlayerFloatingPillTitle,
            subtitle: UserText.duckPlayerOptInPillSubtitle,
            thumbnailImage: viewModel.thumbnailImage,
            accessibilityID: "Play this video in Duck Player",
            action: { viewModel.openInDuckPlayer() }
        )
    }
}

/// The Floating UI re-entry pill ("Resume in Duck Player").
struct DuckPlayerFloatingMiniPillView: View {
    @ObservedObject var viewModel: DuckPlayerMiniPillViewModel

    var body: some View {
        DuckPlayerFloatingPillContent(
            showsLogo: false,
            title: UserText.duckPlayerResumeInDuckPlayer,
            subtitle: viewModel.title,
            thumbnailImage: viewModel.thumbnailImage,
            accessibilityID: "Resume in Duck Player",
            action: { viewModel.openInDuckPlayer() }
        )
    }
}
