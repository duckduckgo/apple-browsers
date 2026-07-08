//
//  FloatingTabSwitcherChrome.swift
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

import UIKit
import Core
import DesignResourcesKit
import DesignResourcesKitIcons

/// The floating ("liquid glass") tab switcher chrome. Uses out-of-the-box UIKit components
/// (a `UINavigationBar` for the top bar and a `UIToolbar` for the bottom bar) so the system
/// renders liquid glass automatically on iOS 26+. Below iOS 26 the same layout is used with a
/// solid bar background as a fallback.
///
/// Floating UI is iPhone-only and does not support the bottom address bar position, so this
/// chrome only ever handles the `regularSize` / `editingRegularSize` interface modes and always
/// pins the top bar to the top and the bottom bar to the bottom.
@MainActor
final class FloatingTabSwitcherChrome: TabSwitcherChrome {

    private enum Metrics {
        static let estimatedNavBarHeight: CGFloat = 50
        static let estimatedToolbarHeight: CGFloat = 49
        static let bottomFloatingInset: CGFloat = 8
    }

    private let navigationBar = UINavigationBar()
    let navigationItem = UINavigationItem()
    let toolbar = UIToolbar()

    private weak var hostView: UIView?
    private weak var contentView: UIScrollView?
    /// The scroll view whose edges drive the system liquid glass effect. This is the active page's
    /// collection view (which scrolls vertically), not the horizontally-paging `contentView`.
    private weak var scrollEdgeScrollView: UIScrollView?
    private weak var centerView: UIView?
    private var glassCenterContainer: UIVisualEffectView?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var title: String?
    private var isFireModeEnabled = false

    var actions = TabSwitcherChromeActions()

    var fireButton: UIBarButtonItem {
        fireItem
    }

    // MARK: - Bar items

    private lazy var tabsStyleItem = UIBarButtonItem(
        title: nil,
        image: DesignSystemImages.Glyphs.Size24.viewGrid,
        primaryAction: nil,
        menu: UIMenu(children: []))

    private lazy var doneItem: UIBarButtonItem = {
        let item = UIBarButtonItem(title: nil,
                                   image: UIImage(systemName: "checkmark"),
                                   primaryAction: UIAction { [weak self] _ in self?.actions.onDoneTapped?() },
                                   menu: nil)
        item.accessibilityLabel = UserText.navigationTitleDone
        // Prominent style gives an accent-filled glass capsule (with a contrasting white
        // checkmark) sized like the other glass bar buttons. The fill colour comes from
        // `tintColor`, set in `decorate(theme:)`.
        if #available(iOS 26.0, *) {
            item.style = .prominent
        }
        return item
    }()

    private lazy var closeItem = UIBarButtonItem(
        systemItem: .close,
        primaryAction: UIAction { [weak self] _ in self?.actions.onDoneTapped?() },
        menu: nil)

    private lazy var selectAllItem = UIBarButtonItem(
        title: UserText.selectAllTabs,
        image: nil,
        primaryAction: UIAction { [weak self] _ in self?.actions.onSelectAllTapped?() },
        menu: nil)

    private lazy var deselectAllItem = UIBarButtonItem(
        title: UserText.deselectAllTabs,
        image: nil,
        primaryAction: UIAction { [weak self] _ in self?.actions.onDeselectAllTapped?() },
        menu: nil)

    private lazy var editMenuItem = UIBarButtonItem(
        title: nil,
        image: DesignSystemImages.Glyphs.Size24.menuDotsHorizontal,
        primaryAction: nil,
        menu: UIMenu(children: []))

    private lazy var multiSelectMenuItem = UIBarButtonItem(
        title: nil,
        image: DesignSystemImages.Glyphs.Size24.menuDotsHorizontal,
        primaryAction: nil,
        menu: UIMenu(children: []))

    private lazy var fireItem = UIBarButtonItem(
        title: nil,
        image: DesignSystemImages.Glyphs.Size24.fireSolid,
        primaryAction: UIAction { [weak self] _ in self?.actions.onFireTapped?() },
        menu: nil)

    private lazy var plusItem = UIBarButtonItem(
        title: nil,
        image: DesignSystemImages.Glyphs.Size24.add,
        primaryAction: UIAction { [weak self] _ in self?.actions.onPlusTapped?() },
        menu: nil)

    private lazy var duckChatItem = UIBarButtonItem(
        title: nil,
        image: DesignSystemImages.Glyphs.Size24.aiChat,
        primaryAction: UIAction { [weak self] _ in self?.actions.onDuckChatTapped?() },
        menu: nil)

    private lazy var closeTabsItem = UIBarButtonItem(
        title: UserText.closeTabs(withCount: 0),
        image: nil,
        primaryAction: UIAction { [weak self] _ in self?.actions.onCloseTabsTapped?() },
        menu: nil)

    // MARK: - TabSwitcherChrome

    func install(in view: UIView, contentView: UIScrollView) {
        hostView = view
        self.contentView = contentView

        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        navigationBar.setItems([navigationItem], animated: false)

        configureBarMaterials()

        fireItem.accessibilityLabel = "Close all tabs and clear data"
        fireItem.accessibilityIdentifier = "Browser.Toolbar.Button.Fire"
        plusItem.accessibilityLabel = UserText.keyCommandNewTab
        duckChatItem.accessibilityIdentifier = "TabSwitcher.Button.DuckChat"
        duckChatItem.accessibilityLabel = UserText.duckAiFeatureName
        tabsStyleItem.accessibilityLabel = UserText.tabSwitcherGridViewMenuTitle

        attachTopScrollViewInteraction()
        attachBottomScrollViewInteraction()
    }

    var scrollViewTopInteraction: UIInteraction?
    var scrollViewBottomInteraction: UIInteraction?

    @available(iOS 26, *)
    func attachScrollViewInteractionToView(_ view: UIView,
                                           onEdge edge: UIRectEdge,
                                           removingExistingInteraction existingInteraction: UIInteraction?) -> UIInteraction? {
        if let existingInteraction {
            view.removeInteraction(existingInteraction)
        }

        let interaction = UIScrollEdgeElementContainerInteraction()
        interaction.scrollView = scrollEdgeScrollView
        interaction.edge = edge
        view.addInteraction(interaction)
        return interaction
    }

    func attachTopScrollViewInteraction() {
        guard #available(iOS 26, *) else { return }
        scrollViewTopInteraction = attachScrollViewInteractionToView(navigationBar, onEdge: .top, removingExistingInteraction: scrollViewTopInteraction)
    }

    func attachBottomScrollViewInteraction() {
        guard #available(iOS 26, *) else { return }
        scrollViewBottomInteraction = attachScrollViewInteractionToView(toolbar, onEdge: .bottom, removingExistingInteraction: scrollViewBottomInteraction)
    }

    func trackScrollEdge(of scrollView: UIScrollView) {
        guard scrollEdgeScrollView !== scrollView else { return }
        scrollEdgeScrollView = scrollView
        guard #available(iOS 26, *) else { return }
        (scrollViewTopInteraction as? UIScrollEdgeElementContainerInteraction)?.scrollView = scrollView
        (scrollViewBottomInteraction as? UIScrollEdgeElementContainerInteraction)?.scrollView = scrollView
    }

    func setCenterView(_ view: UIView?) {
        centerView = view
        glassCenterContainer = nil
    }

    /// Wraps the mode switcher in a glass capsule on iOS 26 so it stays legible over the
    /// glass navigation bar (otherwise it washes out). Below iOS 26 the raw view is used.
    private func centerTitleView() -> UIView? {
        guard let centerView else { return nil }
        guard #available(iOS 26.0, *) else { return centerView }

        if let glassCenterContainer { return glassCenterContainer }

        let effectView = UIVisualEffectView(effect: UIGlassEffect())
        effectView.cornerConfiguration = .capsule()
        centerView.translatesAutoresizingMaskIntoConstraints = false
        effectView.contentView.addSubview(centerView)
        NSLayoutConstraint.activate([
            centerView.topAnchor.constraint(equalTo: effectView.contentView.topAnchor),
            centerView.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor),
            centerView.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor),
            centerView.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor),
        ])
        glassCenterContainer = effectView
        return effectView
    }

    func setTitle(_ title: String?) {
        self.title = title
    }

    func configurePlusButtonLongPressMenu(isFireModeEnabled: Bool) {
        self.isFireModeEnabled = isFireModeEnabled
        guard isFireModeEnabled else {
            plusItem.menu = nil
            return
        }

        plusItem.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                Pixel.fire(pixel: .tabLongPressMenuDisplayed, withAdditionalParameters: [
                    PixelParameters.source: "tab_switcher"
                ])
                completion([
                    UIAction(title: UserText.actionNewFireTab,
                             image: DesignSystemImages.Glyphs.Size16.fireWindow) { [weak self] _ in
                        Pixel.fire(pixel: .tabLongPressMenuNewFireTab, withAdditionalParameters: [
                            PixelParameters.source: "tab_switcher"
                        ])
                        self?.actions.onNewFireTabTapped?()
                    },
                    UIAction(title: UserText.actionNewTab,
                             image: DesignSystemImages.Glyphs.Size16.add) { [weak self] _ in
                        Pixel.fire(pixel: .tabLongPressMenuNewNormalTab, withAdditionalParameters: [
                            PixelParameters.source: "tab_switcher"
                        ])
                        self?.actions.onNewNormalTabTapped?()
                    }
                ])
            }
        ])
    }

    func decorate(theme: Theme) {
        let tint = UIColor(singleUseColor: .toolbarButton)
        navigationBar.tintColor = tint
        toolbar.tintColor = tint
        doneItem.tintColor = UIColor(designSystemColor: .accentPrimary)
        configureBarMaterials()
    }

    func update(state: TabSwitcherToolbarState,
                tabsStyle: TabSwitcherViewController.TabsStyle,
                canShowSelectionMenu: Bool,
                isEditing: Bool) {
        let params = Parameters(state: state)

        tabsStyleItem.image = tabsStyle.image
        tabsStyleItem.menu = makeTabsStyleMenu(current: tabsStyle)
        editMenuItem.menu = actions.onEditMenuRequested?()
        multiSelectMenuItem.menu = actions.onMultiSelectMenuRequested?()
        multiSelectMenuItem.isEnabled = canShowSelectionMenu

        doneItem.isEnabled = params.canDismissOnEmpty || params.totalCount > 0

        if isEditing {
            navigationItem.titleView = nil
            navigationItem.title = title
            navigationItem.leftBarButtonItems = [closeItem]
            navigationItem.rightBarButtonItems = [params.selectedCount == params.totalCount ? deselectAllItem : selectAllItem]

            closeTabsItem.title = UserText.closeTabs(withCount: params.selectedCount)
            closeTabsItem.isEnabled = params.selectedCount > 0
            toolbar.setItems([multiSelectMenuItem, .flexibleSpace(), closeTabsItem], animated: false)
        } else {
            navigationItem.title = nil
            navigationItem.titleView = centerTitleView()
            navigationItem.leftBarButtonItems = [tabsStyleItem]
            navigationItem.rightBarButtonItems = [doneItem]

            var items: [UIBarButtonItem] = [editMenuItem, .flexibleSpace(), fireItem, .flexibleSpace(), plusItem]
            if params.showAIChat {
                items.append(duckChatItem)
            }
            toolbar.setItems(items, animated: false)
        }
    }

    func applyCollectionContentInset(to collectionView: UICollectionView) {
        let navHeight = navigationBar.frame.height > 0 ? navigationBar.frame.height : Metrics.estimatedNavBarHeight
        let toolbarHeight = toolbar.frame.height > 0 ? toolbar.frame.height : Metrics.estimatedToolbarHeight
        collectionView.contentInset.top = navHeight
        collectionView.contentInset.bottom = toolbarHeight + Metrics.bottomFloatingInset
    }

    func layout(addressBarPosition: AddressBarPosition,
                interfaceMode: TabSwitcherViewController.InterfaceMode) {
        guard let hostView, let contentView else {
            assertionFailure("FloatingTabSwitcherChrome.layout called before install")
            return
        }

        contentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = []

        [navigationBar, toolbar, contentView].forEach { $0.removeFromSuperview() }

        // Content sits behind the glass bars so it scrolls under them.
        hostView.addSubview(contentView)
        hostView.addSubview(toolbar)
        hostView.addSubview(navigationBar)

        let constraints = [
            navigationBar.topAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor),

            contentView.topAnchor.constraint(equalTo: hostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),

            toolbar.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        layoutConstraints = constraints
    }

    // MARK: - Private

    private func makeTabsStyleMenu(current: TabSwitcherViewController.TabsStyle) -> UIMenu {
        let grid = UIAction(title: UserText.tabSwitcherGridViewMenuTitle,
                            image: DesignSystemImages.Glyphs.Size24.viewGrid,
                            state: current == .grid ? .on : .off) { [weak self] _ in
            self?.actions.onSelectTabsStyle?(.grid)
        }
        let list = UIAction(title: UserText.tabSwitcherListViewMenuTitle,
                            image: DesignSystemImages.Glyphs.Size24.viewList,
                            state: current == .list ? .on : .off) { [weak self] _ in
            self?.actions.onSelectTabsStyle?(.list)
        }
        return UIMenu(children: [grid, list])
    }

    private func configureBarMaterials() {
        if #available(iOS 26, *) {
            // The system renders liquid glass automatically for the navigation bar and toolbar.
            return
        }

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(designSystemColor: .background)
        navAppearance.shadowColor = .clear
        navigationBar.standardAppearance = navAppearance
        navigationBar.scrollEdgeAppearance = navAppearance
        navigationBar.compactAppearance = navAppearance

        let toolbarAppearance = UIToolbarAppearance()
        toolbarAppearance.configureWithOpaqueBackground()
        toolbarAppearance.backgroundColor = UIColor(designSystemColor: .background)
        toolbarAppearance.shadowColor = .clear
        toolbar.standardAppearance = toolbarAppearance
        toolbar.compactAppearance = toolbarAppearance
    }
}

private extension FloatingTabSwitcherChrome {
    struct Parameters {
        var selectedCount = 0
        var totalCount = 0
        var showAIChat = false
        var canDismissOnEmpty = true

        init(state: TabSwitcherToolbarState) {
            switch state {
            case .regularSize(let selectedCount, let totalCount, _, let showAIChat, let canDismissOnEmpty),
                 .largeSize(let selectedCount, let totalCount, _, let showAIChat, let canDismissOnEmpty):
                self.selectedCount = selectedCount
                self.totalCount = totalCount
                self.showAIChat = showAIChat
                self.canDismissOnEmpty = canDismissOnEmpty
            case .editingRegularSize(let selectedCount, let totalCount),
                 .editingLargeSize(let selectedCount, let totalCount):
                self.selectedCount = selectedCount
                self.totalCount = totalCount
            }
        }
    }
}
