//
//  FloatingTabSwitcherChromeTests.swift
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

import DesignResourcesKit
import XCTest
import UIKit
@testable import DuckDuckGo

@MainActor
final class FloatingTabSwitcherChromeTests: XCTestCase {

    private func makeInstalledChrome() -> FloatingTabSwitcherChrome {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)
        return chrome
    }

    func testWhenRegularSizeThenTopBarHasStyleMenuAndDone() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.count, 1)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.count, 1)
        XCTAssertNil(chrome.navigationItem.title)
        XCTAssertNotNil(chrome.navigationItem.leftBarButtonItems?.first?.menu)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.accessibilityLabel, UserText.navigationTitleDone)
    }

    func testWhenRegularSizeWithoutAIChatThenBottomBarHasNoDuckChat() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.toolbar.items?.count, 5)
        } else {
            XCTAssertEqual(chrome.toolbar.items?.count, 7)
            XCTAssertEqual(chrome.toolbar.items?.first?.width, 20)
            XCTAssertEqual(chrome.toolbar.items?.last?.width, 20)
        }
    }

    func testWhenRegularSizeWithAIChatThenBottomBarHasDuckChat() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.toolbar.items?.count, 6)
        } else {
            XCTAssertEqual(chrome.toolbar.items?.count, 9)
            XCTAssertEqual(chrome.toolbar.items?[6].width, 12)
        }
    }

    func testWhenEditingThenTopBarHasMenuSelectionCountAndSelectAll() {
        let chrome = makeInstalledChrome()
        chrome.actions.onMultiSelectMenuRequested = { UIMenu(children: []) }
        chrome.setTitle("2 Selected")

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertNotNil(chrome.navigationItem.leftBarButtonItems?.first?.menu)
        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.count, 1)
        XCTAssertNil(chrome.navigationItem.title)
        XCTAssertEqual((chrome.navigationItem.titleView as? UILabel)?.text, "2 Selected")
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.title, UserText.selectAllTabs)
    }

    func testWhenEditingTitleChangesThenLabelResizesToFitNewTitle() {
        let chrome = makeInstalledChrome()
        chrome.setTitle("2 Tabs")
        chrome.update(state: .editingRegularSize(selectedCount: 0, totalCount: 2),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        guard let titleLabel = chrome.navigationItem.titleView as? UILabel else {
            XCTFail("Missing selection title label")
            return
        }
        let initialWidth = titleLabel.frame.width

        chrome.setTitle("5 Private Tabs")

        XCTAssertGreaterThan(titleLabel.frame.width, initialWidth)
        XCTAssertGreaterThanOrEqual(titleLabel.frame.width, titleLabel.intrinsicContentSize.width)
    }

    func testWhenEditingThenBottomBarHasCloseTabsAndDone() {
        let chrome = makeInstalledChrome()
        chrome.actions.onMultiSelectMenuRequested = { UIMenu(children: []) }

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        let items = chrome.toolbar.items ?? []
        let closeTabsIndex = items.firstIndex { $0.title == UserText.tabSwitcherCloseTabsButtonTitle(withCount: 2) }
        let fireIndex = items.firstIndex { $0.accessibilityIdentifier == "Browser.Toolbar.Button.Fire" }
        let doneIndex = items.firstIndex { $0.accessibilityLabel == UserText.navigationTitleDone }

        guard let closeTabsIndex, let doneIndex else {
            XCTFail("Missing selection toolbar items")
            return
        }
        // Single-tab burn is not implemented, so select mode must not offer the Fire button.
        XCTAssertNil(fireIndex)
        XCTAssertLessThan(closeTabsIndex, doneIndex)
        XCTAssertNotNil(chrome.navigationItem.leftBarButtonItems?.first?.menu)

        if #available(iOS 26.0, *) {
            // On iOS 26 Done is a title-less glyph; earlier versions still use the system Done item.
            XCTAssertNil(items[doneIndex].title)
            XCTAssertNotNil(items[doneIndex].image)
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual([items[closeTabsIndex], items[doneIndex]].map(\.sharesBackground), [false, false])
        }
    }

    func testWhenAllSelectedWhileEditingThenShowsDeselectAll() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 4, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.title, UserText.deselectAllTabs)
    }

    func testWhenLargeSizeThenMatchesIPhoneControlStyle() {
        let chrome = makeInstalledChrome()
        chrome.actions.onEditMenuRequested = { UIMenu(children: []) }

        chrome.update(state: .largeSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.count, 2)
        XCTAssertNotNil((chrome.navigationItem.leftBarButtonItems?.first?.customView as? UIButton)?.menu)
        XCTAssertNotNil(chrome.navigationItem.leftBarButtonItems?.last?.menu)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.accessibilityLabel, UserText.navigationTitleDone)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.count, 3)
        XCTAssertTrue(chrome.toolbar.isHidden)
        XCTAssertTrue(chrome.toolbar.items?.isEmpty == true)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.first?.style, .prominent)
            XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.map(\.sharesBackground), [false, false])
            XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.map(\.sharesBackground), [false, false, true])
        }
    }

    func testWhenLargeSizeWithAIChatThenDuckChatIsInTopBar() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .largeSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: true, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.count, 4)
        XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.last?.accessibilityIdentifier, "TabSwitcher.Button.DuckChat")
        XCTAssertTrue(chrome.toolbar.items?.isEmpty == true)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.navigationItem.rightBarButtonItems?.map(\.sharesBackground), [false, false, true, true])
        }
    }

    func testWhenEditingLargeSizeThenMatchesProductionBarLayout() {
        let chrome = makeInstalledChrome()
        chrome.setTitle("2 Selected")
        chrome.actions.onMultiSelectMenuRequested = { UIMenu(children: []) }

        chrome.update(state: .editingLargeSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.first?.accessibilityLabel, UserText.navigationTitleDone)
        XCTAssertEqual((chrome.navigationItem.titleView as? UILabel)?.text, "2 Selected")
        XCTAssertNotNil(chrome.navigationItem.rightBarButtonItems?.first?.menu)
        XCTAssertTrue(chrome.toolbar.isHidden)
        XCTAssertTrue(chrome.toolbar.items?.isEmpty == true)

        if #available(iOS 26.0, *) {
            XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.first?.style, .prominent)
        }
    }

    func testWhenLargeSizeThenCollectionHasNoBottomInset() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .top, interfaceMode: .largeSize)
        chrome.applyCollectionContentInset(to: collectionView)

        XCTAssertEqual(collectionView.contentInset.bottom, 0)
    }

    func testWhenCollectionContentInsetIsAppliedThenTopIncludesFloatingMargin() {
        let chrome = FloatingTabSwitcherChrome()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

        chrome.applyCollectionContentInset(to: collectionView)

        XCTAssertEqual(collectionView.contentInset.top, 58)
        XCTAssertEqual(collectionView.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(collectionView.contentOffset.y, -58)
        XCTAssertEqual(chrome.topBarBottomOffset, 58)
    }

    func testWhenCollectionContentInsetIsAppliedToBothPagesThenTopInsetsMatch() {
        let chrome = FloatingTabSwitcherChrome()
        let normalPage = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let firePage = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

        chrome.applyCollectionContentInset(to: normalPage)
        chrome.applyCollectionContentInset(to: firePage)

        XCTAssertEqual(normalPage.contentInset.top, firePage.contentInset.top)
        XCTAssertEqual(normalPage.contentOffset.y, firePage.contentOffset.y)
        XCTAssertEqual(normalPage.contentInsetAdjustmentBehavior, .never)
        XCTAssertEqual(firePage.contentInsetAdjustmentBehavior, .never)
    }

    func testWhenCollectionInsetsAreUnchangedThenLayoutDoesNotRewriteInsetsOrOffset() {
        let chrome = FloatingTabSwitcherChrome()
        let collectionView = InsetTrackingCollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        chrome.applyCollectionContentInset(to: collectionView)
        collectionView.contentOffset.y = 200
        collectionView.verticalScrollIndicatorInsets = .zero
        collectionView.contentInsetWriteCount = 0
        collectionView.contentOffsetWriteCount = 0

        chrome.applyCollectionContentInset(to: collectionView)

        XCTAssertEqual(collectionView.contentInsetWriteCount, 0)
        XCTAssertEqual(collectionView.contentOffsetWriteCount, 0)
        XCTAssertEqual(collectionView.contentOffset.y, 200)
        XCTAssertEqual(collectionView.verticalScrollIndicatorInsets, collectionView.contentInset)
    }

    func testWhenTopBarHeightChangesThenCollectionKeepsItsVisibleContentPosition() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        chrome.install(in: host, contentView: content)
        chrome.layout(addressBarPosition: .bottom, interfaceMode: .regularSize)
        chrome.applyCollectionContentInset(to: collectionView)
        collectionView.contentOffset = CGPoint(x: 23, y: 200)
        let initialTopInset = collectionView.contentInset.top
        guard let navigationBar = host.subviews.first(where: { $0 is UINavigationBar }) else {
            XCTFail("Missing navigation bar")
            return
        }
        navigationBar.frame = CGRect(x: 0, y: 20, width: 390, height: 50)

        chrome.applyCollectionContentInset(to: collectionView)

        XCTAssertEqual(collectionView.contentInset.top, 70)
        XCTAssertEqual(collectionView.contentOffset, CGPoint(x: 23, y: 200 + initialTopInset - 70))
        XCTAssertEqual(collectionView.verticalScrollIndicatorInsets, collectionView.contentInset)
    }

    func testWhenEmptyStateClearanceIsAppliedThenItSitsBelowNavbarAndAbovePictogram() {
        XCTAssertEqual(TabSwitcherPageViewController.FireModeEmptyStateMetrics.spacingBelowNavbar, 10)
        XCTAssertEqual(TabSwitcherPageViewController.FireModeEmptyStateMetrics.estimatedFloatingTopClearance, 68)
        XCTAssertEqual(FireModeEmptyStateView.Constants.mainTopPadding, 24)

        let chrome = FloatingTabSwitcherChrome()
        XCTAssertEqual(
            chrome.topBarBottomOffset + TabSwitcherPageViewController.FireModeEmptyStateMetrics.spacingBelowNavbar,
            TabSwitcherPageViewController.FireModeEmptyStateMetrics.estimatedFloatingTopClearance)
    }

    func testWhenLargeSizeHasSingleEmptyTabThenEditMenuIsDisabled() {
        let chrome = makeInstalledChrome()
        chrome.actions.onEditMenuRequested = { UIMenu(children: []) }

        chrome.update(state: .largeSize(selectedCount: 0, totalCount: 1, containsWebPages: false, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        XCTAssertEqual(chrome.navigationItem.leftBarButtonItems?.first?.isEnabled, false)
    }

    func testWhenNoTabsSelectedWhileEditingThenCloseTabsDisabled() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 0, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: true)

        let closeTabsItem = chrome.toolbar.items?.first { $0.title == UserText.tabSwitcherCloseTabsButtonTitle(withCount: 0) }
        XCTAssertEqual(closeTabsItem?.isEnabled, false)
    }

    func testWhenOneTabSelectedWhileEditingThenCloseTabsTitleIncludesCount() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 1, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        let closeTabsItem = chrome.toolbar.items?.first {
            $0.title == UserText.tabSwitcherCloseTabsButtonTitle(withCount: 1)
        }
        XCTAssertNotNil(closeTabsItem)
    }

    func testWhenTabsSelectedWhileEditingThenCloseTabsEnabled() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .editingRegularSize(selectedCount: 2, totalCount: 4),
                      tabsStyle: .grid,
                      canShowSelectionMenu: true,
                      isEditing: true)

        let closeTabsItem = chrome.toolbar.items?.first { $0.title == UserText.tabSwitcherCloseTabsButtonTitle(withCount: 2) }
        XCTAssertEqual(closeTabsItem?.isEnabled, true)
    }

    func testWhenStyleMenuBuiltThenItHasGridAndListActions() {
        let chrome = makeInstalledChrome()

        chrome.update(state: .regularSize(selectedCount: 0, totalCount: 3, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                      tabsStyle: .grid,
                      canShowSelectionMenu: false,
                      isEditing: false)

        let menu = chrome.navigationItem.leftBarButtonItems?.first?.menu
        let actions = menu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(actions.count, 2)
        XCTAssertTrue(actions.contains { $0.title == UserText.tabSwitcherGridViewMenuTitle && $0.state == .on })
        XCTAssertTrue(actions.contains { $0.title == UserText.tabSwitcherListViewMenuTitle && $0.state == .off })
    }

    func testWhenLayoutIsAppliedMultipleTimesThenConstraintsArePreserved() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)
        let firstHostConstraintCount = host.constraints.count
        let firstContentConstraints = host.constraints.filter { $0.firstItem === content || $0.secondItem === content }

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)
        let secondHostConstraintCount = host.constraints.count
        let secondContentConstraints = host.constraints.filter { $0.firstItem === content || $0.secondItem === content }

        XCTAssertEqual(firstHostConstraintCount, secondHostConstraintCount)
        XCTAssertEqual(firstContentConstraints.count, 4)
        XCTAssertEqual(secondContentConstraints.count, 4)
        XCTAssertEqual(firstContentConstraints, secondContentConstraints)
        XCTAssertTrue(firstContentConstraints.allSatisfy(\.isActive))
        XCTAssertTrue(secondContentConstraints.allSatisfy(\.isActive))
    }

    func testWhenPreviewIsPresentedThenHeaderButtonsKeepTheirHorizontalPositions() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for style in [TabSwitcherViewController.TabsStyle.list, .grid] {
            let preview = UIView(frame: window.bounds)
            window.addSubview(preview)
            let destination = UIViewController()
            destination.modalPresentationStyle = .overCurrentContext
            let originalMargins = destination.view.directionalLayoutMargins
            destination.view.directionalLayoutMargins = root.systemMinimumLayoutMargins
            destination.view.frame = preview.bounds
            preview.addSubview(destination.view)
            let chrome = FloatingTabSwitcherChrome()
            let content = UIScrollView()
            chrome.install(in: destination.view, contentView: content)
            chrome.update(state: .regularSize(selectedCount: 0, totalCount: 8, containsWebPages: true, showAIChat: false, canDismissOnEmpty: true),
                          tabsStyle: style,
                          canShowSelectionMenu: false,
                          isEditing: false)
            chrome.layout(addressBarPosition: .bottom, interfaceMode: .regularSize)
            destination.view.layoutIfNeeded()
            let navigationBar = try XCTUnwrap(destination.view.subviews.first { $0 is UINavigationBar })
            func buttonFrames(in view: UIView) -> [CGRect] {
                if view is UIButton { return [view.convert(view.bounds, to: window)] }
                return view.subviews.flatMap { buttonFrames(in: $0) }
            }
            let previewFrames = buttonFrames(in: navigationBar)
            XCTAssertEqual(previewFrames.count, 2)

            await withCheckedContinuation { continuation in
                root.present(destination, animated: false) { continuation.resume() }
            }
            destination.view.directionalLayoutMargins = originalMargins
            destination.view.layoutIfNeeded()

            XCTAssertEqual(buttonFrames(in: navigationBar).map(\.minX), previewFrames.map(\.minX), style.rawValue)
            XCTAssertEqual(buttonFrames(in: navigationBar).map(\.width), previewFrames.map(\.width), style.rawValue)
            await withCheckedContinuation { continuation in
                root.dismiss(animated: false) { continuation.resume() }
            }
            preview.removeFromSuperview()
        }
    }

    func testWhenLayoutInterfaceModeChangesThenToolbarVisibilityUpdates() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .bottom, interfaceMode: .regularSize)
        XCTAssertFalse(chrome.toolbar.isHidden)

        chrome.layout(addressBarPosition: .bottom, interfaceMode: .largeSize)
        XCTAssertTrue(chrome.toolbar.isHidden)

        chrome.layout(addressBarPosition: .bottom, interfaceMode: .regularSize)
        XCTAssertFalse(chrome.toolbar.isHidden)
    }

    func testWhenChromeIsReinstalledThenLayoutConstraintsAreRecreated() {
        let chrome = FloatingTabSwitcherChrome()
        let originalHost = UIView()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: originalHost, contentView: content)
        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)
        let originalConstraints = originalHost.constraints.filter { $0.firstItem === content || $0.secondItem === content }

        chrome.install(in: host, contentView: content)
        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)

        XCTAssertTrue(originalConstraints.allSatisfy { !$0.isActive })
        XCTAssertTrue(content.superview === host)
        XCTAssertEqual(host.constraints.filter { $0.firstItem === content || $0.secondItem === content }.count, 4)
    }

    func testWhenLayoutIsAppliedThenNavigationBarUsesPlatformTopMargin() {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)

        let topConstraint = host.constraints.first {
            $0.firstItem is UINavigationBar && $0.firstAttribute == .top
        }
        XCTAssertTrue((topConstraint?.secondItem as? UILayoutGuide) === host.layoutMarginsGuide)
    }

    func testWhenLayoutIsAppliedThenToolbarUsesDeviceConcentricInsets() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)

        let leading = host.constraints.first { $0.firstItem === chrome.toolbar && $0.firstAttribute == .leading }
        let trailing = host.constraints.first { $0.firstItem === chrome.toolbar && $0.firstAttribute == .trailing }
        let bottom = host.constraints.first { $0.firstItem === chrome.toolbar && $0.firstAttribute == .bottom }

        if #available(iOS 26.0, *) {
            let horizontalGuide = host.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
            let verticalGuide = host.layoutGuide(for: .safeArea(cornerAdaptation: .vertical))
            XCTAssertTrue((leading?.secondItem as? UILayoutGuide) === horizontalGuide)
            XCTAssertTrue((trailing?.secondItem as? UILayoutGuide) === horizontalGuide)
            XCTAssertTrue((bottom?.secondItem as? UILayoutGuide) === verticalGuide)
        } else {
            XCTAssertTrue((leading?.secondItem as? UILayoutGuide) === host.safeAreaLayoutGuide)
            XCTAssertTrue((trailing?.secondItem as? UILayoutGuide) === host.safeAreaLayoutGuide)
            XCTAssertTrue((bottom?.secondItem as? UILayoutGuide) === host.safeAreaLayoutGuide)
        }
    }

    func testWhenLayoutIsAppliedThenFallbackTopBackgroundCoversContentBeforeIOS26() {
        let chrome = FloatingTabSwitcherChrome()
        let host = UIView()
        let content = UIScrollView()
        chrome.install(in: host, contentView: content)

        chrome.layout(addressBarPosition: .top, interfaceMode: .regularSize)

        if #available(iOS 26.0, *) {
            XCTAssertNil(chrome.fallbackTopBackgroundView.superview)
        } else {
            XCTAssertTrue(chrome.fallbackTopBackgroundView.superview === host)
            XCTAssertFalse(chrome.fallbackTopBackgroundView.isUserInteractionEnabled)
            XCTAssertEqual(chrome.fallbackTopBackgroundView.backgroundColor?.resolvedColor(with: host.traitCollection),
                           UIColor(designSystemColor: .background).resolvedColor(with: host.traitCollection))

            let contentIndex = host.subviews.firstIndex(of: content)
            let backgroundIndex = host.subviews.firstIndex(of: chrome.fallbackTopBackgroundView)
            let toolbarIndex = host.subviews.firstIndex(of: chrome.toolbar)

            guard let contentIndex, let backgroundIndex, let toolbarIndex else {
                XCTFail("Missing tab switcher views")
                return
            }
            XCTAssertLessThan(contentIndex, backgroundIndex)
            XCTAssertLessThan(backgroundIndex, toolbarIndex)

            let backgroundConstraints = host.constraints.filter {
                $0.firstItem === chrome.fallbackTopBackgroundView || $0.secondItem === chrome.fallbackTopBackgroundView
            }
            XCTAssertEqual(backgroundConstraints.count, 4)
            XCTAssertTrue(backgroundConstraints.allSatisfy(\.isActive))
        }
    }
}

private final class InsetTrackingCollectionView: UICollectionView {
    var contentInsetWriteCount = 0
    var contentOffsetWriteCount = 0

    override var contentInset: UIEdgeInsets {
        didSet { contentInsetWriteCount += 1 }
    }

    override var contentOffset: CGPoint {
        didSet { contentOffsetWriteCount += 1 }
    }
}
