//
//  TabBarRemoteMessageView.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

struct TabBarRemoteMessageView: View {
    @ObservedObject var themeManager: ThemeManager
    @State private var wasViewHovered: Bool = false
    @State private var wasCloseButtonHovered: Bool = false

    let model: TabBarRemoteMessage

    let onClose: () -> Void
    let onTap: (URL) -> Void
    let onHover: () -> Void
    let onHoverEnd: () -> Void
    let onAppear: () -> Void

    private var palette: ThemeColors {
        themeManager.theme.palette
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                Text(model.buttonTitle)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(Color(palette.accentContentPrimary))
            }
            .padding([.leading, .top, .bottom], 8)
            .padding(.trailing, 6)
            .cornerRadius(8)
            .background(wasViewHovered
                        ? Color(palette.accentSecondary)
                        : Color(palette.accentPrimary))
            .onTapGesture { onTap(model.surveyURL) }
            .onHover { hovering in
                wasViewHovered = hovering

                if hovering {
                    onHover()
                } else {
                    onHoverEnd()
                }
            }

            Divider()
                .background(Color(palette.accentContentTertiary))
                .frame(width: 1)
                .padding([.top, .bottom], 3)

            HStack {
                Image(.close)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(palette.accentContentPrimary))
                    .frame(width: 16, height: 16)
            }
            .padding([.top, .bottom])
            .padding([.leading, .trailing], 4)
            .background(wasCloseButtonHovered
                        ? Color(palette.accentSecondary)
                        : Color(palette.accentPrimary))
            .cornerRadius(8)
            .onTapGesture {
                onClose()
            }
            .onHover { hovering in
                wasCloseButtonHovered = hovering
            }
            .frame(maxWidth: .infinity)
        }
        .background(wasCloseButtonHovered || wasViewHovered
                    ? Color(palette.accentSecondary)
                    : Color(palette.accentPrimary))
        .frame(height: 24)
        .cornerRadius(8)
        .onAppear(perform: { onAppear() })
    }
}

struct TabBarRemoteMessagePopoverContent: View {
    let model: TabBarRemoteMessage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(.daxResponse)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(alignment: .leading, spacing: 8) {
                Text(model.popupTitle)
                    .font(.system(size: 13, weight: .bold))
                    .padding(.top, 9)

                Text(model.popupSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.bottom, 9)
            }
        }
        .frame(width: 360)
        .padding([.top, .bottom], 10)
        .padding(.leading, 12)
        .padding(.trailing, 24)
    }
}
