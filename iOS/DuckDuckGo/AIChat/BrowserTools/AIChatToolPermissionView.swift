//
//  AIChatToolPermissionView.swift
//  DuckDuckGo
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import PrivacyConfig
import SwiftUI
import UIKit

@MainActor
struct AIChatToolPermissionView: View {

    struct Tool: Identifiable {
        let id: String
        let name: String
        let title: String
        let detail: String
        let icon: UIImage
        let rowIcon: UIImage
        let accessibilityName: String

        init?(name: String, targetsOtherTab: Bool = false, offersAllowForChat: Bool = false) {
            typealias Icons = DesignSystemImages.Glyphs.Size16
            id = name
            let copy: Copy.ToolText
            switch AIChatBrowserToolsSubfeature(rawValue: name) {
            case .readTabContent:
                copy = Copy.tabContent(targetsOtherTab: targetsOtherTab, offersAllowForChat: offersAllowForChat)
                icon = Icons.tabContent
                rowIcon = Icons.file
            case .searchHistory:
                copy = Copy.browsingHistory
                icon = Icons.history
                rowIcon = icon
            case .listOpenTabs:
                copy = Copy.openTabs
                icon = Icons.windowsAndTabs
                rowIcon = icon
            case .findInPage:
                copy = Copy.findInPage(targetsOtherTab: targetsOtherTab, offersAllowForChat: offersAllowForChat)
                icon = Icons.searchSite
                rowIcon = icon
            case .switchToTab:
                copy = Copy.switchToTab
                icon = Icons.arrowCircleRight
                rowIcon = icon
            default:
                return nil
            }
            self.name = copy.name
            title = copy.title
            detail = copy.detail
            accessibilityName = copy.accessibilityName ?? copy.name
        }

#if DEBUG || ALPHA
        fileprivate init(mock tool: Tool, row: Int) {
            id = "mock-\(row)"
            name = tool.name
            title = tool.title
            detail = "\(tool.detail) \(tool.detail)"
            icon = tool.icon
            rowIcon = tool.rowIcon
            accessibilityName = tool.accessibilityName
        }
#endif
    }

    struct Prompt {
        enum Approval {
            case once
            case chat
            case access

            var buttonTitle: LocalizedStringKey {
                switch self {
                case .once: Copy.allowOnce
                case .chat, .access: Copy.allowInThisChat
                }
            }

            func decision(for selection: Selection) -> ClientToolPermissionDecision {
                switch self {
                case .once: .allowOnce
                case .chat: .allowForChat
                case .access: selection.allowDecision
                }
            }
        }

        let tools: [Tool]
        let approval: Approval

        init?(_ prompt: ClientToolPermissionPrompt) {
            if let toolNames = prompt.accessToolNames {
                self.init(accessToolNames: toolNames)
            } else {
                guard prompt.target == nil,
                      let tool = Tool(name: prompt.toolName, targetsOtherTab: prompt.targetsOtherTab,
                                      offersAllowForChat: prompt.offersAllowForChat) else { return nil }
                self.init(tools: [tool], approval: prompt.offersAllowForChat ? .chat : .once)
            }
        }

        init?(accessToolNames: [String]) {
            let tools = accessToolNames.compactMap { Tool(name: $0) }
            guard !tools.isEmpty, tools.count == accessToolNames.count,
                  Set(accessToolNames).count == accessToolNames.count else { return nil }
            self.init(tools: tools, approval: .access)
        }

#if DEBUG || ALPHA
        init?(mockToolNames: [String]) {
            let tools = mockToolNames.enumerated().compactMap { row, name in
                Tool(name: name).map { Tool(mock: $0, row: row) }
            }
            guard !tools.isEmpty, tools.count == mockToolNames.count else { return nil }
            self.init(tools: tools, approval: .access)
        }
#endif

        private init(tools: [Tool], approval: Approval) {
            self.tools = tools
            self.approval = approval
        }
    }

    struct Selection {
        let allowsPartialSelection: Bool
        private let toolNames: Set<String>
        private var excluded: Set<String> = []

        init(toolNames: [String], allowsPartialSelection: Bool) {
            self.toolNames = Set(toolNames)
            self.allowsPartialSelection = allowsPartialSelection
        }

        func isSelected(_ toolName: String) -> Bool {
            toolNames.contains(toolName) && !excluded.contains(toolName)
        }

        func canToggle(_ toolName: String) -> Bool {
            allowsPartialSelection && toolNames.contains(toolName)
                && (excluded.contains(toolName) || toolNames.count - excluded.count > 1)
        }

        mutating func toggle(_ toolName: String) {
            guard canToggle(toolName) else { return }
            if excluded.remove(toolName) == nil {
                excluded.insert(toolName)
            }
        }

        var allowDecision: ClientToolPermissionDecision { .allowAccess(excluding: excluded) }
    }

    private enum Metrics {
        static let cardWidth: CGFloat = 321
        static let cardPadding: CGFloat = 16
        static let windowMargin: CGFloat = 16
        static let listSpacing: CGFloat = 14
        static let actionsSpacing: CGFloat = 18
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ObservedObject private var surfaceState: AIChatToolPermissionPresenter.SurfaceState
    @State private var selection: Selection
    @State private var heights: [PermissionCardPart: CGFloat] = [:]
    private let tools: [Tool]
    private let approval: Prompt.Approval
    private let respond: @MainActor (ClientToolPermissionDecision) -> Void

    init(prompt: Prompt,
         surfaceState: AIChatToolPermissionPresenter.SurfaceState,
         respond: @escaping @MainActor (ClientToolPermissionDecision) -> Void) {
        self.tools = prompt.tools
        self.approval = prompt.approval
        self.surfaceState = surfaceState
        self.respond = respond
        _selection = State(initialValue: Selection(toolNames: prompt.tools.map(\.id), allowsPartialSelection: prompt.tools.count > 1))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture {}
                .accessibilityHidden(true)

            GeometryReader { geometry in
                card(availableHeight: max(0, geometry.size.height - Metrics.windowMargin * 2))
                    .frame(maxWidth: Metrics.cardWidth)
                    .padding(.horizontal, Metrics.windowMargin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    private func card(availableHeight: CGFloat) -> some View {
        let contentHeight = max(0, availableHeight - Metrics.cardPadding * 2 - Metrics.actionsSpacing - heights[.actions, default: 0])
        let shape = RoundedRectangle(cornerRadius: 36)

        return VStack(spacing: Metrics.actionsSpacing) {
            cardContent(availableHeight: contentHeight)
            actions
                .fixedSize(horizontal: false, vertical: true)
                .reportPermissionHeight(.actions)
        }
        .padding(Metrics.cardPadding)
        .background {
            if reduceTransparency {
                shape.fill(Color(designSystemColor: .backgroundSheets))
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .onPreferenceChange(PermissionCardHeights.self) { heights = $0 }
        .disabled(surfaceState.isChangingSurface)
    }

    @ViewBuilder
    private func cardContent(availableHeight: CGFloat) -> some View {
        let showsList = approval == .access
        let headerHeight = heights[.header, default: 0]
        let listHeight = max(0, availableHeight - headerHeight - Metrics.listSpacing)
        let scrollsHeader = headerHeight > availableHeight || (showsList && listHeight < heights[.firstRow, default: 0])

        if scrollsHeader {
            scrollView {
                VStack(spacing: Metrics.listSpacing) {
                    header
                    if showsList { toolRows }
                }
            }
            .frame(height: availableHeight)
        } else {
            VStack(spacing: Metrics.listSpacing) {
                header
                if showsList {
                    scrollView { toolRows }
                        .frame(height: min(heights[.list] ?? listHeight, listHeight))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    private var header: some View {
        let singleTool = approval == .access ? nil : tools.first

        return VStack(alignment: .leading, spacing: 8) {
            PermissionBadge(toolIcon: singleTool?.icon)
                .padding(.leading, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(singleTool?.title ?? Copy.multipleToolsTitle)
                    .font(.headline)
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .accessibilityAddTraits(.isHeader)
                Text(singleTool?.detail ?? Copy.multipleToolsDetail)
                    .font(.subheadline)
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .reportPermissionHeight(.header)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                respond(approval.decision(for: selection))
            } label: {
                actionLabel(approval.buttonTitle, primary: true)
            }
            .accessibilityIdentifier("AIChatToolPermission.Allow")

            Button {
                respond(.dontAllow)
            } label: {
                actionLabel(Copy.dontAllow, primary: false)
            }
            .accessibilityIdentifier("AIChatToolPermission.DontAllow")
            .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.plain)
    }

    private var toolRows: some View {
        VStack(spacing: 0) {
            ForEach(tools) { tool in
                if tool.id != tools.first?.id {
                    Divider().padding(.leading, 38).padding(.trailing, 12)
                    toolRow(tool)
                } else {
                    toolRow(tool).reportPermissionHeight(.firstRow)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(designSystemColor: .backgroundTertiary), in: RoundedRectangle(cornerRadius: 20))
        .reportPermissionHeight(.list)
    }

    @ViewBuilder
    private func toolRow(_ tool: Tool) -> some View {
        let isSelected = selection.isSelected(tool.id)
        if selection.allowsPartialSelection {
            Button {
                selection.toggle(tool.id)
            } label: {
                rowLabel(tool)
                    .opacity(isSelected ? 1 : 0.4)
                    .overlay(alignment: .trailing) {
                        selectionIndicator(isSelected: isSelected)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!selection.canToggle(tool.id))
            .accessibilityLabel(Text(tool.accessibilityName))
            .accessibilityValue(Text(tool.detail))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            rowLabel(tool)
                .accessibilityElement(children: .combine)
        }
    }

    private func rowLabel(_ tool: Tool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(uiImage: tool.rowIcon)
                .renderingMode(.template)
                .frame(width: 16, height: 16)
                .foregroundStyle(Color(designSystemColor: .iconsSecondary))
                .padding(.top, 3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(tool.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                Text(tool.detail)
                    .font(.footnote)
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, selection.allowsPartialSelection ? 53 : 12)
        .padding(.vertical, 9)
        .frame(minHeight: 44)
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle().fill(Color(designSystemColor: .accentPrimary))
                Image(uiImage: DesignSystemImages.Glyphs.Size16.check)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color(designSystemColor: .accentContentPrimary))
            } else {
                Circle().strokeBorder(Color(designSystemColor: .iconsSecondary), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private func actionLabel(_ title: LocalizedStringKey, primary: Bool) -> some View {
        Text(title)
            .font(primary ? .headline : .body)
            .foregroundStyle(Color(designSystemColor: primary ? .accentContentPrimary : .textPrimary))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color(designSystemColor: primary ? .accentPrimary : .controlsFillSecondary), in: Capsule())
    }

    @ViewBuilder
    private func scrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16.4, *) {
            ScrollView(content: content).scrollBounceBehavior(.basedOnSize)
        } else {
            ScrollView(content: content)
        }
    }
}

private extension AIChatToolPermissionView {
    enum Copy {
        struct ToolText {
            let name: String
            let title: String
            let detail: String
            var accessibilityName: String?
        }

        static var multipleToolsTitle: String { String(localized: "Allow Duck.ai to do the following:") }
        static var multipleToolsDetail: String { String(localized: "Duck.ai can take these actions without asking again in this chat.") }
        static var allowOnce: LocalizedStringKey { "Allow Once" }
        static var allowInThisChat: LocalizedStringKey { "Allow in This Chat" }
        static var dontAllow: LocalizedStringKey { "Don’t Allow" }

        static func tabContent(targetsOtherTab: Bool, offersAllowForChat: Bool) -> ToolText {
            let name = String(localized: "Tab Content")
            if offersAllowForChat {
                return ToolText(
                    name: name,
                    title: String(localized: "Allow Duck.ai to read content from open tabs?"),
                    detail: String(localized: "It can see page titles, addresses, and text without asking again in this chat.")
                )
            }
            return ToolText(
                name: name,
                title: targetsOtherTab
                    ? String(localized: "Allow Duck.ai to read the content of another tab?")
                    : String(localized: "Allow Duck.ai to read the content of this tab?"),
                detail: String(localized: "It will see the page’s title, address, and text.")
            )
        }

        static var browsingHistory: ToolText {
            ToolText(
                name: String(localized: "Browsing History"),
                title: String(localized: "Allow Duck.ai to search your browsing history?"),
                detail: String(localized: "It will see sites you’ve visited, including before this chat."),
                accessibilityName: String(localized: "Search Browsing History")
            )
        }

        static var openTabs: ToolText {
            ToolText(
                name: String(localized: "List Open Tabs"),
                title: String(localized: "Allow Duck.ai to see your open tabs?"),
                detail: String(localized: "It will see the title and address of each tab in this window.")
            )
        }

        static var switchToTab: ToolText {
            ToolText(
                name: UserText.settingsBrowserAccessSwitchToTab,
                title: UserText.settingsBrowserAccessSwitchToTabPrompt,
                detail: UserText.settingsBrowserAccessSwitchToTabDetail
            )
        }

        static func findInPage(targetsOtherTab: Bool, offersAllowForChat: Bool) -> ToolText {
            if offersAllowForChat {
                return ToolText(
                    name: UserText.findInPage,
                    title: String(localized: "Allow Duck.ai to use Find in Page on open tabs?"),
                    detail: String(localized: "It can see page titles, addresses, and short snippets around each match without asking again in this chat.")
                )
            }
            return ToolText(
                name: UserText.findInPage,
                title: targetsOtherTab
                    ? String(localized: "Allow Duck.ai to use Find in Page on another tab?")
                    : String(localized: "Allow Duck.ai to use Find in Page on this tab?"),
                detail: String(localized: "It will see short snippets around each match.")
            )
        }
    }
}

private struct PermissionBadge: View {
    let toolIcon: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: AppIcon.defaultAppIcon.mediumImage)
                .resizable()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .frame(width: 72, height: 72, alignment: .topLeading)

            if let toolIcon {
                Image(uiImage: toolIcon)
                    .renderingMode(.template)
                    .foregroundStyle(Color(designSystemColor: .accentContentPrimary))
                    .frame(width: 32, height: 32)
                    .background(Color(designSystemColor: .accentPrimary), in: RoundedRectangle(cornerRadius: 9))
                    .padding(.trailing, 3)
                    .padding(.bottom, 7)
            } else {
                let badgeSize: CGFloat = 24
                let cutoutMargin: CGFloat = 2
                let trailingInset: CGFloat = 8
                let bottomInset: CGFloat = 14

                Circle()
                    .frame(width: badgeSize + 2 * cutoutMargin, height: badgeSize + 2 * cutoutMargin)
                    .blendMode(.destinationOut)
                    .padding(.trailing, trailingInset - cutoutMargin)
                    .padding(.bottom, bottomInset - cutoutMargin)

                Image(systemName: "questionmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color(designSystemColor: .background))
                    .frame(width: badgeSize, height: badgeSize)
                    .background(Color(designSystemColor: .textPrimary), in: Circle())
                    .padding(.trailing, trailingInset)
                    .padding(.bottom, bottomInset)
            }
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

private enum PermissionCardPart {
    case header
    case firstRow
    case list
    case actions
}

private struct PermissionCardHeights: PreferenceKey {
    static let defaultValue: [PermissionCardPart: CGFloat] = [:]

    static func reduce(value: inout [PermissionCardPart: CGFloat], nextValue: () -> [PermissionCardPart: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, updated in updated })
    }
}

private extension View {
    func reportPermissionHeight(_ part: PermissionCardPart) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PermissionCardHeights.self, value: [part: geometry.size.height])
            }
        }
    }
}
