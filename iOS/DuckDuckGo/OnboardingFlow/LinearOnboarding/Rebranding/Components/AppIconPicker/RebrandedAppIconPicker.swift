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
        @StateObject private var viewModel = AppIconPickerViewModel()

        let layout = [GridItem(.adaptive(minimum: AppIconPickerMetrics.iconSize), spacing: AppIconPickerMetrics.spacing, alignment: .leading)]

        var body: some View {
            LazyVGrid(columns: layout, spacing: AppIconPickerMetrics.spacing) {
                ForEach(viewModel.items, id: \.icon) { item in
                    Image(uiImage: item.icon.mediumImage ?? UIImage())
                        .resizable()
                        .frame(width: AppIconPickerMetrics.iconSize, height: AppIconPickerMetrics.iconSize)
                        .cornerRadius(AppIconPickerMetrics.cornerRadius)
                        .overlay {
                            strokeOverlay(isSelected: item.isSelected)
                        }
                        .onTapGesture {
                            viewModel.changeApp(icon: item.icon)
                        }
                }
            }
        }

        @ViewBuilder
        private func strokeOverlay(isSelected: Bool) -> some View {
            if isSelected {
                RoundedRectangle(cornerRadius: AppIconPickerMetrics.cornerRadius)
                    .foregroundColor(.clear)
                    .frame(width: AppIconPickerMetrics.strokeFrameSize, height: AppIconPickerMetrics.strokeFrameSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppIconPickerMetrics.cornerRadius)
                            .inset(by: -AppIconPickerMetrics.strokeInset)
                            .stroke(.blue, lineWidth: AppIconPickerMetrics.strokeWidth)
                    )
            }
        }
    }

}

private enum AppIconPickerMetrics {
    static let cornerRadius: CGFloat = 13.0
    static let iconSize: CGFloat = 56.0
    static let spacing: CGFloat = 16.0
    static let strokeFrameSize: CGFloat = 60
    static let strokeWidth: CGFloat = 3
    static let strokeInset: CGFloat = 1.5
}
