//
//  ImageSegmentedPickerView.swift
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

#if os(iOS)

import SwiftUI
import DesignResourcesKit

// MARK: - Configuration

public struct ImageSegmentedPickerConfiguration {
    public var font: Font
    public var selectedTextColor: Color
    public var unselectedTextColor: Color
    public var backgroundColor: Color
    public var selectedBackgroundColor: Color

    public init(
        font: Font = .system(size: 16, weight: .medium),
        selectedTextColor: Color = .init(designSystemColor: .textPrimary),
        unselectedTextColor: Color = .init(designSystemColor: .textPrimary),
        backgroundColor: Color = .init(designSystemColor: .surface),
        selectedBackgroundColor: Color = .init(designSystemColor: .background),
    ) {
        self.font = font
        self.selectedTextColor = selectedTextColor
        self.unselectedTextColor = unselectedTextColor
        self.backgroundColor = backgroundColor
        self.selectedBackgroundColor = selectedBackgroundColor
    }
}

// MARK: - Main View

public struct ImageSegmentedPickerView: View {
    private enum Constants {
        static let outterHeight: CGFloat = 36
        static let innerHeight: CGFloat = 32
        static let innerHorizontalPadding: CGFloat = 2
    }

    let items: [ImageSegmentedPickerItem]
    @Binding var selectedItem: ImageSegmentedPickerItem
    let configuration: ImageSegmentedPickerConfiguration

    @State private var currentOffset: CGFloat = 0

    // Public initializer with default configuration
    public init(
        items: [ImageSegmentedPickerItem],
        selectedItem: Binding<ImageSegmentedPickerItem>,
        configuration: ImageSegmentedPickerConfiguration = ImageSegmentedPickerConfiguration()
    ) {
        self.items = items
        self._selectedItem = selectedItem
        self.configuration = configuration
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: Constants.outterHeight / 2)
                    .fill(configuration.backgroundColor)

                RoundedRectangle(cornerRadius: Constants.innerHeight / 2)
                    .fill(configuration.selectedBackgroundColor)
                    .frame(width: geometry.size.width / CGFloat(items.count), height: Constants.innerHeight)
                    .offset(x: currentOffset)
                    .shadow(color: Color.black.opacity(0.10), radius: 0.5, x: 0, y: 0.5)
                    .onAppear {
                        currentOffset = selectedOffset(geometry: geometry)
                    }
                    .onChange(of: selectedItem.id) { _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentOffset = selectedOffset(geometry: geometry)
                        }
                    }

                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isInSelectedArea = isItemInSelectedArea(itemIndex: index, geometry: geometry, currentOffset: currentOffset)

                        CustomPickerButton(
                            item: item,
                            isSelected: isInSelectedArea,
                            configuration: configuration) {
                            selectedItem = item
                        }
                        .frame(width: geometry.size.width / CGFloat(items.count))
                    }
                }
            }
        }
        .frame(height: Constants.outterHeight)
    }

    private func selectedOffset(geometry: GeometryProxy) -> CGFloat {
        let buttonWidth = geometry.size.width / CGFloat(items.count)
        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedItem.id }) else {
            return 0
        }

        let baseOffset = CGFloat(selectedIndex) * buttonWidth - (geometry.size.width / 2) + (buttonWidth / 2)

        let paddingAdjustment: CGFloat
        if selectedIndex == 0 {
            paddingAdjustment = Constants.innerHorizontalPadding
        } else if selectedIndex == items.count - 1 {
            paddingAdjustment = -Constants.innerHorizontalPadding
        } else {
            paddingAdjustment = 0
        }

        return baseOffset + paddingAdjustment
    }

    private func isItemInSelectedArea(itemIndex: Int, geometry: GeometryProxy, currentOffset: CGFloat) -> Bool {
        let buttonWidth = geometry.size.width / CGFloat(items.count)
        let selectorWidth = buttonWidth - (Constants.innerHorizontalPadding * 2)

        // Calculate the actual position of the blue rectangle
        let selectorCenter = currentOffset + (geometry.size.width / 2)
        let selectorLeft = selectorCenter - (selectorWidth / 2)
        let selectorRight = selectorCenter + (selectorWidth / 2)

        // Calculate the position of this item
        let itemLeft = CGFloat(itemIndex) * buttonWidth
        let itemRight = itemLeft + buttonWidth

        // Check if there's any overlap between the selector and the item
        return selectorLeft < itemRight && selectorRight > itemLeft
    }
}

// MARK: - Private Components

private struct CustomPickerButton: View {
    let item: ImageSegmentedPickerItem
    let isSelected: Bool
    let configuration: ImageSegmentedPickerConfiguration
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                (isSelected ? item.selectedImage : item.unselectedImage)
                    .font(configuration.font)
                    .foregroundColor(isSelected ? configuration.selectedTextColor : configuration.unselectedTextColor)

                Text(item.text)
                    .font(configuration.font)
                    .foregroundColor(isSelected ? configuration.selectedTextColor : configuration.unselectedTextColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Data Model

public struct ImageSegmentedPickerItem: Identifiable, Hashable {
    public let id = UUID()
    public let text: String
    public let selectedImage: Image
    public let unselectedImage: Image

    public init(text: String, selectedImage: Image, unselectedImage: Image) {
        self.text = text
        self.selectedImage = selectedImage
        self.unselectedImage = unselectedImage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
    }

    public static func == (lhs: ImageSegmentedPickerItem, rhs: ImageSegmentedPickerItem) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}

// MARK: - View Modifiers for Convenience

public extension ImageSegmentedPickerView {
    func pickerFont(_ font: Font) -> ImageSegmentedPickerView {
        var modifiedConfiguration = configuration
        modifiedConfiguration.font = font
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: $selectedItem,
            configuration: modifiedConfiguration
        )
    }

    func pickerTextColors(selected: Color, unselected: Color) -> ImageSegmentedPickerView {
        var modifiedConfiguration = configuration
        modifiedConfiguration.selectedTextColor = selected
        modifiedConfiguration.unselectedTextColor = unselected
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: $selectedItem,
            configuration: modifiedConfiguration
        )
    }

    func pickerBackgroundColors(background: Color, selectedBackground: Color) -> ImageSegmentedPickerView {
        var modifiedConfiguration = configuration
        modifiedConfiguration.backgroundColor = background
        modifiedConfiguration.selectedBackgroundColor = selectedBackground
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: $selectedItem,
            configuration: modifiedConfiguration
        )
    }
}

// MARK: - Example Usage

private struct ImageSegmentedPickerExample: View {
    @State private var selectedItem: ImageSegmentedPickerItem
    private let items: [ImageSegmentedPickerItem]

    init() {
        let defaultItems = [
            ImageSegmentedPickerItem(
                text: "List",
                selectedImage: Image(systemName: "list.bullet"),
                unselectedImage: Image(systemName: "list.bullet")
            ),
            ImageSegmentedPickerItem(
                text: "Grid",
                selectedImage: Image(systemName: "square.grid.2x2.fill"),
                unselectedImage: Image(systemName: "square.grid.2x2")
            )
        ]
        self.items = defaultItems
        self._selectedItem = State(initialValue: defaultItems[0])
    }

    var body: some View {
        VStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Configuration")
                    .font(.headline)

                ImageSegmentedPickerView(
                    items: items,
                    selectedItem: $selectedItem
                )
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Configuration (via initializer)")
                    .font(.headline)

                ImageSegmentedPickerView(
                    items: items,
                    selectedItem: $selectedItem,
                    configuration: ImageSegmentedPickerConfiguration(
                        font: .system(size: 14, weight: .bold),
                        selectedTextColor: .white,
                        unselectedTextColor: .gray,
                        backgroundColor: Color(UIColor.secondarySystemBackground),
                        selectedBackgroundColor: .purple
                    )
                )
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom Configuration (via modifiers)")
                    .font(.headline)

                ImageSegmentedPickerView(
                    items: items,
                    selectedItem: $selectedItem
                )
                .pickerFont(.system(size: 18, weight: .semibold))
                .pickerTextColors(selected: .yellow, unselected: .blue)
                .pickerBackgroundColors(
                    background: Color(UIColor.systemGray5),
                    selectedBackground: .green
                )
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dark Theme")
                    .font(.headline)

                ImageSegmentedPickerView(
                    items: items,
                    selectedItem: $selectedItem,
                    configuration: ImageSegmentedPickerConfiguration(
                        font: .system(size: 15, weight: .medium, design: .rounded),
                        selectedTextColor: .black,
                        unselectedTextColor: Color(UIColor.systemGray3),
                        backgroundColor: .black,
                        selectedBackgroundColor: .white
                    )
                )
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.vertical)
    }
}

#Preview {
    ImageSegmentedPickerExample()
        .padding()
}

#endif
