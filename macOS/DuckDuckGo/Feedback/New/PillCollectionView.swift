//
//  PillCollectionView.swift
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

struct Pill: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .systemLabel(color: isSelected || isHovered ? textColor : .textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 32)
        .buttonStyle(PillButtonStyle(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var textColor: Color {
        if isSelected {
            return colorScheme == .light ? .init(baseColor: .blue60) : .init(baseColor: .blue0)
        } else if isHovered {
            return colorScheme == .light ? .init(baseColor: .blue60) : .white.opacity(0.84)
        } else {
            return .textPrimary.opacity(0.84)
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor(configuration: configuration), lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        if isSelected {
            return colorScheme == .light ? .init(baseColor: .blue0) : .init(baseColor: .blue30).opacity(0.32)
        } else {
            if configuration.isPressed {
                return colorScheme == .light ? .init(baseColor: .blue0).opacity(0.56) : .white.opacity(0.09)
            } else if isHovered {
                return colorScheme == .light ? .init(baseColor: .blue0).opacity(0.48) : .white.opacity(0.06)
            } else {
                return Color(.controlBackgroundColor)
            }
        }
    }

    private func borderColor(configuration: Configuration) -> Color {
        if isSelected {
            return colorScheme == .light ? .init(baseColor: .blue40) : .init(baseColor: .blue20)
        } else {
            if configuration.isPressed {
                return colorScheme == .light ? .init(baseColor: .blue40).opacity(0.8) : .white.opacity(0.16)
            } else if isHovered {
                return colorScheme == .light ? .init(baseColor: .blue40).opacity(0.64) : .white.opacity(0.12)
            } else {
                return Color(.separatorColor)
            }
        }
    }
}

struct FlexibleView<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let availableWidth: CGFloat
    let data: Data
    let spacing: CGFloat
    let alignment: HorizontalAlignment
    let content: (Data.Element) -> Content
    @State private var elementsSize: [Data.Element: CGSize] = [:]

    var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            ForEach(computeRows(), id: \.self) { rowElements in
                HStack(spacing: spacing) {
                    ForEach(rowElements, id: \.self) { element in
                        content(element)
                            .fixedSize()
                            .readSize { size in
                                elementsSize[element] = size
                            }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    func computeRows() -> [[Data.Element]] {
        var rows: [[Data.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for element in data {
            let elementSize = elementsSize[element, default: CGSize(width: availableWidth, height: 1)]

            if currentRowWidth + elementSize.width + spacing > availableWidth {
                rows.append([element])
                currentRowWidth = elementSize.width
            } else {
                rows[rows.count - 1].append(element)
                currentRowWidth += elementSize.width + spacing
            }
        }

        return rows
    }
}
