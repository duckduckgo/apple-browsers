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

import SwiftUI
import DesignResourcesKit

struct DuckPlayerEntryPillView: View {
    @ObservedObject var viewModel: DuckPlayerEntryPillViewModel
    
    // Add state to track the height
    @State private var viewHeight: CGFloat = 100
    @State private var iconSize: CGFloat = 40

    struct Constants {
        static let daxLogo = "Home"
        static let playImage = "play.fill"

        enum Layout {
            static let iconSize: CGFloat = 40
            static let stackSpacing: CGFloat = 12
            static let fontSize: CGFloat = 16
            static let playButtonFont: CGFloat = 20
            static let cornerRadius: CGFloat = 12
            static let shadowOpacity: CGFloat = 0.2
            static let shadowRadius: CGFloat = 8
            static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
            static let viewOffset: CGFloat = 20
            static let regularPadding: CGFloat = 16
            static let bottomSpacer: CGFloat = 25
        }
    }


    private var sheetContent: some View {
        Button(action: { viewModel.openInDuckPlayer() }) {
            VStack(spacing: Constants.Layout.stackSpacing) {
                HStack(spacing: Constants.Layout.stackSpacing) {
                    Image(Constants.daxLogo)
                        .resizable()
                        .frame(width: Constants.Layout.iconSize, height: Constants.Layout.iconSize)
                    
                    Text(UserText.duckPlayerNativeOpenInDuckPlayer)
                        .font(.system(size: Constants.Layout.fontSize, weight: .semibold))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    
                    Spacer()
                    
                    Image(systemName: Constants.playImage)
                        .font(.system(size: Constants.Layout.playButtonFont))
                        .foregroundColor(.white)
                        .frame(width: iconSize, height: iconSize)
                        .background(Color.blue)
                        .clipShape(Circle())
            
                }
                .padding(Constants.Layout.regularPadding)
            }
            .background(Color(designSystemColor: .surface))
            .cornerRadius(Constants.Layout.cornerRadius)
            .shadow(color: Color.black.opacity(Constants.Layout.shadowOpacity),
                    radius: Constants.Layout.shadowRadius,
                    x: Constants.Layout.shadowOffset.width,
                    y: Constants.Layout.shadowOffset.height)
            .padding(.horizontal, Constants.Layout.regularPadding)
            .padding(.vertical, Constants.Layout.regularPadding)
            .padding(.bottom, Constants.Layout.bottomSpacer) // Add padding to cover border during animation                      
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(designSystemColor: .panel)
            sheetContent
        }
        .clipShape(CustomRoundedCorners(radius: Constants.Layout.cornerRadius,
                                        corners: [.topLeft, .topRight]))
        .shadow(color: Color.black.opacity(Constants.Layout.shadowOpacity),
                radius: Constants.Layout.shadowRadius, x: Constants.Layout.shadowOffset.width, y: Constants.Layout.shadowOffset.height)
        .offset(y: Constants.Layout.viewOffset)
    }
}
