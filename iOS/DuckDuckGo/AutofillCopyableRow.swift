//
//  AutofillCopyableRow.swift
//  DuckDuckGo
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

import DesignResourcesKit
import SwiftUI

struct AutofillCopyableRow: View {
    @State private var id = UUID()
    let title: String
    let subtitle: String
    @Binding var selectedCell: UUID?
    var truncationMode: Text.TruncationMode = .tail
    var multiLine: Bool = false
    var isMonospaced: Bool = false
    
    var actionTitle: String
    let action: () -> Void
    
    var secondaryActionTitle: String?
    var secondaryAction: (() -> Void)?
    
    var buttonImageName: String?
    var buttonAccessibilityLabel: String?
    var buttonAction: (() -> Void)?
    
    var secondaryButtonImageName: String?
    var secondaryButtonAccessibilityLabel: String?
    var secondaryButtonAction: (() -> Void)?
    
    private let textFieldImageSize: CGFloat = 24
    
    var body: some View {
        ZStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .daxBodyRegular()
                        .foregroundStyle(Color(designSystemColor: .textPrimary))
                    HStack {
                        if isMonospaced {
                            Text(subtitle)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(Color(designSystemColor: .textSecondary))
                                .truncationMode(truncationMode)
                        } else {
                            Text(subtitle)
                                .daxBodyRegular()
                                .foregroundStyle(Color(designSystemColor: .textSecondary))
                                .truncationMode(truncationMode)
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 8))
                
                if secondaryButtonImageName != nil {
                    Spacer(minLength: textFieldImageSize * 2 + 8)
                } else {
                    Spacer(minLength: buttonImageName != nil ? textFieldImageSize : 8)
                }
            }
            .copyable(isSelected: selectedCell == id,
                      menuTitle: actionTitle,
                      menuAction: action,
                      menuSecondaryTitle: secondaryActionTitle,
                      menuSecondaryAction: secondaryAction) {
                self.selectedCell = self.id
            } menuClosedAction: {
                self.selectedCell = nil
            }
            
            if let buttonImageName = buttonImageName, let buttonAccessibilityLabel = buttonAccessibilityLabel {
                let differenceBetweenImageSizeAndTapAreaPerEdge = (36 - textFieldImageSize) / 2.0
                HStack(alignment: .center, spacing: 0) {
                    Spacer()
                    
                    Button {
                        buttonAction?()
                        self.selectedCell = nil
                    } label: {
                        VStack(alignment: .trailing) {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(buttonImageName)
                                    .resizable()
                                    .frame(width: textFieldImageSize, height: textFieldImageSize)
                                    .foregroundColor(Color(designSystemColor: .textPrimary).opacity(0.84))
                                    .opacity(subtitle.isEmpty ? 0 : 1)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain) // Prevent taps from being forwarded to the container view
                    .accessibilityLabel(buttonAccessibilityLabel)
                    .contentShape(Rectangle())
                    .frame(width: 36, height: 36)
                    
                    if let secondaryButtonImageName = secondaryButtonImageName,
                       let secondaryButtonAccessibilityLabel = secondaryButtonAccessibilityLabel {
                        Button {
                            secondaryButtonAction?()
                            self.selectedCell = nil
                        } label: {
                            VStack(alignment: .trailing) {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(secondaryButtonImageName)
                                        .resizable()
                                        .frame(width: textFieldImageSize, height: textFieldImageSize)
                                        .foregroundColor(Color(designSystemColor: .textPrimary).opacity(0.84))
                                        .opacity(subtitle.isEmpty ? 0 : 1)
                                    Spacer()
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain) // Prevent taps from being forwarded to the container view
                        .accessibilityLabel(secondaryButtonAccessibilityLabel)
                        .contentShape(Rectangle())
                        .frame(width: 36, height: 36)
                    }
                    
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: -differenceBetweenImageSizeAndTapAreaPerEdge))
            }
        }
        .selectableBackground(isSelected: selectedCell == id)
    }
}

private struct Copyable: ViewModifier {
    var isSelected: Bool
    var menuTitle: String
    let menuSecondaryTitle: String?
    let menuAction: () -> Void
    let menuSecondaryAction: (() -> Void)?
    let menuOpenedAction: () -> Void
    let menuClosedAction: () -> Void
    
    public func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(false)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .frame(minHeight: 60)
            Rectangle()
                .foregroundColor(.clear)
                .menuController(menuTitle,
                                secondaryTitle: menuSecondaryTitle,
                                action: menuAction,
                                secondaryAction: menuSecondaryAction,
                                onOpen: menuOpenedAction,
                                onClose: menuClosedAction)
        }
    }
}

private struct ListRowSelectableBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var isSelected: Bool
    
    public func body(content: Content) -> some View {
        content
            .listRowBackground(backgroundColor)
            .listRowInsets(.init(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return colorScheme == .light ? Color(baseColor: .gray40) : Color(baseColor: .gray80)
        } else {
            return Color(designSystemColor: .surface)
        }
    }
}

private extension View {
    func copyable(isSelected: Bool, menuTitle: String, menuAction: @escaping () -> Void, menuSecondaryTitle: String? = "", menuSecondaryAction: (() -> Void)? = nil, menuOpenedAction: @escaping () -> Void, menuClosedAction: @escaping () -> Void) -> some View {
        modifier(Copyable(isSelected: isSelected,
                          menuTitle: menuTitle,
                          menuSecondaryTitle: menuSecondaryTitle,
                          menuAction: menuAction,
                          menuSecondaryAction: menuSecondaryAction,
                          menuOpenedAction: menuOpenedAction,
                          menuClosedAction: menuClosedAction))
    }
    
    func selectableBackground(isSelected: Bool) -> some View {
        modifier(ListRowSelectableBackground(isSelected: isSelected))
    }
}
