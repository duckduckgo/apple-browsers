//
//  VerticalTabsView.swift
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

import DesignResourcesKit
import SwiftUI
import SwiftUIExtensions
import UniformTypeIdentifiers

struct VerticalTabsView: View {
    @ObservedObject var model: VerticalTabsViewModel
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        VerticalTabsList(model: model)
            .environment(\.designSystemPalette, themeManager.designColorPalette)
    }
}

private enum Layout {
    static let listPadding: CGFloat = 4
    static let rowHeight: CGFloat = 32
    static let rowVerticalSpacing: CGFloat = 2
    static let rowHorizontalPadding: CGFloat = 8
    static let rowContentSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 6
    static let iconSize: CGFloat = 16
    static let closeButtonSize: CGFloat = 16
    static let newTabButtonPadding: CGFloat = 8
}

/// Only the sidebar accepts it, so a dragged tab can't land as text in the address bar or a pinned tab.
private let verticalTabDragType = UTType(exportedAs: "com.duckduckgo.macos.vertical-tab")

private struct VerticalTabsList: View {
    @ObservedObject var model: VerticalTabsViewModel
    @Environment(\.designSystemPalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(model.tabs) { tab in
                            VerticalTabRow(tab: tab, isSelected: tab.id == model.selectedTabID, isOnlyTab: model.tabs.count == 1, model: model)
                                .id(tab.id)
                        }
                    }
                    .padding(Layout.listPadding)
                }
                .onAppear {
                    guard let selectedTabID = model.selectedTabID else { return }
                    proxy.scrollTo(selectedTabID)
                }
                .onChange(of: model.selectedTabID) { selectedTabID in
                    guard let selectedTabID else { return }
                    proxy.scrollTo(selectedTabID)
                }
            }

            VerticalTabsNewTabButton(action: model.openNewTab)
                .padding(Layout.newTabButtonPadding)
        }
        .background(Color(designSystemColor: .surfaceBackdrop, palette: palette))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(designSystemColor: .surfaceDecorationPrimary, palette: palette))
                .frame(width: 1)
        }
    }
}

private struct VerticalTabRow: View {
    let tab: VerticalTab
    let isSelected: Bool
    let isOnlyTab: Bool
    @ObservedObject var model: VerticalTabsViewModel

    @Environment(\.designSystemPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Layout.rowContentSpacing) {
            favicon

            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(tab.url?.absoluteString ?? tab.title)

            if isSelected || isHovered {
                VerticalTabCloseButton {
                    model.close(tab.id)
                }
            }
        }
        .padding(.horizontal, Layout.rowHorizontalPadding)
        .frame(height: Layout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .padding(.vertical, Layout.rowVerticalSpacing)
        .onHover { isHovered = $0 }
        .onTapGesture {
            model.select(tab.id)
        }
        .contextMenu {
            Button(UserText.duplicateTab) { model.duplicate(tab.id) }
            if model.canPinTabs && tab.canBePinned {
                Button(UserText.pinTab) { model.pin(tab.id) }
            }
            Divider()
            Button(UserText.closeTab) { model.close(tab.id) }
            Button(UserText.closeOtherTabs) { model.closeOtherTabs(except: tab.id) }
                .disabled(isOnlyTab)
        }
        .onDrag {
            model.startDragging(tab.id)
            let itemProvider = NSItemProvider()
            itemProvider.registerDataRepresentation(forTypeIdentifier: verticalTabDragType.identifier, visibility: .ownProcess) { completion in
                completion(Data(tab.id.utf8), nil)
                return nil
            }
            return itemProvider
        }
        .onDrop(of: [verticalTabDragType], delegate: VerticalTabDropDelegate(targetID: tab.id, model: model))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(tab.id) }
        .accessibilityAction(named: UserText.closeTab) { model.close(tab.id) }
        .accessibilityIdentifier("VerticalTabs.tab")
    }

    @ViewBuilder
    private var favicon: some View {
        if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
        } else {
            LetterIconView(title: tab.url?.host ?? tab.title, size: Layout.iconSize, characterCount: 1, font: .system(size: 9, weight: .bold), paddingModifier: 0)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(designSystemColor: .surfacePrimary, palette: palette)
        } else if isHovered {
            return Color(designSystemColor: .controlsFillPrimary, palette: palette)
        }
        return .clear
    }
}

private struct VerticalTabCloseButton: View {
    let action: () -> Void

    @Environment(\.designSystemPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: NSImage(resource: .close))
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconsPrimary, palette: palette))
                .frame(width: Layout.closeButtonSize, height: Layout.closeButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color(designSystemColor: .controlsFillSecondary, palette: palette) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(UserText.closeTab)
        .accessibilityIdentifier("VerticalTabs.closeTabButton")
    }
}

private struct VerticalTabsNewTabButton: View {
    let action: () -> Void

    @Environment(\.designSystemPalette) private var palette
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.rowContentSpacing) {
                Image(nsImage: NSImage(resource: .add))
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsPrimary, palette: palette))
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                Text(UserText.plusButtonNewTabMenuItem)
                    .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
            }
            .padding(.horizontal, Layout.rowHorizontalPadding)
            .frame(height: Layout.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(isHovered ? Color(designSystemColor: .controlsFillPrimary, palette: palette) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { isHovered = $0 }
        .help(UserText.newTabTooltip)
        .accessibilityIdentifier("VerticalTabs.newTabButton")
    }
}

private struct VerticalTabDropDelegate: DropDelegate {
    let targetID: TabIdentifier
    let model: VerticalTabsViewModel

    func dropEntered(info: DropInfo) {
        model.moveDraggedTab(to: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        model.dropDraggedTab(on: targetID)
        return true
    }
}
