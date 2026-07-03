//
//  LongPressBarMenuBuilder.swift
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


import Core
import DesignResourcesKitIcons

final class LongPressBarMenuBuilder {

    typealias Glyphs = DesignSystemImages.Glyphs.Size16

    struct OmniBarContext {
        let state: OmniBarState
        let isFeatureEnabled: Bool
        let currentURL: URL?
        let isAITab: Bool
        let isPad: Bool
        let addressBarPosition: AddressBarPosition
        let isPrivacyProtectionEnabled: Bool
        let onShare: () -> Void
        let onCopy: (URL) -> Void
        let onMoveAddressBar: () -> Void
        let onCloseTab: () -> Void
    }

    private let dailyPixelFiring: DailyPixelFiring.Type

    init(dailyPixelFiring: DailyPixelFiring.Type = DailyPixel.self) {
        self.dailyPixelFiring = dailyPixelFiring
    }

    func makeOmniBarMenu(context: OmniBarContext) -> UIMenu? {
        guard context.isFeatureEnabled else { return nil }
        guard isSupportedNonEditingOmniBarStateForLongPressMenu(context.state) else { return nil }

        var sections = [UIMenuElement]()

        if let url = context.currentURL, !context.isAITab {
            let copyTitle = copyTitle(for: url, isPrivacyProtectionEnabled: context.isPrivacyProtectionEnabled)
            sections.append(UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: UserText.actionShare, image: Glyphs.shareApple) { [weak self] _ in
                    self?.dailyPixelFiring.fireDailyAndCount(.longPressBarActionShare, error: nil, withAdditionalParameters: [:])
                    context.onShare()
                },
                UIAction(title: copyTitle, image: Glyphs.link) { [weak self] _ in
                    self?.dailyPixelFiring.fireDailyAndCount(.longPressBarActionCopy, error: nil, withAdditionalParameters: [:])
                    context.onCopy(url)
                },
            ]))
        }

        if !context.isPad {
            let moveLabel = context.addressBarPosition == .top ? UserText.omnibarLongPressMoveToBottom : UserText.omnibarLongPressMoveToTop
            let moveImage = context.addressBarPosition == .top ? Glyphs.addressBarBottom : Glyphs.addressBarTop
            sections.append(UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: moveLabel, image: moveImage) { [weak self] _ in
                    self?.dailyPixelFiring.fireDailyAndCount(.longPressBarActionMove, error: nil, withAdditionalParameters: [:])
                    context.onMoveAddressBar()
                },
            ]))
        }

        sections.append(UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: UserText.closeTabs(withCount: 1), image: Glyphs.closeOutline, attributes: [.destructive]) { [weak self] _ in
                self?.dailyPixelFiring.fireDailyAndCount(.longPressBarActionCloseTab, error: nil, withAdditionalParameters: [:])
                context.onCloseTab()
            },
        ]))

        return UIMenu(title: "", children: sections)
    }

    func fireOmniBarMenuOpenPixel() {
        dailyPixelFiring.fireDailyAndCount(.longPressBarOpen, error: nil, withAdditionalParameters: [:])
    }

    private func copyTitle(for url: URL, isPrivacyProtectionEnabled: Bool) -> String {
        if !url.isDuckDuckGo, isPrivacyProtectionEnabled {
            return UserText.actionCopyCleanLink
        }
        return UserText.actionCopyLink
    }

    private func isSupportedNonEditingOmniBarStateForLongPressMenu(_ state: OmniBarState) -> Bool {
        switch state {
        case is SmallOmniBarState.HomeNonEditingState,
            is SmallOmniBarState.BrowsingNonEditingState,
            is SmallOmniBarState.AIChatModeState,
            is LargeOmniBarState.HomeNonEditingState,
            is LargeOmniBarState.BrowsingNonEditingState,
            is LargeOmniBarState.AIChatModeState:
            return true
        default:
            return false
        }
    }
}
