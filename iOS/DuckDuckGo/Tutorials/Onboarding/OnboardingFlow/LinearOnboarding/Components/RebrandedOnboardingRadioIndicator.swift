//
//  RebrandedOnboardingRadioIndicator.swift
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

import SwiftUI
import Onboarding
import DesignResourcesKitIcons

private enum RadioIndicatorMetrics {
    static let size: CGFloat = 24.0
    static let checkSize: CGFloat = 16.0
    static let strokeInset: CGFloat = 0.75
    static let strokeWidth: CGFloat = 1.5
    static let borderLightColor = Color.black.opacity(0.18)
    static let borderDarkColor = Color.white.opacity(0.18)
    static let unselectedForegroundColor = Color(designSystemColor: .controlsFillPrimary)
}

extension OnboardingRebranding {

    struct RadioIndicator: View {
        @Environment(\.colorScheme) private var colorScheme

        let isSelected: Bool
        let accentColor: Color

        var body: some View {
            Circle()
                .frame(width: RadioIndicatorMetrics.size, height: RadioIndicatorMetrics.size)
                .foregroundColor(foregroundColor)
                .overlay {
                    selectionOverlay
                }
        }

        @ViewBuilder
        private var selectionOverlay: some View {
            if isSelected {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.checkSolid)
                    .renderingMode(.template)
                    .resizable()
                    .background(
                        Circle()
                            .fill(checkboxFillerColor)
                            .frame(width: RadioIndicatorMetrics.checkSize, height: RadioIndicatorMetrics.checkSize)
                    )
                    .foregroundStyle(accentColor)
                    .frame(width: RadioIndicatorMetrics.size, height: RadioIndicatorMetrics.size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .inset(by: RadioIndicatorMetrics.strokeInset)
                    .stroke(checkboxStrokeColor, lineWidth: RadioIndicatorMetrics.strokeWidth)
            }
        }

        private var checkboxStrokeColor: Color {
            colorScheme == .light ? RadioIndicatorMetrics.borderLightColor : RadioIndicatorMetrics.borderDarkColor
        }

        private var checkboxFillerColor: Color {
            colorScheme == .light ? .white : Color(baseColor: .gray90)
        }

        private var foregroundColor: Color {
            if isSelected {
                accentColor
            } else {
                RadioIndicatorMetrics.unselectedForegroundColor
            }
        }
    }


}
