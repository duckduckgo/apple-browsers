//
//  SettingsCell.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons

struct SettingsCellComponents {
    static var chevron: some View {
        Image(systemName: "chevron.forward")
            .font(Font.system(.footnote).weight(.bold))
            // Bypasses the design system to match the system chevron color
            .foregroundColor(Color(UIColor.tertiaryLabel))
    }
    static var link: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size16.openIn)
            .font(Font.system(.footnote).weight(.bold))
            .foregroundColor(Color(designSystemColor: .iconsSecondary))
    }
}

/// Encapsulates a View representing a Cell with different configurations
struct SettingsCellView: View, Identifiable {

    enum Accessory {
        case none
        case rightDetail(String)
        case toggle(isOn: Binding<Bool>)
        case image(Image)
        case custom(AnyView)
    }

    var label: String
    var subtitle: String?
    var image: Image?
    var action: () -> Void = {}
    var enabled: Bool = true
    var accessory: Accessory
    var statusIndicator: StatusIndicatorView?
    var disclosureIndicator: Bool
    var webLinkIndicator: Bool
    var id: UUID = UUID()
    var isButton: Bool
    var isGreyedOut: Bool
    var isNew: Bool = false

    /// Initializes a `SettingsCellView` with the specified label and accessory.
    ///
    /// Use this initializer for standard cell types that require a label.
    /// - Parameters:
    ///   - label: The text to display in the cell.
    ///   - subtitle: Displayed below title (if present)
    ///   - image: Image displayed to the left of label
    ///   - action: The closure to execute when the view is tapped. (If not embedded in a NavigationLink)
    ///   - accessory: The type of cell to display. Excludes the custom cell type.
    ///   - enabled: A Boolean value that determines whether the cell is enabled.
    ///   - disclosureIndicator: Forces Adds a disclosure indicator on the right (chevron)
    ///   - webLinkIndicator: Adds a link indicator on the right
    ///   - isButton: Disables the tap actions on the cell if true
    ///   - isNew: Displays "New" badges next to the item for feature discovery
    init(label: String, subtitle: String? = nil, image: Image? = nil, action: @escaping () -> Void = {}, accessory: Accessory = .none, enabled: Bool = true, statusIndicator: StatusIndicatorView? = nil, disclosureIndicator: Bool = false, webLinkIndicator: Bool = false, isButton: Bool = false, isGreyedOut: Bool = false, isNew: Bool = false) {
        self.label = label
        self.subtitle = subtitle
        self.image = image
        self.action = action
        self.enabled = enabled
        self.accessory = accessory
        self.statusIndicator = statusIndicator
        self.disclosureIndicator = disclosureIndicator
        self.webLinkIndicator = webLinkIndicator
        self.isButton = isButton
        self.isGreyedOut = isGreyedOut
        self.isNew = isNew
    }

    /// Initializes a `SettingsCellView` for custom content.
    ///
    /// Use this initializer for creating a cell that displays custom content.
    /// This initializer does not require a label, as the content is entirely custom.
    /// - Parameters:
    ///   - action: The closure to execute when the view is tapped. (If not embedded in a NavigationLink)
    ///   - customView: A closure that returns the custom view (`AnyView`) to be displayed in the cell.
    ///   - enabled: A Boolean value that determines whether the cell is enabled.
    init(action: @escaping () -> Void = {}, @ViewBuilder customView: () -> AnyView, enabled: Bool = true) {
        self.label = "" // Not used for custom cell
        self.action = action
        self.enabled = enabled
        self.accessory = .custom(customView())
        self.disclosureIndicator = false
        self.webLinkIndicator = false
        self.isButton = false
        self.isGreyedOut = false
    }

    var body: some View {
        Group {
            if isButton {
                Button(action: action) {
                    cellContent
                        .disabled(!enabled)
                }
                .contentShape(Rectangle())
            } else {
                Button {
                    // No-op
                } label: {
                    cellContent
                }
                .contentShape(Rectangle())
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private var cellContent: some View {
        Group {
            switch accessory {
            case .custom(let customView):
                customView
            default:
                defaultView
            }
        }
    }

    private var defaultView: some View {
        Group {
            HStack(alignment: .center) {
                HStack(alignment: .center) {
                    HStack(alignment: .top) {
                        // Image
                        if let image {
                            if isGreyedOut {
                                image
                                    .padding(.top, -2)
                                    .saturation(0)
                                    .opacity(0.5)
                            } else {
                                image
                                    .padding(.top, -2)
                            }
                        }
                        VStack(alignment: .leading) {
                            // Title
                            Text(label)
                                .daxBodyRegular()
                                .foregroundColor(Color(designSystemColor: isGreyedOut == true ? .textSecondary : .textPrimary))
                            // Subtitle
                            if let subtitleText = subtitle {
                                Text(subtitleText)
                                    .daxFootnoteRegular()
                                    .foregroundColor(Color(designSystemColor: .textSecondary))
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(0.7)
                    }.scaledToFit()
                    if isNew {
                        BadgeView(text: UserText.settingsItemNewBadge)
                    }
                }

                Spacer(minLength: 8)

                accessoryView()

                if let statusIndicator {
                    statusIndicator.fixedSize()
                }
                if disclosureIndicator {
                    SettingsCellComponents.chevron
                }
                if webLinkIndicator {
                    SettingsCellComponents.link
                }
            }.padding(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        }.contentShape(Rectangle())
    }

    struct BadgeView: View {
        let text: String
        var body: some View {
            Text(text.uppercased())
                .font(.caption2)
                .bold()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(designSystemColor: .alertYellow))
                .foregroundColor(.black)
                .cornerRadius(6)
        }
    }

    @ViewBuilder
    private func accessoryView() -> some View {
        switch accessory {
        case .none:
            EmptyView()
        case .rightDetail(let value):
            Text(value)
                .daxSubheadRegular()
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .layoutPriority(1)
        case .toggle(let isOn):
            Toggle("", isOn: isOn)
                .toggleStyle(SwitchToggleStyle(tint: Color(designSystemColor: .accent)))
                .fixedSize()
        case .image(let image):
            if isGreyedOut {
                image
                    .saturation(0)
                    .opacity(0.5)
            } else {
                image
            }
        case .custom(let customView):
            customView
        }
    }
}

/// Encapsulates a Picker with options derived from a generic type that conforms to CustomStringConvertible.
struct SettingsPickerCellView<T: CaseIterable & Hashable & CustomStringConvertible>: View {
    let label: String
    let options: [T]
    @Binding var selectedOption: T
    @Environment(\.isEnabled) private var isEnabled: Bool

    /// Initializes a SettingsPickerCellView.
    /// Use a custom picker that mimics the MenuPickerStyle
    /// But with specific design
    /// - Parameters:
    ///   - label: The label to display above the Picker.
    ///   - options: An array of options of generic type `T` that conforms to CustomStringConvertible.
    ///   - selectedOption: A binding to a state variable that represents the selected option.
    init(label: String, options: [T], selectedOption: Binding<T>) {
        self.label = label
        self.options = options
        self._selectedOption = selectedOption
    }

    var body: some View {
        HStack {
            Text(label)
                .daxBodyRegular()
                .foregroundColor(isEnabled ? Color(designSystemColor: .textPrimary): Color(designSystemColor: .textSecondary))
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Group {
                        getButtonWithAction(action: { self.selectedOption = option },
                                            option: option.description,
                                            selected: option == selectedOption)
                    }
                }
            } label: {
                HStack {
                    Text(selectedOption.description)
                        .daxSubheadRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(Font.system(.footnote).weight(.bold))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .padding(.trailing, -2)
                }
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private func getButtonWithAction(action: @escaping () -> Void,
                                     option: String,
                                     selected: Bool) -> some View {
        return Group {
            Button(action: action) {
                HStack {
                    if selected {
                        Image(systemName: "checkmark")
                    }
                    Text(option)
                }
            }
        }
    }
}

/// A simple settings cell that can act as a link and include a disclosure indicator
struct SettingsCustomCell<Content: View>: View {
    var content: Content
    var action: () -> Void
    var disclosureIndicator: Bool
    var isButton: Bool

    /// Initializes a `SettingsCustomCell`.
    /// - Parameters:
    ///   - content: A SwiftUI View to be displayed in the cell.
    ///   - action: The closure to execute when the view is tapped.
    ///   - disclosureIndicator: A Boolean value that determines if the cell shows a disclosure
    ///    indicator.
    ///   - isButton: Disables the tap actions on the cell if true
    init(@ViewBuilder content: () -> Content, action: @escaping () -> Void = {}, disclosureIndicator: Bool = false, isButton: Bool = false) {
        self.content = content()
        self.action = action
        self.disclosureIndicator = disclosureIndicator
        self.isButton = isButton
    }

    var body: some View {
        Group {
            if isButton {
                ZStack {
                    Button(action: action) {
                        cellContent
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        action() // We need this to make sure tap target is expanded to frame
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                cellContent
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private var cellContent: some View {
        HStack {
            content
            Spacer()
            if disclosureIndicator {
                SettingsCellComponents.chevron
            }
        }
    }
}
