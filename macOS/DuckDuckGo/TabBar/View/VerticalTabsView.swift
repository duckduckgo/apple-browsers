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
    let newTabButtonAnchor: NSView
    let dragSession: VerticalTabDragSession

    static func insertionIndex(at y: CGFloat, rowCount: Int) -> Int {
        let rowStride = Layout.rowHeight + Layout.rowSpacing
        let index = Int(floor((y + Layout.rowHeight / 2 + Layout.rowSpacing) / rowStride))
        return min(max(index, 0), rowCount)
    }

    var body: some View {
        VerticalTabsList(model: model, newTabButtonAnchor: newTabButtonAnchor, dragSession: dragSession)
            .frame(minWidth: 0, maxWidth: .infinity)
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
    static let permissionIconInterval: TimeInterval = 4
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
    @ObservedObject var model: VerticalTabsViewModel
    let newTabButtonAnchor: NSView
    let dragSession: VerticalTabDragSession
    @Environment(\.designSystemPalette) private var palette

    var body: some View {
        let tabs = model.tabs
        let indexedTabs = tabs.indices.lazy.map { (index: $0, tab: tabs[$0]) }
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: Layout.rowSpacing) {
                        ForEach(indexedTabs, id: \.tab.id) { index, tab in
                            VerticalTabRow(tab: tab, isSelected: tab.id == model.selectedTabID, isOnlyTab: tabs.count == 1, model: model)
                                .id(tab.id)
                                .modifier(VerticalTabReorder(tabID: tab.id, index: index, model: model, dragSession: dragSession))
                        }
                    }
                    .coordinateSpace(name: Layout.listCoordinateSpace)
                    .background(VerticalTabsAnchor(view: dragSession.rowsAnchor).allowsHitTesting(false))
                    .animation(Layout.reorderAnimation, value: model.tabOrderRevision)
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
                .background(VerticalTabsAnchor(view: newTabButtonAnchor).allowsHitTesting(false))
                .padding(Layout.listPadding)
        }
        .background(Color(designSystemColor: .surfaceBackdrop, palette: palette).opacity(VerticalTabsStyle.backgroundOpacity))
    }
}

/// Only the row under the pointer needs to redraw between changes to the tab order.
private struct VerticalTabReorder: ViewModifier {
    private struct Drag {
        let grabOffset: CGFloat
        var pointerY: CGFloat?
    }

    let tabID: TabIdentifier
    let index: Int
    let model: VerticalTabsViewModel
    @ObservedObject var dragSession: VerticalTabDragSession
    @State private var drag: Drag?
    @GestureState private var isReordering = false

    func body(content: Content) -> some View {
        content
            .offset(y: dragOffset)
            .zIndex(drag == nil ? 0 : 1)
            .transaction { transaction in
                if drag != nil {
                    transaction.animation = nil
                }
            }
            .simultaneousGesture(reorderGesture)
            .onChange(of: isReordering) { isReordering in
                if !isReordering {
                    withAnimation(Layout.reorderAnimation) { drag = nil }
                }
            }
    }

    private var reorderGesture: some Gesture {
        DragGesture(minimumDistance: Layout.reorderDragThreshold, coordinateSpace: .named(Layout.listCoordinateSpace))
            .updating($isReordering) { _, isReordering, _ in isReordering = true }
            .onChanged { value in
                if drag == nil {
                    drag = Drag(grabOffset: value.startLocation.y - rowTop)
                    model.select(tabID)
                    dragSession.beginDragging(tabID)
                }
                guard var currentDrag = drag else { return }
                let canReorder = dragSession.isDragging && dragSession.isPointerOverSidebar
                currentDrag.pointerY = canReorder ? value.location.y : nil
                drag = currentDrag
                if canReorder {
                    model.moveTab(tabID, to: targetIndex(pointerY: value.location.y, grabOffset: currentDrag.grabOffset))
                }
            }
    }

    private var rowTop: CGFloat {
        CGFloat(index) * (Layout.rowHeight + Layout.rowSpacing)
    }

    /// The place of the row that the middle of the dragged row is over.
    private func targetIndex(pointerY: CGFloat, grabOffset: CGFloat) -> Int {
        let draggedRowMiddle = pointerY - grabOffset + Layout.rowHeight / 2
        let index = Int((draggedRowMiddle / (Layout.rowHeight + Layout.rowSpacing)).rounded(.down))
        return min(max(index, 0), model.tabs.count - 1)
    }

    private var dragOffset: CGFloat {
        guard dragSession.isDragging, let drag, let pointerY = drag.pointerY else { return 0 }
        return pointerY - drag.grabOffset - rowTop
    }
}

private struct VerticalTabsAnchor: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct VerticalTabRow: View {
    let tab: VerticalTab
    let isSelected: Bool
    let isOnlyTab: Bool
    @ObservedObject var model: VerticalTabsViewModel

    @Environment(\.designSystemPalette) private var palette
    @State private var isHovered = false
    @State private var permissionRotationStart = Date()

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
                .disabled(!tab.canBeDuplicated)
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
        .accessibilityValue(activePermissionDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(tab.id) }
        .accessibilityAction(named: UserText.closeTab) { model.close(tab.id) }
        .accessibilityIdentifier("VerticalTabs.tab")
    }

    @ViewBuilder
    private var favicon: some View {
        if let firstPermission = tab.activePermissions.first {
            if tab.activePermissions.count == 1 {
                permissionIcon(firstPermission)
            } else {
                TimelineView(.periodic(from: permissionRotationStart, by: Layout.permissionIconInterval)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(permissionRotationStart))
                    let tick = Int(elapsed / Layout.permissionIconInterval)
                    permissionIcon(tab.activePermissions[tick % tab.activePermissions.count])
                }
            }
        } else if let favicon = tab.favicon {
            Image(nsImage: favicon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
        } else {
            LetterIconView(title: tab.url?.host ?? tab.title, size: Layout.iconSize, characterCount: 1, font: .system(size: 9, weight: .bold), paddingModifier: 0)
        }
    }

    private func permissionIcon(_ permission: PermissionType) -> some View {
        Image(nsImage: permission.solidIcon ?? permission.icon)
            .renderingMode(.template)
            .foregroundColor(Color(nsColor: .systemRed))
            .frame(width: Layout.iconSize, height: Layout.iconSize)
            .help(activePermissionDescription)
    }

    private var activePermissionDescription: String {
        guard !tab.activePermissions.isEmpty else { return "" }
        let names = ListFormatter.localizedString(byJoining: tab.activePermissions.map(\.localizedDescription))
        return String(format: UserText.verticalTabActivePermissions, names)
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
