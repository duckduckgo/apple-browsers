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

/// Configuration options for customizing the appearance of an `ImageSegmentedPickerView`.
///
/// Use this structure to define the visual properties of the segmented picker,
/// including fonts, colors, and backgrounds.
public struct ImageSegmentedPickerConfiguration {
    public var font: Font
    public var selectedTextColor: Color
    public var unselectedTextColor: Color
    public var backgroundColor: Color
    public var selectedBackgroundColor: Color

    /// Creates a new configuration for the image segmented picker.
    ///
    /// - Parameters:
    ///   - font: The font for text labels. Defaults to system font with size 16 and medium weight.
    ///   - selectedTextColor: The text color for selected items. Defaults to primary text color.
    ///   - unselectedTextColor: The text color for unselected items. Defaults to primary text color.
    ///   - backgroundColor: The picker's background color. Defaults to backdrop color.
    ///   - selectedBackgroundColor: The selected indicator's background color. Defaults to tertiary background color.
    public init(
        font: Font = .system(size: 16, weight: .medium),
        selectedTextColor: Color = .init(designSystemColor: .textPrimary),
        unselectedTextColor: Color = .init(designSystemColor: .textPrimary),
        backgroundColor: Color = .init(designSystemColor: .backdrop),
        selectedBackgroundColor: Color = .init(designSystemColor: .backgroundTertiary)
    ) {
        self.font = font
        self.selectedTextColor = selectedTextColor
        self.unselectedTextColor = unselectedTextColor
        self.backgroundColor = backgroundColor
        self.selectedBackgroundColor = selectedBackgroundColor
    }
}

// MARK: - ViewModel

/// ViewModel for managing the state and configuration of an ImageSegmentedPickerView.
public class ImageSegmentedPickerViewModel: ObservableObject {
    let items: [ImageSegmentedPickerItem]
    @Published public var selectedItem: ImageSegmentedPickerItem
    let configuration: ImageSegmentedPickerConfiguration
    @Published public var scrollProgress: CGFloat?

    /// Creates a new ViewModel for the image segmented picker.
    ///
    /// - Parameters:
    ///   - items: An array of items to display in the picker.
    ///   - selectedItem: The initially selected item.
    ///   - configuration: The configuration for customizing the picker's appearance.
    ///   - scrollProgress: Optional scroll progress (0-1) to animate the toggle indicator.
    public init(
        items: [ImageSegmentedPickerItem],
        selectedItem: ImageSegmentedPickerItem,
        configuration: ImageSegmentedPickerConfiguration = ImageSegmentedPickerConfiguration(),
        scrollProgress: CGFloat? = nil
    ) {
        self.items = items
        self.selectedItem = selectedItem
        self.configuration = configuration
        self.scrollProgress = scrollProgress
    }

    /// Updates the selected item.
    ///
    /// - Parameter item: The item to select.
    public func selectItem(_ item: ImageSegmentedPickerItem) {
        selectedItem = item
    }

    /// Updates the scroll progress.
    ///
    /// - Parameter progress: The scroll progress (0-1).
    public func updateScrollProgress(_ progress: CGFloat?) {
        scrollProgress = progress
    }
}

// MARK: - Main View

/// A segmented picker view that displays items with images and text labels.
///
/// This view creates a horizontal segmented control where each segment contains
/// an image and text. The selected segment is highlighted with a sliding background
/// indicator that animates between selections.
///
/// Example usage:
/// ```swift
/// let items = [
///     ImageSegmentedPickerItem(
///         text: "List",
///         selectedImage: Image(systemName: "list.bullet"),
///         unselectedImage: Image(systemName: "list.bullet")
///     ),
///     ImageSegmentedPickerItem(
///         text: "Grid",
///         selectedImage: Image(systemName: "square.grid.2x2.fill"),
///         unselectedImage: Image(systemName: "square.grid.2x2")
///     )
/// ]
///
/// let viewModel = ImageSegmentedPickerViewModel(
///     items: items,
///     selectedItem: items[0]
/// )
///
/// ImageSegmentedPickerView(viewModel: viewModel)
/// ```
public struct ImageSegmentedPickerView: View {
    private enum Constants {
        static let outerHeight: CGFloat = 40
        static let innerHeight: CGFloat = 36
        static let innerHorizontalPadding: CGFloat = 2
    }

    @ObservedObject private var viewModel: ImageSegmentedPickerViewModel
    @State private var currentOffset: CGFloat = 0

    /// Creates a new image segmented picker view with a ViewModel.
    ///
    /// - Parameter viewModel: The ViewModel managing the picker's state and configuration.
    public init(viewModel: ImageSegmentedPickerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: Constants.outerHeight / 2)
                    .fill(viewModel.configuration.backgroundColor)

                RoundedRectangle(cornerRadius: Constants.innerHeight / 2)
                    .fill(viewModel.configuration.selectedBackgroundColor)
                    .frame(width: geo.size.width / CGFloat(viewModel.items.count), height: Constants.innerHeight)
                    .offset(x: currentOffset)
                    .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 0.5, x: 0, y: 0.5)
                    .animation(.easeInOut(duration: 0.2), value: currentOffset)

                HStack(spacing: 0) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        let isInSelectedArea = isItemInSelectedArea(itemIndex: index, geometry: geo, currentOffset: currentOffset)

                        CustomPickerButton(
                            item: item,
                            isSelected: isInSelectedArea,
                            configuration: viewModel.configuration) {
                            viewModel.selectItem(item)
                        }
                        .frame(width: geo.size.width / CGFloat(viewModel.items.count))
                    }
                }
            }
            .onAppear {
                currentOffset = calculateCurrentOffset(geometry: geo)
            }
            .onChange(of: viewModel.selectedItem.id) { _ in
                if viewModel.scrollProgress == nil {
                    currentOffset = calculateCurrentOffset(geometry: geo)
                }
            }
            .onChange(of: viewModel.scrollProgress) { _ in
                if viewModel.scrollProgress != nil {
                    currentOffset = calculateCurrentOffset(geometry: geo)
                }
            }
        }
        .frame(height: Constants.outerHeight)
    }

    private func calculateCurrentOffset(geometry: GeometryProxy) -> CGFloat {
        if let progress = viewModel.scrollProgress {
            return offsetForScrollProgress(progress, geometry: geometry)
        } else {
            return selectedOffset(geometry: geometry)
        }
    }

    private func offsetForScrollProgress(_ progress: CGFloat, geometry: GeometryProxy) -> CGFloat {
        guard viewModel.items.count >= 2 else { return 0 }

        let firstOffset = offsetForItemIndex(0, geometry: geometry)
        let secondOffset = offsetForItemIndex(1, geometry: geometry)

        // Interpolate between first and second positions based on scroll progress
        return firstOffset + (secondOffset - firstOffset) * progress
    }

    private func offsetForItemIndex(_ index: Int, geometry: GeometryProxy) -> CGFloat {
        let buttonWidth = geometry.size.width / CGFloat(viewModel.items.count)
        let baseOffset = CGFloat(index) * buttonWidth - (geometry.size.width / 2) + (buttonWidth / 2)

        let paddingAdjustment: CGFloat
        if index == 0 {
            paddingAdjustment = Constants.innerHorizontalPadding
        } else if index == viewModel.items.count - 1 {
            paddingAdjustment = -Constants.innerHorizontalPadding
        } else {
            paddingAdjustment = 0
        }

        return baseOffset + paddingAdjustment
    }

    private func selectedOffset(geometry: GeometryProxy) -> CGFloat {
        guard let selectedIndex = viewModel.items.firstIndex(where: { $0.id == viewModel.selectedItem.id }) else {
            return 0
        }

        return offsetForItemIndex(selectedIndex, geometry: geometry)
    }

    private func isItemInSelectedArea(itemIndex: Int, geometry: GeometryProxy, currentOffset: CGFloat) -> Bool {
        let buttonWidth = geometry.size.width / CGFloat(viewModel.items.count)
        let selectorWidth = buttonWidth - (Constants.innerHorizontalPadding * 2)

        let selectorCenter = currentOffset + (geometry.size.width / 2)
        let selectorLeft = selectorCenter - (selectorWidth / 2)
        let selectorRight = selectorCenter + (selectorWidth / 2)

        let itemLeft = CGFloat(itemIndex) * buttonWidth
        let itemRight = itemLeft + buttonWidth

        // Calculate the overlap between selector and item
        let overlapLeft = max(selectorLeft, itemLeft)
        let overlapRight = min(selectorRight, itemRight)
        let overlapWidth = max(0, overlapRight - overlapLeft)

        // Only consider item selected if overlay is more than 50% on top of it
        let overlapPercentage = overlapWidth / selectorWidth
        return overlapPercentage > 0.5
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
            HStack(spacing: 6) {
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

/// Represents an item in an `ImageSegmentedPickerView`.
///
/// Each item contains text and images for both selected and unselected states.
/// The picker automatically switches between these images based on the selection state.
public struct ImageSegmentedPickerItem: Identifiable, Hashable {
    public let id = UUID()
    public let text: String
    public let selectedImage: Image
    public let unselectedImage: Image

    /// Creates a new picker item.
    ///
    /// - Parameters:
    ///   - text: The text label for the item.
    ///   - selectedImage: The image to display when selected.
    ///   - unselectedImage: The image to display when not selected.
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
        lhs.id == rhs.id
    }
}

#endif
