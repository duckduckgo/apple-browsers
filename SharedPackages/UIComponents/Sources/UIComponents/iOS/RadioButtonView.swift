//
//  RadioButtonView.swift
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
import DesignResourcesKitIcons

// MARK: - Configuration

/// Layout orientation for the radio button group.
public enum RadioButtonLayout {
    case vertical
    case horizontal
}

/// Configuration options for customizing the appearance of a `RadioButtonView`.
///
/// Use this structure to define the visual properties of the radio buttons,
/// including fonts, colors, borders, spacing, and layout.
public struct RadioButtonConfiguration {
    public var font: Font
    public var selectedTextColor: Color
    public var unselectedTextColor: Color
    public var selectedBackgroundColor: Color
    public var unselectedBackgroundColor: Color
    public var selectedBorderColor: Color
    public var unselectedBorderColor: Color
    public var selectedCheckboxColor: Color
    public var unselectedCheckboxColor: Color
    public var selectedCheckboxImage: Image
    public var unselectedCheckboxImage: Image
    public var borderWidth: CGFloat
    public var cornerRadius: CGFloat
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var spacing: CGFloat
    public var checkboxSize: CGFloat
    public var layout: RadioButtonLayout
    public var buttonSpacing: CGFloat

    public init(
        font: Font = Font(UIFont.daxCaption().withSize(13)),
        selectedTextColor: Color = .init(designSystemColor: .textLink),
        unselectedTextColor: Color = .init(designSystemColor: .textSecondary),
        selectedBackgroundColor: Color = .init(designSystemColor: .accent).opacity(0.2),
        unselectedBackgroundColor: Color = .clear,
        selectedBorderColor: Color = .init(designSystemColor: .accent),
        unselectedBorderColor: Color = .init(designSystemColor: .lines),
        selectedCheckboxColor: Color = .init(designSystemColor: .accent),
        unselectedCheckboxColor: Color = .gray.opacity(0.6),
        selectedCheckboxImage: Image = Image(uiImage: DesignSystemImages.Glyphs.Size24.checkRecolorable),
        unselectedCheckboxImage: Image = Image(uiImage: DesignSystemImages.Glyphs.Size24.shapeCircle),
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 12,
        horizontalPadding: CGFloat = 16,
        verticalPadding: CGFloat = 12,
        spacing: CGFloat = 6,
        checkboxSize: CGFloat = 24,
        layout: RadioButtonLayout = .vertical,
        buttonSpacing: CGFloat = 8
    ) {
        self.font = font
        self.selectedTextColor = selectedTextColor
        self.unselectedTextColor = unselectedTextColor
        self.selectedBackgroundColor = selectedBackgroundColor
        self.unselectedBackgroundColor = unselectedBackgroundColor
        self.selectedBorderColor = selectedBorderColor
        self.unselectedBorderColor = unselectedBorderColor
        self.selectedCheckboxColor = selectedCheckboxColor
        self.unselectedCheckboxColor = unselectedCheckboxColor
        self.selectedCheckboxImage = selectedCheckboxImage
        self.unselectedCheckboxImage = unselectedCheckboxImage
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
        self.spacing = spacing
        self.checkboxSize = checkboxSize
        self.layout = layout
        self.buttonSpacing = buttonSpacing
    }
}

// MARK: - ViewModel

/// ViewModel for managing the state and configuration of a RadioButtonView.
public class RadioButtonViewModel: ObservableObject {
    let items: [RadioButtonItem]
    @Published public var selectedItem: RadioButtonItem?
    let configuration: RadioButtonConfiguration

    /// Creates a new ViewModel for the radio button view.
    ///
    /// - Parameters:
    ///   - items: An array of items to display in the radio button group.
    ///   - selectedItem: The initially selected item (optional).
    ///   - configuration: The configuration for customizing the radio buttons' appearance.
    public init(
        items: [RadioButtonItem],
        selectedItem: RadioButtonItem? = nil,
        configuration: RadioButtonConfiguration = RadioButtonConfiguration()
    ) {
        self.items = items
        self.selectedItem = selectedItem
        self.configuration = configuration
    }

    public func selectItem(_ item: RadioButtonItem) {
        selectedItem = item
    }
}

// MARK: - Main View

/// A radio button view that displays a group of selectable items with checkboxes and text labels.
///
/// This view creates a vertical list of radio buttons where only one can be selected at a time.
/// Each button contains a checkbox and text label with customizable appearance.
///
/// Example usage:
/// ```swift
/// let items = [
///     RadioButtonItem(text: "Option 1"),
///     RadioButtonItem(text: "Option 2"),
///     RadioButtonItem(text: "Option 3")
/// ]
///
/// let viewModel = RadioButtonViewModel(
///     items: items,
///     selectedItem: items[0]
/// )
///
/// RadioButtonView(viewModel: viewModel)
/// ```
public struct RadioButtonView: View {
    @ObservedObject private var viewModel: RadioButtonViewModel

    /// Creates a new radio button view with a ViewModel.
    ///
    /// - Parameter viewModel: The ViewModel managing the radio buttons' state and configuration.
    public init(viewModel: RadioButtonViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Group {
            switch viewModel.configuration.layout {
            case .vertical:
                VStack(alignment: .leading, spacing: viewModel.configuration.buttonSpacing) {
                    ForEach(viewModel.items, id: \.id) { item in
                        RadioButtonRow(
                            item: item,
                            isSelected: viewModel.selectedItem?.id == item.id,
                            configuration: viewModel.configuration
                        ) {
                            viewModel.selectItem(item)
                        }
                    }
                }
            case .horizontal:
                HStack(alignment: .top, spacing: viewModel.configuration.buttonSpacing) {
                    ForEach(viewModel.items, id: \.id) { item in
                        RadioButtonRow(
                            item: item,
                            isSelected: viewModel.selectedItem?.id == item.id,
                            configuration: viewModel.configuration
                        ) {
                            viewModel.selectItem(item)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Private Components

private struct RadioButtonRow: View {
    let item: RadioButtonItem
    let isSelected: Bool
    let configuration: RadioButtonConfiguration
    let action: () -> Void

    var body: some View {
        HStack(spacing: configuration.spacing) {
            if configuration.layout == .vertical {
                verticalRowContent
            } else {
                horizontalRowContent
            }
        }
        .padding(.horizontal, configuration.layout == .vertical ? configuration.horizontalPadding : 0)
        .padding(.vertical, configuration.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: configuration.cornerRadius)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: configuration.cornerRadius)
                .stroke(borderColor, lineWidth: configuration.borderWidth)
        )
        .contentShape(Rectangle()) // This makes the entire area tappable
        .onTapGesture {
            action()
        }
        .animation(.easeInOut(duration: 0.1), value: isSelected)
    }

    private var backgroundColor: Color {
        isSelected ? configuration.selectedBackgroundColor : configuration.unselectedBackgroundColor
    }

    private var borderColor: Color {
        isSelected ? configuration.selectedBorderColor : configuration.unselectedBorderColor
    }

    @ViewBuilder
    private var verticalRowContent: some View {
        Text(item.text)
            .font(configuration.font)
            .foregroundColor(isSelected ? configuration.selectedTextColor : configuration.unselectedTextColor)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

        (isSelected ? configuration.selectedCheckboxImage : configuration.unselectedCheckboxImage)
            .resizable()
            .renderingMode(.template)
            .font(.system(size: configuration.checkboxSize))
            .foregroundColor(isSelected ? configuration.selectedCheckboxColor : configuration.unselectedCheckboxColor)
            .frame(width: configuration.checkboxSize, height: configuration.checkboxSize)
            .flexibleFrame(horizontal: false, vertical: false)
    }

    @ViewBuilder
    private var horizontalRowContent: some View {
        Spacer()

        (isSelected ? configuration.selectedCheckboxImage : configuration.unselectedCheckboxImage)
            .resizable()
            .renderingMode(.template)
            .font(.system(size: configuration.checkboxSize))
            .foregroundColor(isSelected ? configuration.selectedCheckboxColor : configuration.unselectedCheckboxColor)
            .frame(width: configuration.checkboxSize, height: configuration.checkboxSize)
            .flexibleFrame(horizontal: false, vertical: false)

        Text(item.text)
            .minimumScaleFactor(0.8)
            .lineLimit(1)
            .font(configuration.font)
            .foregroundColor(isSelected ? configuration.selectedTextColor : configuration.unselectedTextColor)
            .multilineTextAlignment(.center)
            .truncationMode(.tail)

        Spacer()
    }
}

private extension View {
    func flexibleFrame(horizontal: Bool, vertical: Bool) -> some View {
        if horizontal && vertical {
            return AnyView(self.frame(maxWidth: .infinity, maxHeight: .infinity))
        } else if horizontal {
            return AnyView(self.frame(maxWidth: .infinity))
        } else if vertical {
            return AnyView(self.frame(maxHeight: .infinity))
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - Data Model

/// Represents an item in a `RadioButtonView`.
///
/// Each item contains text and an optional identifier for tracking selections.
public struct RadioButtonItem: Identifiable, Hashable {
    public let id = UUID()
    public let text: String
    public let value: AnyHashable?

    /// Creates a new radio button item.
    ///
    /// - Parameters:
    ///   - text: The text label for the item.
    ///   - value: An optional value associated with the item for data binding.
    public init(text: String, value: AnyHashable? = nil) {
        self.text = text
        self.value = value
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(text)
        if let value = value {
            hasher.combine(value)
        }
    }

    public static func == (lhs: RadioButtonItem, rhs: RadioButtonItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Convenience Initializers

public extension RadioButtonView {
    /// Creates a radio button view with an array of text strings.
    ///
    /// - Parameters:
    ///   - options: An array of text strings to create radio button items.
    ///   - selectedIndex: The index of the initially selected item (optional).
    ///   - configuration: The configuration for customizing appearance.
    ///   - onSelectionChanged: Callback when selection changes, providing the selected item and its index.
    init(
        options: [String],
        selectedIndex: Int? = nil,
        configuration: RadioButtonConfiguration = RadioButtonConfiguration(),
        onSelectionChanged: @escaping (RadioButtonItem?, Int?) -> Void = { _, _ in }
    ) {
        let items = options.map { RadioButtonItem(text: $0) }
        let selectedItem = selectedIndex.flatMap { index in
            items.indices.contains(index) ? items[index] : nil
        }

        let viewModel = CallbackRadioButtonViewModel(
            items: items,
            selectedItem: selectedItem,
            configuration: configuration,
            onSelectionChanged: onSelectionChanged
        )

        self.viewModel = viewModel
    }
}

// MARK: - Private ViewModel with Callback

private class CallbackRadioButtonViewModel: RadioButtonViewModel {
    private let onSelectionChanged: (RadioButtonItem?, Int?) -> Void

    init(
        items: [RadioButtonItem],
        selectedItem: RadioButtonItem? = nil,
        configuration: RadioButtonConfiguration = RadioButtonConfiguration(),
        onSelectionChanged: @escaping (RadioButtonItem?, Int?) -> Void
    ) {
        self.onSelectionChanged = onSelectionChanged
        super.init(
            items: items,
            selectedItem: selectedItem,
            configuration: configuration,
        )
    }

    override func selectItem(_ item: RadioButtonItem) {
        super.selectItem(item)

        let selectedIndex = selectedItem.flatMap { selected in
            items.firstIndex { $0.id == selected.id }
        }
        onSelectionChanged(selectedItem, selectedIndex)
    }
}

// MARK: - Previews

#Preview("Basic Radio Buttons") {
    VStack(spacing: 20) {
        RadioButtonView(
            options: ["Option 1", "Option 2"],
            selectedIndex: 0
        )

        Divider()

        RadioButtonView(
            options: ["Search Only", "Search & Duck.ai"],
            selectedIndex: 0,
            configuration: RadioButtonConfiguration(
                layout: .horizontal,

            )
        )
    }
    .padding()
}

#Preview("Custom Styled") {
    VStack(spacing: 20) {
        RadioButtonView(
            options: ["Small", "Medium", "Large"],
            selectedIndex: 1,
            configuration: RadioButtonConfiguration(
                font: .system(size: 18, weight: .semibold),
                selectedTextColor: .white,
                unselectedTextColor: .black,
                selectedBackgroundColor: .green,
                unselectedBackgroundColor: .gray.opacity(0.1),
                selectedBorderColor: .green,
                unselectedBorderColor: .gray.opacity(0.4),
                selectedCheckboxColor: .white,
                unselectedCheckboxColor: .gray,
                cornerRadius: 12,
                horizontalPadding: 20,
                verticalPadding: 16,
                spacing: 12,
                checkboxSize: 24
            )
        )
    }
    .padding()
}

#Preview("Custom Images") {
    VStack(spacing: 20) {
        Text("Favorites")
            .font(.headline)

        RadioButtonView(
            options: ["Heart", "Star", "Bookmark", "Flag"],
            selectedIndex: 0,
            configuration: RadioButtonConfiguration(
                selectedTextColor: .pink,
                unselectedTextColor: .gray,
                selectedBackgroundColor: .pink.opacity(0.1),
                selectedBorderColor: .pink,
                selectedCheckboxColor: .pink,
                unselectedCheckboxColor: .gray.opacity(0.5),
                selectedCheckboxImage: Image(systemName: "heart.fill"),
                unselectedCheckboxImage: Image(systemName: "heart"),
                checkboxSize: 24
            )
        )
    }
    .padding()
}

#Preview("All Layouts") {
    ScrollView {
        VStack(alignment: .leading, spacing: 30) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Vertical Layout")
                    .font(.title2)
                    .fontWeight(.bold)

                RadioButtonView(
                    options: ["Option A", "Option B", "Option C"],
                    selectedIndex: 1
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Horizontal Layout")
                    .font(.title2)
                    .fontWeight(.bold)

                RadioButtonView(
                    options: ["Yes", "No", "Maybe"],
                    selectedIndex: 0,
                    configuration: RadioButtonConfiguration(
                        layout: .horizontal,
                        buttonSpacing: 12
                    )
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Custom Theme")
                    .font(.title2)
                    .fontWeight(.bold)

                RadioButtonView(
                    options: ["Basic", "Premium", "Enterprise"],
                    selectedIndex: 1,
                    configuration: RadioButtonConfiguration(
                        selectedTextColor: .white,
                        selectedBackgroundColor: .purple,
                        selectedBorderColor: .purple,
                        selectedCheckboxColor: .white,
                        selectedCheckboxImage: Image(systemName: "star.fill"),
                        unselectedCheckboxImage: Image(systemName: "star"),
                        cornerRadius: 16
                    )
                )
            }
        }
        .padding()
    }
}

#endif
