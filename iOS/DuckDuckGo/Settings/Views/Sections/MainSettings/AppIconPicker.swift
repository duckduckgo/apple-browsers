//
//  AppIconPicker.swift
//  DuckDuckGo
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
import DuckUI
import DesignResourcesKit

private enum Metrics {
    static let cornerRadius: CGFloat = 16.0
    static let outerPadding: CGFloat = 32.0
    static let iconSize: CGFloat = 64.0
    static let spacing: CGFloat = 26.0
    static let strokeWidth: CGFloat = 2
    static let strokeInset: CGFloat = 3
}

struct SettingsAppIconPicker: View {
    private let onChange: ((AppIcon) -> Void)?

    init(onChange: ((AppIcon) -> Void)? = nil) {
        self.onChange = onChange
    }

    var body: some View {
        VStack {
            AppIconPicker(onChange: onChange)
            Spacer()
        }
        .padding(Metrics.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(designSystemColor: .background).ignoresSafeArea())
    }
}

struct AppIconPicker: View {
    @StateObject private var viewModel: AppIconPickerViewModel

    let layout = [GridItem(.adaptive(minimum: Metrics.iconSize), spacing: Metrics.spacing, alignment: .leading)]

    init(onChange: ((AppIcon) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: AppIconPickerViewModel(onChange: onChange))
    }

    var body: some View {
        LazyVGrid(columns: layout, spacing: Metrics.spacing) {
            ForEach(viewModel.items, id: \.icon) { item in
                Button {
                    viewModel.changeApp(icon: item.icon)
                } label: {
                    Image(uiImage: item.icon.mediumImage)
                        .overlay {
                            strokeOverlay(isSelected: item.isSelected)
                        }
                }
                .buttonStyle(AppIconButtonStyle())
                .accessibilityLabel(item.icon.accessibilityName)
                .accessibilityAddTraits(item.isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func strokeOverlay(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .inset(by: -Metrics.strokeInset)
                .stroke(Color(singleUseColor: .rebranding(.controlBorderTertiary)), lineWidth: Metrics.strokeWidth)
        }
    }
}

private struct AppIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    AppIconPicker()
}
