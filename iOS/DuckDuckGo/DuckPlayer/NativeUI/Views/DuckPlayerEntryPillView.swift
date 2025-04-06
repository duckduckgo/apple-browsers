//
//  DuckPlayerEntryPillView.swift
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

struct DuckPlayerEntryPillView: View {
    @ObservedObject var viewModel: DuckPlayerEntryPillViewModel

    // Add state to track the height
    @State private var viewHeight: CGFloat = 100
    @State private var iconSize: CGFloat = 40

    @Environment(\.colorScheme) private var colorScheme

    struct Constants {
        static let daxLogo = "Home"
        static let playImage = "play.fill"

        // Layout
        static let iconSize: CGFloat = 40
        static let vStackSpacing: CGFloat = 4
        static let hStackSpacing: CGFloat = 10
        static let fontSize: CGFloat = 16
        static let playButtonFont: CGFloat = 16
        static let cornerRadius: CGFloat = 16
        static let shadowOpacity: CGFloat = 0.1
        static let shadowRadius: CGFloat = 3
        static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
        static let regularPadding: CGFloat = 12
    }

    private var playButton: some View {
        Image(systemName: Constants.playImage)
            .font(.system(size: Constants.playButtonFont))
            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
            .frame(width: iconSize, height: iconSize)
            .background(Color(designSystemColor: .buttonsPrimaryDefault))
            .clipShape(Circle())
    }

    private var sheetContent: some View {
        Button(
            action: { viewModel.openInDuckPlayer() },
            label: {
                VStack(spacing: Constants.vStackSpacing) {
                    HStack(spacing: Constants.hStackSpacing) {

                        Image(Constants.daxLogo)
                            .resizable()
                            .frame(width: Constants.iconSize, height: Constants.iconSize)

                        VStack(alignment: .leading) {
                            Text(UserText.duckPlayerNativeOpenInDuckPlayer)
                                .daxSubheadSemibold()
                                .foregroundColor(Color(designSystemColor: .textPrimary))
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)

                            Text(UserText.duckPlayerTapToWatchWithoutAds)
                                .daxFootnoteRegular()
                                .foregroundColor(Color(designSystemColor: .textSecondary))
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .layoutPriority(1)

                        Spacer()

                        playButton
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
