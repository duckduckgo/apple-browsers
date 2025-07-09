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

// MARK: - Main View

/// A segmented picker view that displays items with images and text labels.
///
/// This view creates a horizontal segmented control where each segment contains
/// an image and text. The selected segment is highlighted with a sliding background
/// indicator that animates between selections.
///
/// Example usage:
/// ```swift
/// @State private var selectedItem: ImageSegmentedPickerItem
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
/// ImageSegmentedPickerView(
///     items: items,
///     selectedItem: $selectedItem
/// )
/// ```
public struct ImageSegmentedPickerView: View {
    private enum Constants {
        static let outerHeight: CGFloat = 40
        static let innerHeight: CGFloat = 36
        static let innerHorizontalPadding: CGFloat = 2
    }

    let items: [ImageSegmentedPickerItem]
    @Binding var selectedItem: ImageSegmentedPickerItem
    let configuration: ImageSegmentedPickerConfiguration
    let scrollProgress: CGFloat?

    @State private var currentOffset: CGFloat = 0

    /// Creates a new image segmented picker view.
    ///
    /// - Parameters:
    ///   - items: An array of items to display in the picker.
    ///   - selectedItem: A binding to the currently selected item.
    ///   - configuration: The configuration for customizing the picker's appearance. Defaults to `ImageSegmentedPickerConfiguration()`.
    ///   - scrollProgress: Optional scroll progress (0-1) to animate the toggle indicator alongside a scroll view. When provided, the indicator will interpolate between positions based on this progress.
    public init(
        items: [ImageSegmentedPickerItem],
        selectedItem: Binding<ImageSegmentedPickerItem>,
        configuration: ImageSegmentedPickerConfiguration = ImageSegmentedPickerConfiguration(),
        scrollProgress: CGFloat? = nil
    ) {
        self.items = items
        self._selectedItem = selectedItem
        self.configuration = configuration
        self.scrollProgress = scrollProgress
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: Constants.outerHeight / 2)
                    .fill(configuration.backgroundColor)

                RoundedRectangle(cornerRadius: Constants.innerHeight / 2)
                    .fill(configuration.selectedBackgroundColor)
                    .frame(width: geometry.size.width / CGFloat(items.count), height: Constants.innerHeight)
                    .offset(x: currentOffset)
                    .shadow(color: Color(designSystemColor: .shadowPrimary), radius: 0.5, x: 0, y: 0.5)
                    .onAppear {
                        currentOffset = calculateCurrentOffset(geometry: geometry)
                    }
                    .onChange(of: selectedItem.id) { _ in
                        // Only animate on selection change if not controlled by scroll progress
                        if scrollProgress == nil {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentOffset = calculateCurrentOffset(geometry: geometry)
                            }
                        } else {
                            // Update immediately without animation when controlled by scroll
                            currentOffset = calculateCurrentOffset(geometry: geometry)
                        }
                    }
                    .onChange(of: scrollProgress) { _ in
                        // Update offset based on scroll progress without animation
                        // (the scroll animation provides the smooth transition)
                        currentOffset = calculateCurrentOffset(geometry: geometry)
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
        .frame(height: Constants.outerHeight)
    }

    private func calculateCurrentOffset(geometry: GeometryProxy) -> CGFloat {
        if let progress = scrollProgress {
            return offsetForScrollProgress(progress, geometry: geometry)
        } else {
            return selectedOffset(geometry: geometry)
        }
    }

    private func offsetForScrollProgress(_ progress: CGFloat, geometry: GeometryProxy) -> CGFloat {
        guard items.count >= 2 else { return 0 }

        let firstOffset = offsetForItemIndex(0, geometry: geometry)
        let secondOffset = offsetForItemIndex(1, geometry: geometry)

        // Interpolate between first and second positions based on scroll progress
        return firstOffset + (secondOffset - firstOffset) * progress
    }

    private func offsetForItemIndex(_ index: Int, geometry: GeometryProxy) -> CGFloat {
        let buttonWidth = geometry.size.width / CGFloat(items.count)
        let baseOffset = CGFloat(index) * buttonWidth - (geometry.size.width / 2) + (buttonWidth / 2)

        let paddingAdjustment: CGFloat
        if index == 0 {
            paddingAdjustment = Constants.innerHorizontalPadding
        } else if index == items.count - 1 {
            paddingAdjustment = -Constants.innerHorizontalPadding
        } else {
            paddingAdjustment = 0
        }

        return baseOffset + paddingAdjustment
    }

    private func selectedOffset(geometry: GeometryProxy) -> CGFloat {
        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedItem.id }) else {
            return 0
        }

        return offsetForItemIndex(selectedIndex, geometry: geometry)
    }

    private func isItemInSelectedArea(itemIndex: Int, geometry: GeometryProxy, currentOffset: CGFloat) -> Bool {
        let buttonWidth = geometry.size.width / CGFloat(items.count)
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
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}

// MARK: - View Modifiers for Convenience

public extension ImageSegmentedPickerView {
    /// Creates a scroll-controlled image segmented picker view.
    ///
    /// This convenience method creates a picker that updates its indicator position
    /// based on scroll progress, making it appear connected to a UIScrollView.
    ///
    /// - Parameters:
    ///   - items: An array of items to display in the picker.
    ///   - selectedItem: A binding to the currently selected item.
    ///   - scrollProgress: The scroll progress (0-1) that controls the indicator position.
    ///   - configuration: The configuration for customizing the picker's appearance.
    /// - Returns: A scroll-controlled picker view.
    static func scrollControlled(
        items: [ImageSegmentedPickerItem],
        selectedItem: Binding<ImageSegmentedPickerItem>,
        scrollProgress: CGFloat,
        configuration: ImageSegmentedPickerConfiguration = ImageSegmentedPickerConfiguration()
    ) -> ImageSegmentedPickerView {
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: selectedItem,
            configuration: configuration,
            scrollProgress: scrollProgress
        )
    }

    /// Sets the font for the picker's text labels.
    ///
    /// - Parameter font: The font to apply to text labels.
    /// - Returns: A picker view with the updated font configuration.
    func pickerFont(_ font: Font) -> ImageSegmentedPickerView {
        var modifiedConfiguration = configuration
        modifiedConfiguration.font = font
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: $selectedItem,
            configuration: modifiedConfiguration,
            scrollProgress: scrollProgress
        )
    }

    /// Sets the text colors for selected and unselected states.
    ///
    /// - Parameters:
    ///   - selected: The color for selected item text.
    ///   - unselected: The color for unselected item text.
    /// - Returns: A picker view with the updated text color configuration.
    func pickerTextColors(selected: Color, unselected: Color) -> ImageSegmentedPickerView {
        var modifiedConfiguration = configuration
        modifiedConfiguration.selectedTextColor = selected
        modifiedConfiguration.unselectedTextColor = unselected
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: $selectedItem,
            configuration: modifiedConfiguration,
            scrollProgress: scrollProgress
        )
    }

    /// Sets the background colors for the picker and selected indicator.
    ///
    /// - Parameters:
    ///   - background: The overall background color of the picker.
    ///   - selectedBackground: The background color of the selected item indicator.
    /// - Returns: A picker view with the updated background color configuration.
    func pickerBackgroundColors(background: Color, selectedBackground: Color) -> ImageSegmentedPickerView {
        var modifiedConfiguration = configuration
        modifiedConfiguration.backgroundColor = background
        modifiedConfiguration.selectedBackgroundColor = selectedBackground
        return ImageSegmentedPickerView(
            items: items,
            selectedItem: $selectedItem,
            configuration: modifiedConfiguration,
            scrollProgress: scrollProgress
        )
    }
}

// MARK: - Example Usage

private struct ImageSegmentedPickerExample: View {
    @State private var selectedItem: ImageSegmentedPickerItem
    @State private var scrollProgress: CGFloat = 0.0
    private let items: [ImageSegmentedPickerItem]

    init() {
        let defaultItems = [
            ImageSegmentedPickerItem(
                text: "Chat",
                selectedImage: Image(systemName: "message.fill"),
                unselectedImage: Image(systemName: "message")
            ),
            ImageSegmentedPickerItem(
                text: "Search",
                selectedImage: Image(systemName: "magnifyingglass"),
                unselectedImage: Image(systemName: "magnifyingglass")
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
                Text("Scroll-Controlled Toggle")
                    .font(.headline)

                ImageSegmentedPickerView.scrollControlled(
                    items: items,
                    selectedItem: $selectedItem,
                    scrollProgress: scrollProgress
                )
                .padding(.horizontal)

                // Simulate scroll progress with a slider
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scroll Progress: \(scrollProgress, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: $scrollProgress, in: 0...1) {
                        Text("Progress")
                    }
                    .onChange(of: scrollProgress) { progress in
                        // Update selected item based on progress
                        // This simulates what would happen in a real scroll view
                        let newIndex = progress < 0.5 ? 0 : 1
                        selectedItem = items[newIndex]
                    }
                }
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

            Text("Usage with UIScrollView:")
                .font(.headline)
                .padding(.horizontal)

            Text("""
                // In your scroll view delegate:
                func scrollViewDidScroll(_ scrollView: UIScrollView) {
                    let progress = scrollView.contentOffset.x / scrollView.contentSize.width
                    // Update your scroll progress state
                }

                // Then use:
                ImageSegmentedPickerView.scrollControlled(
                    items: items,
                    selectedItem: $selectedItem,
                    scrollProgress: scrollProgress
                )
                """)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)

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
