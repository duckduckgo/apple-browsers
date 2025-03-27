//
//  DuckPlayerMiniPillView.swift
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

import DesignResourcesKit
import SwiftUI

/// A view that loads an image asynchronously with animation
struct AnimatedAsyncImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    struct Constants {
        static let backgroundColor: Color = .gray.opacity(0.3)
    }

    private var placeholderView: some View {
        Rectangle()
            .foregroundColor(Constants.backgroundColor)
            .frame(width: width, height: height)
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .contentShape(Rectangle())
                .transition(.opacity.combined(with: .scale))
        } placeholder: {
            placeholderView
        }
        .frame(width: width, height: height)
        .animation(.easeInOut(duration: 0.3), value: url)
        .id(url?.absoluteString ?? "")
    }
}

struct DuckPlayerMiniPillView: View {
    @ObservedObject var viewModel: DuckPlayerMiniPillViewModel

    // Add state to track the height
    @State private var viewHeight: CGFloat = 100
    @State private var iconSize: CGFloat = 40

    @Environment(\.colorScheme) private var colorScheme

    struct Constants {
        static let playImage = "play.fill"

        // Layout
        static let thumbnailSize: (w: CGFloat, h: CGFloat) = (60, 33.7)
        static let thumbnailCornerRadius: CGFloat = 8
        static let vStackSpacing: CGFloat = 4
        static let hStackSpacing: CGFloat = 10
        static let fontSize: CGFloat = 16
        static let playButtonFont: CGFloat = 20
        static let cornerRadius: CGFloat = 12
        static let shadowOpacity: CGFloat = 0.2
        static let shadowRadius: CGFloat = 8
        static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
        static let viewOffset: CGFloat = 20
        static let regularPadding: CGFloat = 16
       
    }

    private var sheetContent: some View {
        Button(
            action: { viewModel.openInDuckPlayer() },
            label: {
                VStack(spacing: Constants.vStackSpacing) {
                    HStack(spacing: Constants.hStackSpacing) {

                        // YouTube thumbnail image
                        Group {
                            AnimatedAsyncImage(
                                url: viewModel.thumbnailURL,
                                width: Constants.thumbnailSize.w,
                                height: Constants.thumbnailSize.h
                            )
                        }
                        .frame(width: Constants.thumbnailSize.w, height: Constants.thumbnailSize.h)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.thumbnailCornerRadius))

                        VStack(alignment: .leading) {
                            Text(UserText.duckPlayerNativeResumeInDuckPlayer)
                                .daxSubheadSemibold()
                                .foregroundColor(Color(designSystemColor: .textPrimary))
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(viewModel.title)
                                .daxFootnoteRegular()
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .layoutPriority(1)

                    }
                    .padding(Constants.regularPadding)
                    .background(
                        Color(designSystemColor: colorScheme == .dark ? .container : .backgroundSheets)
                    )

                }
                .cornerRadius(Constants.cornerRadius)
                .shadow(
                    color: Color.black.opacity(Constants.shadowOpacity), radius: Constants.shadowRadius,
                    x: Constants.shadowOffset.width, y: Constants.shadowOffset.height
                )

            })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(designSystemColor: .panel)
            sheetContent
        }
    }
}
