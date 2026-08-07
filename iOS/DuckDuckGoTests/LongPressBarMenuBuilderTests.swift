//
//  LongPressBarMenuBuilderTests.swift
//  DuckDuckGoTests
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

import XCTest
@testable import DuckDuckGo
@testable import Core

final class LongPressBarMenuBuilderTests: XCTestCase {

    private var builder: LongPressBarMenuBuilder!
    private var supportedState: OmniBarState!

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
        builder = LongPressBarMenuBuilder(dailyPixelFiring: PixelFiringMock.self)
        supportedState = SmallOmniBarState.HomeNonEditingState(dependencies: MockOmnibarDependency(), isLoading: false)
    }

    func testWhenFeatureFlagDisabledThenOmniBarMenuIsNil() {
        let menu = builder.makeOmniBarMenu(context: makeOmniBarContext(isFeatureEnabled: false))
        XCTAssertNil(menu)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }

    func testWhenStateUnsupportedThenOmniBarMenuIsNil() {
        let unsupportedState = DummyOmniBarState()
        let menu = builder.makeOmniBarMenu(context: makeOmniBarContext(state: unsupportedState))
        XCTAssertNil(menu)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }

    func testWhenOmniBarMenuBuiltThenOpenPixelNotFired() {
        _ = builder.makeOmniBarMenu(context: makeOmniBarContext())
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }

    func testWhenOmniBarMenuDisplayedThenOpenPixelFired() {
        builder.fireOmniBarMenuOpenPixel()
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.longPressBarOpen.name)
    }

    func testWhenPrivacyEnabledOnNonDuckDuckGoSiteThenCopyActionUsesCopyCleanLinkTitle() {
        let menu = builder.makeOmniBarMenu(context: makeOmniBarContext(
            currentURL: URL(string: "https://example.com")!,
            isPrivacyProtectionEnabled: true
        ))
        let actions = flatActions(from: menu)
        XCTAssertTrue(actions.contains(where: { $0.title == UserText.actionCopyCleanLink }))
        XCTAssertFalse(actions.contains(where: { $0.title == UserText.actionCopyLink }))
    }

    func testWhenDuckDuckGoSiteThenCopyActionUsesCopyLinkTitle() {
        let menu = builder.makeOmniBarMenu(context: makeOmniBarContext(
            currentURL: URL(string: "https://duckduckgo.com/?q=test")!,
            isPrivacyProtectionEnabled: true
        ))
        let actions = flatActions(from: menu)
        XCTAssertTrue(actions.contains(where: { $0.title == UserText.actionCopyLink }))
        XCTAssertFalse(actions.contains(where: { $0.title == UserText.actionCopyCleanLink }))
    }

    func testWhenPrivacyEnabledOnNonDuckDuckGoSiteThenCopyLinkTitleReturnsCopyCleanLink() {
        let title = UserText.copyLinkTitle(for: URL(string: "https://example.com")!, isPrivacyProtectionEnabled: true)
        XCTAssertEqual(title, UserText.actionCopyCleanLink)
    }

    func testWhenPrivacyDisabledOnNonDuckDuckGoSiteThenCopyLinkTitleReturnsCopyLink() {
        let title = UserText.copyLinkTitle(for: URL(string: "https://example.com")!, isPrivacyProtectionEnabled: false)
        XCTAssertEqual(title, UserText.actionCopyLink)
    }

    func testWhenPrivacyEnabledOnDuckDuckGoSiteThenCopyLinkTitleReturnsCopyLink() {
        let title = UserText.copyLinkTitle(for: URL(string: "https://duckduckgo.com/?q=test")!, isPrivacyProtectionEnabled: true)
        XCTAssertEqual(title, UserText.actionCopyLink)
    }

    func testWhenDuckPlayerURLThenCopyLinkActionURLReturnsYouTubeURL() {
        let url = URL(string: "duck://player/abcdef12345?t=23s")!
        XCTAssertEqual(url.urlForCopyLinkAction.absoluteString, "https://m.youtube.com/watch?v=abcdef12345&t=23s")
    }

    func testWhenYouTubeNoCookieDuckPlayerURLThenCopyLinkActionURLReturnsYouTubeURL() {
        let url = URL(string: "https://www.youtube-nocookie.com/embed/abcdef12345?t=23s")!
        XCTAssertEqual(url.urlForCopyLinkAction.absoluteString, "https://m.youtube.com/watch?v=abcdef12345&t=23s")
    }

    func testWhenRegularURLThenCopyLinkActionURLReturnsOriginalURL() {
        let url = URL(string: "https://example.com/path")!
        XCTAssertEqual(url.urlForCopyLinkAction, url)
    }

    func testWhenPadThenMoveAddressBarActionHidden() {
        let menu = builder.makeOmniBarMenu(context: makeOmniBarContext(isPad: true))
        let actions = flatActions(from: menu)
        XCTAssertFalse(actions.contains(where: { $0.title == UserText.omnibarLongPressMoveToTop }))
        XCTAssertFalse(actions.contains(where: { $0.title == UserText.omnibarLongPressMoveToBottom }))
    }

    func testWhenShareActionIsPresentThenNoActionSideEffectsOccurOnMenuBuild() {
        var didShare = false
        let menu = builder.makeOmniBarMenu(context: makeOmniBarContext(onShare: {
            didShare = true
        }))

        let shareAction = flatActions(from: menu).first(where: { $0.title == UserText.actionShare })
        XCTAssertNotNil(shareAction)
        XCTAssertFalse(didShare)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo)
    }

    private func makeOmniBarContext(
        state: OmniBarState? = nil,
        isFeatureEnabled: Bool = true,
        currentURL: URL = URL(string: "https://example.com")!,
        isAITab: Bool = false,
        isPad: Bool = false,
        addressBarPosition: AddressBarPosition = .top,
        isPrivacyProtectionEnabled: Bool = false,
        onShare: @escaping () -> Void = {},
        onCopy: @escaping (URL) -> Void = { _ in },
        onMoveAddressBar: @escaping () -> Void = {},
        onCloseTab: @escaping () -> Void = {}
    ) -> LongPressBarMenuBuilder.OmniBarContext {
        .init(
            state: state ?? supportedState,
            isFeatureEnabled: isFeatureEnabled,
            currentURL: currentURL,
            isAITab: isAITab,
            isPad: isPad,
            addressBarPosition: addressBarPosition,
            isPrivacyProtectionEnabled: isPrivacyProtectionEnabled,
            onShare: onShare,
            onCopy: onCopy,
            onMoveAddressBar: onMoveAddressBar,
            onCloseTab: onCloseTab
        )
    }

    private func flatActions(from menu: UIMenu?) -> [UIAction] {
        guard let menu else { return [] }
        return menu.children.flatMap { element in
            if let action = element as? UIAction {
                return [action]
            }
            if let subMenu = element as? UIMenu {
                return flatActions(from: subMenu)
            }
            return []
        }
    }
}

private struct DummyOmniBarState: OmniBarState, OmniBarLoadingBearerStateCreating {

    var name: String = "DummyOmniBarState"
    var isLoading: Bool = false
    var dependencies: OmnibarDependencyProvider = MockOmnibarDependency()

    var hasLargeWidth = false
    var showBackButton = false
    var showForwardButton = false
    var showBookmarksButton = false
    var showAIChatButton = false
    var clearTextOnStart = false
    var allowsTrackersAnimation = false
    var showSearchLoupe = false
    var showCancel = false
    var showPrivacyIcon = false
    var showBackground = false
    var showClear = false
    var showRefresh = false
    var showMenu = false
    var showSettings = false
    var showVoiceSearch = false
    var showAbort = false
    var showDismiss = false
    var showCustomizableButton = false
    var isBrowsing: Bool = false

    var onEditingStoppedState: OmniBarState { DummyOmniBarState() }
    var onEditingSuspendedState: OmniBarState { DummyOmniBarState() }
    var onEditingStartedState: OmniBarState { DummyOmniBarState() }
    var onTextClearedState: OmniBarState { DummyOmniBarState() }
    var onTextEnteredState: OmniBarState { DummyOmniBarState() }
    var onBrowsingStartedState: OmniBarState { DummyOmniBarState() }
    var onBrowsingStoppedState: OmniBarState { DummyOmniBarState() }
    var onEnterPhoneState: OmniBarState { DummyOmniBarState() }
    var onEnterPadState: OmniBarState { DummyOmniBarState() }
    var onReloadState: OmniBarState { DummyOmniBarState() }
    var onEnterAIChatState: OmniBarState { DummyOmniBarState() }

    init(dependencies: OmnibarDependencyProvider, isLoading: Bool) {
        self.dependencies = dependencies
        self.isLoading = isLoading
    }

    init() {
        self.init(dependencies: MockOmnibarDependency(), isLoading: false)
    }
}
