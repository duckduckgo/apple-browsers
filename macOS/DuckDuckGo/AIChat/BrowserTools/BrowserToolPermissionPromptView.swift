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
        case "openTab": DesignSystemImages.Glyphs.Size16.openIn
        case "bookmarkTab": DesignSystemImages.Glyphs.Size16.bookmarkAdd
        case "switchToTab": DesignSystemImages.Glyphs.Size16.arrowCircleRight
        case "highlightInPage": DesignSystemImages.Glyphs.Size16.findInPage
        default: DesignSystemImages.Glyphs.Size16.aiChat
        }
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
        default: nil
        }
    }
}

struct BrowserToolPermissionPromptView: View {

    private enum Constants {
        static let width: CGFloat = 252
        static let buttonHeight: CGFloat = 32
    }

    let prompt: ClientToolPermissionPrompt
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                decisionButton(UserText.browserToolPermissionAllowOnce, .allowOnce, id: "allowOnce", shortcutHint: "⌘↵")
                decisionButton(UserText.permissionCenterAlwaysAllow, .always, id: "alwaysAllow")
                decisionButton(UserText.permissionCenterNeverAllow, .never, id: "neverAllow")
            }
        }
        .padding(20)
        .frame(width: Constants.width)
        .background(Color(designSystemColor: .surfaceSecondary, palette: themeManager.designColorPalette))
    }

    private func decisionButton(_ title: String, _ decision: ClientToolPermissionDecision, id: String, shortcutHint: String? = nil) -> some View {
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
            .frame(maxWidth: .infinity)
            .frame(height: Constants.buttonHeight)
            .background(primary ? Color(palette.accentPrimary) : Color(designSystemColor: .controlsFillPrimary))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("BrowserToolPermissionPrompt.\(id)")
    }
}
