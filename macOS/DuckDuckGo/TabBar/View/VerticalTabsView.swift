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

enum VerticalTabsStyle {
    /// The sidebar and the tab bar above it let the blur behind the window show through.
    static let backgroundOpacity: CGFloat = 0.8
}

struct VerticalTabsView: View {
    @ObservedObject var model: VerticalTabsViewModel
    @ObservedObject var themeManager: ThemeManager

    var body: some View {
        VerticalTabsList(model: model)
            .environment(\.designSystemPalette, themeManager.designColorPalette)
    }
}

private enum Layout {
    static let listPadding: CGFloat = 6
    static let rowHeight: CGFloat = 34
    static let rowSpacing: CGFloat = 2
    static let rowHorizontalPadding: CGFloat = 10
    static let rowContentSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 8
    static let iconSize: CGFloat = 16
    static let closeButtonSize: CGFloat = 16
    static let selectedShadowRadius: CGFloat = 1
    static let titleFade = LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                          startPoint: .leading,
                                          endPoint: .trailing)
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
                    LazyVStack(spacing: Layout.rowSpacing) {
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
                .padding(Layout.listPadding)
        }
        .background(Color(designSystemColor: .surfaceBackdrop, palette: palette).opacity(VerticalTabsStyle.backgroundOpacity))
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
                .fixedSize()
                .foregroundColor(Color(designSystemColor: .textPrimary, palette: palette))
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
                .mask(Layout.titleFade)
                .help(tab.url?.absoluteString ?? tab.title)

            if isHovered {
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
                .shadow(color: isSelected ? Color(designSystemColor: .shadowTertiary, palette: palette) : .clear,
                        radius: Layout.selectedShadowRadius,
                        y: Layout.selectedShadowRadius)
        )
        .contentShape(Rectangle())
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
                    .foregroundColor(Color(designSystemColor: .iconsSecondary, palette: palette))
                    .frame(width: Layout.iconSize, height: Layout.iconSize)
                Text(UserText.plusButtonNewTabMenuItem)
                    .foregroundColor(Color(designSystemColor: .textSecondary, palette: palette))
                Spacer(minLength: 0)
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
