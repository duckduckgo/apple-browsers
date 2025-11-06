//
//  ImportSourcePickerView.swift
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

import Foundation
import SwiftUI
import DesignResourcesKitIcons
import DesignResourcesKit
import BrowserServicesKit
import AppKit

struct ImportSourcePickerView: View {
    @StateObject private var viewModel: ImportSourcePickerViewModel

    init(availableSources: [DataImport.Source],
         selectedSource: DataImport.Source,
         selectedImportTypes: [DataImport.DataType],
         shouldShowSyncFeature: Bool,
         onSourceSelected: @escaping (DataImport.Source) -> Void,
         onTypeSelected: @escaping (DataImport.DataType, Bool) -> Void,
         onSyncSelected: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ImportSourcePickerViewModel(
            availableSources: availableSources,
            selectedSource: selectedSource,
            selectedImportTypes: selectedImportTypes,
            shouldShowSyncButton: shouldShowSyncFeature,
            onSourceSelected: onSourceSelected,
            onTypeSelected: onTypeSelected,
            onSyncSelected: onSyncSelected
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack {
                VStack(spacing: 4) {
                    Text(UserText.importChooseSourceTitle)
                        .font(.title2.weight(.semibold))
                        .padding(.top, 20)
                    HoverButtonView {
                        viewModel.showTypeSelectionSheet()
                    } content: {
                        HStack(alignment: .lastTextBaseline, spacing: 1) {
                            Text(viewModel.typeButtonTitle)
                                .font(.system(size: 13, weight: .semibold))
                            Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight)
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 10, height: 10)
                                .rotationEffect(.degrees(90))
                        }
                    }
                    .sheet(isPresented: $viewModel.isTypePickerSheetVisible) {
                        NewImportTypePickerView(
                            items: $viewModel.importTypeItems,
                            doneAction: viewModel.typeSelectionDone,
                            cancelAction: viewModel.typeSelectionCancelled,
                            isDoneDisabled: $viewModel.isDoneButtonDisabled
                        )
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                RadioGridPicker(viewModel: viewModel)
                if viewModel.shouldShowExpandButton {
                    HoverButtonView {
                        viewModel.toggleExpansion()
                    } content: {
                        Text(UserText.importChooseSourceShowMoreButtonTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 10)
                }
            }
            if viewModel.shouldShowSyncButton {
                Button(action: viewModel.syncSelected) {
                    HStack(alignment: .center) {
                        Text(UserText.importChooseSourceSyncButtonTitle)
                            .font(.system(size: 13))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                        Spacer()
                        Text(UserText.importChooseSourceSyncButtonAction)
                            .font(.system(size: 13))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                        Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 10, height: 10)
                            .foregroundColor(Color(designSystemColor: .textTertiary))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .frame(width: 380, alignment: .center)
                    .background((Color(designSystemColor: .surfacePrimary)))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

private struct HoverButtonView<Content>: View where Content: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State var isHovering: Bool = false

    var body: some View {
        Button(action: action) {
            content()
            .foregroundColor(isHovering ? Color(designSystemColor: .textPrimary) : Color(designSystemColor: .textTertiary))
            .onHover {
                isHovering = $0
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Radio Grid Picker

private struct RadioGridPicker: View {
    @ObservedObject var viewModel: ImportSourcePickerViewModel

    let columns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(viewModel.visibleOptions) { option in
                let icon = Image(nsImage: option.importSourceImage ?? DesignSystemImages.Color.Size24.document)

                Button {
                    viewModel.selectSource(option)   // fires on mouse-up inside
                } label: {
                    RadioCard(
                        isSelected: viewModel.selectedSource == option,
                        icon: icon,
                        title: option.importSourceName
                    )
                }
                .buttonStyle(CardPressStyle()) // gives us configuration.isPressed
                .accessibilityElement(children: .combine)
                .accessibilityLabel(option.importSourceName.replacingOccurrences(of: "\n", with: " "))
                .accessibilityAddTraits(option == viewModel.selectedSource ? [.isSelected] : [])
                .accessibilityHint("Activate to select")
            }
        }
    }
}

private struct CardIsPressedKey: EnvironmentKey {
    static let defaultValue = false
}
private extension EnvironmentValues {
    var cardIsPressed: Bool {
        get { self[CardIsPressedKey.self] }
        set { self[CardIsPressedKey.self] = newValue }
    }
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.cardIsPressed, configuration.isPressed)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Radio Card

private struct RadioCard: View {
    let isSelected: Bool
    let icon: Image
    let title: String
    @Environment(\.cardIsPressed) private var isPressed   // <- from CardPressStyle
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            icon
                .resizable()
                .frame(width: 32, height: 32)
                .padding(.trailing, 10)

            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)

            Spacer(minLength: 10)

            RadioButton(isOn: .constant(isSelected), pressed: isPressed) // <- pressed visual
                .fixedSize()
                .allowsHitTesting(false)    // card is the only hit target
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isHovering ? Color(designSystemColor: .controlsFillSecondary) : Color(designSystemColor: .controlsFillPrimary))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(isHovering ? 0.10 : 0.06), radius: 3, x: 0, y: 1)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .scaleEffect(isPressed ? 0.997 : 1)
    }
}

/// A true macOS radio button (NSButtonType.radio) bridged into SwiftUI.
private struct RadioButton: NSViewRepresentable {
    @Binding var isOn: Bool
    var pressed: Bool = false

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton(radioButtonWithTitle: "", target: nil, action: nil)
        b.setButtonType(.radio)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.allowsMixedState = false
        b.focusRingType = .default
        return b
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.state = isOn ? .on : .off
        button.isHighlighted = pressed // native mouse-down look
    }
}
