//
//  BrowserToolPermissionPromptView.swift
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
import DesignResourcesKitIcons
import SwiftUI

enum BrowserToolPermissionPromptText {

    static func title(toolName: String, targetsOtherTab: Bool) -> String {
        switch (toolName, targetsOtherTab) {
        case ("listOpenTabs", _): UserText.browserToolPermissionTitleListOpenTabs
        case ("searchHistory", _): UserText.browserToolPermissionTitleSearchHistory
        case ("readTabContent", false): UserText.browserToolPermissionTitleReadTabContent
        case ("readTabContent", true): UserText.browserToolPermissionTitleReadOtherTabContent
        case ("findInPage", false): UserText.browserToolPermissionTitleFindInPage
        case ("findInPage", true): UserText.browserToolPermissionTitleFindInOtherTab
        case ("searchDownloads", _): UserText.browserToolPermissionTitleSearchDownloads
        case ("searchBookmarks", _): UserText.browserToolPermissionTitleSearchBookmarks
        case ("closeTabs", _): UserText.browserToolPermissionTitleCloseTabs
        case ("pinTab", _): UserText.browserToolPermissionTitlePinTab
        case ("openTab", _): UserText.browserToolPermissionTitleOpenTab
        case ("bookmarkTab", _): UserText.browserToolPermissionTitleBookmarkTab
        case ("switchToTab", _): UserText.browserToolPermissionTitleSwitchToTab
        case ("highlightInPage", _): UserText.browserToolPermissionTitleHighlightInPage
        case ("requestAccess", _): UserText.browserToolAccessTitle
        default: UserText.browserToolPermissionTitleOther
        }
    }

    static func icon(toolName: String) -> NSImage {
        switch toolName {
        case "listOpenTabs": DesignSystemImages.Glyphs.Size16.windowsAndTabs
        case "searchHistory": DesignSystemImages.Glyphs.Size16.history
        case "readTabContent": DesignSystemImages.Glyphs.Size16.tabContent
        case "findInPage": DesignSystemImages.Glyphs.Size16.searchSite
        case "searchDownloads": DesignSystemImages.Glyphs.Size16.downloads
        case "searchBookmarks": DesignSystemImages.Glyphs.Size16.bookmarks
        case "closeTabs": DesignSystemImages.Glyphs.Size16.tabCloseAlt
        case "pinTab": DesignSystemImages.Glyphs.Size16.pin
        case "openTab": size16(DesignSystemImages.Glyphs.Size24.tabNew)
        case "bookmarkTab": DesignSystemImages.Glyphs.Size16.bookmarkAdd
        case "switchToTab": DesignSystemImages.Glyphs.Size16.arrowCircleRight
        case "highlightInPage": size16(DesignSystemImages.Glyphs.Size24.textSelect)
        default: DesignSystemImages.Glyphs.Size16.aiChat
        }
    }

    // DRK has these glyphs at 24 pt only.
    private static func size16(_ image: NSImage) -> NSImage {
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    static func detail(toolName: String, targetsOtherTab: Bool) -> String? {
        switch (toolName, targetsOtherTab) {
        case ("listOpenTabs", _): UserText.browserToolPermissionDetailListOpenTabs
        case ("searchHistory", _): UserText.browserToolPermissionDetailSearchHistory
        case ("readTabContent", false): UserText.browserToolPermissionDetailReadTabContent
        case ("readTabContent", true): UserText.browserToolPermissionDetailReadOtherTabContent
        case ("findInPage", false): UserText.browserToolPermissionDetailFindInPage
        case ("findInPage", true): UserText.browserToolPermissionDetailFindInOtherTab
        case ("searchDownloads", _): UserText.browserToolPermissionDetailSearchDownloads
        case ("searchBookmarks", _): UserText.browserToolPermissionDetailSearchBookmarks
        case ("closeTabs", _): UserText.browserToolPermissionDetailCloseTabs
        case ("requestAccess", _): UserText.browserToolAccessDetail
        default: nil
        }
    }
}

/// The tools the user took out of a `requestAccess` prompt, shared with the presenter's ⌘↵ handling.
@MainActor
final class BrowserToolAccessSelection: ObservableObject {
    @Published var removed: [String] = []
}

struct BrowserToolPermissionPromptView: View {

    private enum Constants {
        static let width: CGFloat = 252
        static let accessWidth: CGFloat = 360
        static let buttonHeight: CGFloat = 32
    }

    let prompt: ClientToolPermissionPrompt
    @ObservedObject var selection: BrowserToolAccessSelection
    let decide: (ClientToolPermissionDecision) -> Void

    @ObservedObject private var themeManager: ThemeManager = NSApp.delegateTyped.themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(BrowserToolPermissionPromptText.title(toolName: prompt.toolName, targetsOtherTab: prompt.targetsOtherTab))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = BrowserToolPermissionPromptText.detail(toolName: prompt.toolName, targetsOtherTab: prompt.targetsOtherTab) {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let target = prompt.target {
                    Text(target)
                        .font(.system(size: 12))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .lineLimit(4)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("BrowserToolPermissionPrompt.target")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let accessToolNames = prompt.accessToolNames {
                accessTools(accessToolNames)

                HStack(spacing: 12) {
                    decisionButton(UserText.browserToolAccessDontAllow, .dontAllow, id: "dontAllow", fillsWidth: false)
                    decisionButton(UserText.browserToolAccessAllow, .allowAccess(excluding: Set(selection.removed)), id: "allowInChat", shortcutHint: "⌘↵")
                }
            } else {
                VStack(spacing: 8) {
                    if prompt.offersAllowForChat {
                        decisionButton(UserText.browserToolAccessAllow, .allowForChat, id: "allowForChat", shortcutHint: "⌘↵")
                    } else {
                        decisionButton(UserText.browserToolPermissionAllowOnce, .allowOnce, id: "allowOnce", shortcutHint: "⌘↵")
                    }
                    if prompt.offersAlways {
                        decisionButton(UserText.permissionCenterAlwaysAllow, .always, id: "alwaysAllow")
                    }
                    decisionButton(UserText.browserToolAccessDontAllow, .dontAllow, id: "dontAllow")
                }
            }
        }
        .padding(20)
        .frame(width: prompt.accessToolNames == nil ? Constants.width : Constants.accessWidth)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }

    /// Each of two or more tools has an X that takes it out of what will be allowed; the last one can't be taken out.
    @ViewBuilder
    private func accessTools(_ toolNames: [String]) -> some View {
        let kept = toolNames.filter { !selection.removed.contains($0) }
        let boxed = toolNames.count > 1
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(kept.enumerated()), id: \.element) { index, toolName in
                if index > 0 {
                    Divider()
                }
                accessRow(toolName, removable: kept.count > 1)
                    .padding(boxed ? 12 : 0)
            }
        }
        .background(boxed ? RoundedRectangle(cornerRadius: 8).fill(Color(designSystemColor: .controlsFillPrimary, palette: themeManager.designColorPalette)) : nil)
        // A container of its own, so its identifier doesn't replace each row's and X's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("BrowserToolPermissionPrompt.accessTools")

        if !selection.removed.isEmpty {
            let titles = selection.removed.map { BrowserToolSettingsText.title(toolName: $0) }
            let names = titles.count > 2 ? titles.dropLast().joined(separator: ", ") + ", or " + titles[titles.count - 1] : titles.joined(separator: " or ")
            // Undo follows the note on the same line, wrapping with it.
            Text(AttributedString(UserText.browserToolAccessRemovedNote(toolNames: names) + " ") + undoLink)
                .font(.system(size: 12))
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, OpenURLAction { _ in
                    selection.removed = []
                    return .handled
                })
                .accessibilityIdentifier("BrowserToolPermissionPrompt.removedNote")
        }
    }

    private var undoLink: AttributedString {
        var link = AttributedString(UserText.browserToolAccessUndo)
        link.link = URL(string: "duck://undo")
        link.foregroundColor = Color(designSystemColor: .textLink)
        return link
    }

    private func accessRow(_ toolName: String, removable: Bool) -> some View {
        let title = BrowserToolSettingsText.title(toolName: toolName)
        return HStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: BrowserToolPermissionPromptText.icon(toolName: toolName))
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsPrimary, palette: themeManager.designColorPalette))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    if let detail = BrowserToolSettingsText.detail(toolName: toolName) {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if removable {
                Button { selection.removed.append(toolName) } label: {
                    Image(nsImage: DesignSystemImages.Glyphs.Size16.closeSmall)
                        .renderingMode(.template)
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverHighlightButtonStyle())
                .help(UserText.browserToolAccessRemoveTool(toolName: title))
                .accessibilityLabel(UserText.browserToolAccessRemoveTool(toolName: title))
                .accessibilityIdentifier("BrowserToolPermissionPrompt.remove.\(toolName)")
            }
        }
    }

    /// `fillsWidth: false` sizes the button to its title, leaving the rest of the row to the others.
    private func decisionButton(_ title: String, _ decision: ClientToolPermissionDecision, id: String, shortcutHint: String? = nil,
                                fillsWidth: Bool = true) -> some View {
        let palette = themeManager.theme.palette
        let primary = shortcutHint != nil
        return Button(action: { decide(decision) }) {
            HStack(spacing: 6) {
                Text(title)
                if let shortcutHint {
                    Text(shortcutHint).opacity(0.7)
                }
            }
            .font(.system(size: 13))
            .foregroundColor(primary ? Color(palette.accentContentPrimary) : Color(designSystemColor: .textPrimary))
            .padding(.horizontal, fillsWidth ? 0 : 24)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: Constants.buttonHeight)
            .background(primary ? Color(palette.accentPrimary) : Color(designSystemColor: .controlsFillPrimary))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("BrowserToolPermissionPrompt.\(id)")
    }
}
