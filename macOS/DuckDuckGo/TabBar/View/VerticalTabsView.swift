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
    static let reorderAnimation = Animation.easeInOut(duration: 0.2)
    static let reorderDragThreshold: CGFloat = 3
    static let listCoordinateSpace = "VerticalTabsList"
    static let titleFade = LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                          startPoint: .leading,
                                          endPoint: .trailing)
}

private struct VerticalTabsList: View {
    /// A tab being dragged to a new place: its row follows the pointer while the other rows make room.
    private struct TabDrag {
        let tabID: TabIdentifier
        /// How far below the row's top the pointer grabbed it.
        let grabOffset: CGFloat
        var pointerY: CGFloat
    }

    @ObservedObject var model: VerticalTabsViewModel
    @Environment(\.designSystemPalette) private var palette
    @State private var drag: TabDrag?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: Layout.rowSpacing) {
                        ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                            VerticalTabRow(tab: tab, isSelected: tab.id == model.selectedTabID, isOnlyTab: model.tabs.count == 1, model: model)
                                .id(tab.id)
                                .offset(y: dragOffset(of: tab.id, at: index))
                                .zIndex(drag?.tabID == tab.id ? 1 : 0)
                                .transaction { transaction in
                                    // The dragged row stays under the pointer; only the rows making room for it slide.
                                    if drag?.tabID == tab.id {
                                        transaction.animation = nil
                                    }
                                }
                                .simultaneousGesture(reorderGesture(for: tab.id))
                        }
                    }
                    .coordinateSpace(name: Layout.listCoordinateSpace)
                    .animation(Layout.reorderAnimation, value: model.tabs.map(\.id))
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

    private func reorderGesture(for tabID: TabIdentifier) -> some Gesture {
        DragGesture(minimumDistance: Layout.reorderDragThreshold, coordinateSpace: .named(Layout.listCoordinateSpace))
            .onChanged { value in
                if drag == nil, let startIndex = index(of: tabID) {
                    drag = TabDrag(tabID: tabID, grabOffset: value.startLocation.y - rowTop(at: startIndex), pointerY: value.location.y)
                    model.select(tabID)
                }
                guard var currentDrag = drag else { return }
                currentDrag.pointerY = value.location.y
                drag = currentDrag
                model.moveTab(tabID, to: targetIndex(of: currentDrag))
            }
            .onEnded { _ in
                withAnimation(Layout.reorderAnimation) {
                    drag = nil
                }
            }
    }

    private func index(of tabID: TabIdentifier) -> Int? {
        model.tabs.firstIndex { $0.id == tabID }
    }

    private func rowTop(at index: Int) -> CGFloat {
        CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
    }

    /// The place of the row that the middle of the dragged row is over.
    private func targetIndex(of drag: TabDrag) -> Int {
        let draggedRowMiddle = drag.pointerY - drag.grabOffset + Layout.rowHeight / 2
        let index = Int((draggedRowMiddle / (Layout.rowHeight + Layout.rowSpacing)).rounded(.down))
        return min(max(index, 0), model.tabs.count - 1)
    }

    private func dragOffset(of tabID: TabIdentifier, at index: Int) -> CGFloat {
        guard let drag, drag.tabID == tabID else { return 0 }
        return drag.pointerY - drag.grabOffset - rowTop(at: index)
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
