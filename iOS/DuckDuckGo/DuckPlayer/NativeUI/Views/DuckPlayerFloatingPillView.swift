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

/// Shared black rounded-rect pill content used by the Floating UI Duck Player prompts.
///
/// Builds on the toast pattern using a black background (both light and dark), suggesting the
/// theater mode of Duck Player. The whole pill is tappable and the enclosing
/// `DuckPlayerContainer` provides the swipe-down-to-dismiss gesture.
private struct DuckPlayerFloatingPillContent: View {
    let showsLogo: Bool
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
    let accessibilityID: String
    let action: () -> Void

    struct Constants {
        static let cornerRadius: CGFloat = 16
        static let logoSize: CGFloat = 40
        static let thumbnailSize: (w: CGFloat, h: CGFloat) = (72, 48)
        static let thumbnailCornerRadius: CGFloat = 8
        static let hStackSpacing: CGFloat = 12
        static let vStackSpacing: CGFloat = 2
        static let contentPadding: CGFloat = 12
        static let horizontalMargin: CGFloat = 6
        static let playBadgeSize: CGFloat = 24
    }

    private var thumbnail: some View {
        AnimatedAsyncImage(
            url: thumbnailURL,
            width: Constants.thumbnailSize.w,
            height: Constants.thumbnailSize.h,
            cornerRadius: Constants.thumbnailCornerRadius,
            borderColor: nil,
            borderWidth: nil,
            borderOpacity: nil
        )
        .frame(width: Constants.thumbnailSize.w, height: Constants.thumbnailSize.h)
        .clipShape(RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius))
        .overlay(
            Image(uiImage: DesignSystemImages.Glyphs.Size16.playSolid)
                .foregroundColor(.white)
                .frame(width: Constants.playBadgeSize, height: Constants.playBadgeSize)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.hStackSpacing) {
                if showsLogo {
                    Image(.home)
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
            .cornerRadius(Constants.cornerRadius)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Constants.horizontalMargin)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// The Floating UI entry pill ("Play this video in Duck Player").
struct DuckPlayerFloatingEntryPillView: View {
    @ObservedObject var viewModel: DuckPlayerEntryPillViewModel

    var body: some View {
        DuckPlayerFloatingPillContent(
            showsLogo: true,
            title: UserText.duckPlayerOptInPillTitle,
            subtitle: UserText.duckPlayerOptInPillSubtitle,
            thumbnailURL: viewModel.thumbnailURL,
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
            thumbnailURL: viewModel.thumbnailURL,
            accessibilityID: "Resume in Duck Player",
            action: { viewModel.openInDuckPlayer() }
        )
    }
}
