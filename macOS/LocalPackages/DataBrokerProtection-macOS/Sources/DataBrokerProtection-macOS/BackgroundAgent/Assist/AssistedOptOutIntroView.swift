//
//  AssistedOptOutIntroView.swift
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

import DataBrokerProtectionCore
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions

/// Shown in place of the broker page before the attempt starts. It explains where the user will need to help and lets them start.
@MainActor
struct AssistedOptOutIntroView: View {
    @Environment(\.designSystemPalette) private var palette
    @ObservedObject var session: AssistedOptOutSession

    private var brokerName: String { session.broker.name }

    var body: some View {
        ScrollView {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(nsImage: DesignSystemImages.Color.Size96.duckDuckGo)
                .resizable()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            Text(AssistedOptOutText.readyToRemove(brokerName))
                .font(.system(size: 30))
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 20)
            Text(AssistedOptOutText.introDescription)
                .font(.system(size: 16))
                .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            whereWeNeedYourHelp
                .padding(.top, 22)
            HStack(spacing: 16) {
                Button {
                    session.begin()
                } label: {
                    Text(AssistedOptOutText.startRequest)
                        .font(.system(size: 16, weight: .medium))
                        .padding(.horizontal, 20)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 14, bottomPadding: 14,
                                                      stateColors: .assistedOptOutAction(palette: palette)))
                Text(AssistedOptOutText.stopAnytime)
                    .font(.system(size: 14))
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var whereWeNeedYourHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AssistedOptOutText.whereHelpNeeded)
                .font(.system(size: 12, weight: .medium))
                .kerning(1.5)
                .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
            helpCard(icon: DesignSystemImages.Glyphs.Size16.check,
                     title: AssistedOptOutText.proveHuman,
                     detail: AssistedOptOutText.proveHumanDetail(brokerName))
            helpCard(icon: DesignSystemImages.Glyphs.Size16.sendPlane,
                     title: AssistedOptOutText.reviewAndSubmit,
                     detail: AssistedOptOutText.reviewDetail)
        }
    }

    private func helpCard(icon: NSImage, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: icon)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .statusWarningContentPrimary, palette: palette))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(designSystemColor: .statusWarningFillPrimary, palette: palette)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .assistedOptOutCallout(palette: palette)
    }
}

private struct AssistedOptOutCallout: ViewModifier {
    let palette: ColorPalette

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(designSystemColor: .statusWarningFillPrimary, palette: palette)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(designSystemColor: .statusYellowPrimary, palette: palette), lineWidth: 1.5))
    }
}

extension View {
    func assistedOptOutCallout(palette: ColorPalette) -> some View {
        modifier(AssistedOptOutCallout(palette: palette))
    }
}

extension ButtonStateColors {
    static func assistedOptOutAction(palette: ColorPalette) -> ButtonStateColors {
        .init(backgroundColor: Color(designSystemColor: .accentPrimary, palette: palette),
              textColor: Color(designSystemColor: .accentContentPrimary, palette: palette),
              hoveredBackgroundColor: Color(designSystemColor: .accentSecondary, palette: palette),
              pressedBackgroundColor: Color(designSystemColor: .accentTertiary, palette: palette),
              pressedTextColor: Color(designSystemColor: .accentContentTertiary, palette: palette))
    }

    static func assistedOptOutDismiss(palette: ColorPalette) -> ButtonStateColors {
        .init(backgroundColor: Color(designSystemColor: .controlsFillPrimary, palette: palette),
              textColor: Color(designSystemColor: .textPrimary, palette: palette),
              hoveredBackgroundColor: Color(designSystemColor: .controlsFillSecondary, palette: palette),
              pressedBackgroundColor: Color(designSystemColor: .controlsFillTertiary, palette: palette),
              pressedTextColor: Color(designSystemColor: .textSecondary, palette: palette))
    }
}
