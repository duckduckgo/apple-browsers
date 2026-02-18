//
//  RebrandedAppIconPicker.swift
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
import DuckUI
import Onboarding

extension OnboardingRebranding.OnboardingView {

    struct AppIconPicker: View {

        @Environment(\.onboardingTheme) private var onboardingTheme

        private enum Metrics {
            // App icon
            static let cornerRadius: CGFloat = 13.0
            static let iconSize: CGFloat = 80.0
            // Color circle
            static let colorCircleSize: CGFloat = 36.0
            static let accentBorderWidth: CGFloat = 1.0
            static let borderWidth: CGFloat = 1.0
            // Selected circle
            static let strokeFrameSize: CGFloat = 40.0
            static let strokeWidth: CGFloat = 2.0
            static let strokeInset: CGFloat = 2.0
            // Layout
            static let spacing: CGFloat = 44.0
        }

        @StateObject private var viewModel = RebrandedAppIconPickerViewModel()

        var body: some View {
            VStack(spacing: Metrics.spacing) {
                Image(uiImage: viewModel.selectedIcon.mediumImage)
                    .resizable()
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .cornerRadius(Metrics.cornerRadius)
                HStack {
                    ForEach(viewModel.items, id: \.icon) { item in
                        colorCircle(color: item.color, isSelected: item.isSelected)
                            .onTapGesture {
                                viewModel.changeApp(icon: item.icon)
                            }
                    }
                }
            }
        }

        @ViewBuilder
        private func strokeOverlay(isSelected: Bool) -> some View {
            if isSelected {
                Circle()
                    .foregroundColor(.clear)
                    .frame(width: Metrics.strokeFrameSize, height: Metrics.strokeFrameSize)
                    .overlay(
                        Circle()
                            .inset(by: -Metrics.strokeInset)
                            .stroke(Color(singleUseColor: .rebranding(.accentPrimary)), lineWidth: Metrics.strokeWidth)
                    )
            }
        }

        @ViewBuilder
        private func colorCircle(color: Color, isSelected: Bool) -> some View {
            Circle()
                .frame(width: Metrics.colorCircleSize, height: Metrics.colorCircleSize)
                .foregroundStyle(.green)
                .overlay {
                    Circle()
                        .foregroundColor(color)
                        .frame(width: Metrics.colorCircleSize, height: Metrics.colorCircleSize)
                        .overlay(
                            Circle()
                                .inset(by: Metrics.borderWidth/2.0)
                                .stroke(Color(singleUseColor: .rebranding(.decorationSecondary)), lineWidth: Metrics.borderWidth)
                                .opacity(0.16)

                        )
                    strokeOverlay(isSelected: isSelected)
                }
        }
    }
}
