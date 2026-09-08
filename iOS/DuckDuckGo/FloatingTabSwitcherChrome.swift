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
import PixelKit

/// The floating ("liquid glass") tab switcher chrome. It uses system bars to render liquid glass
/// on iOS 26+ and falls back to solid bar backgrounds on earlier versions.
@MainActor
final class FloatingTabSwitcherChrome: TabSwitcherChrome {

    private enum Metrics {
        static let estimatedNavBarHeight: CGFloat = 50
        static let estimatedToolbarHeight: CGFloat = 49
        static let topFloatingInset: CGFloat = 8
        static let bottomFloatingInset: CGFloat = 8
        static let fallbackToolbarHorizontalPadding: CGFloat = 20
        static let fallbackAIButtonSpacing: CGFloat = 12
        static let menuButtonSize: CGFloat = 36
        static let fallbackMenuButtonSize: CGFloat = 44
    }

    private let navigationBar = UINavigationBar()
    let navigationItem = UINavigationItem()
    let toolbar = UIToolbar()
    let fallbackTopBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .background)
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private weak var hostView: UIView?
    private weak var contentView: UIScrollView?
    /// The scroll view whose edges drive the system liquid glass effect. This is the active page's
    /// collection view (which scrolls vertically), not the horizontally-paging `contentView`.
    private weak var scrollEdgeScrollView: UIScrollView?
    private weak var centerView: UIView?
    private var glassCenterContainer: UIVisualEffectView?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var isFireModeEnabled = false
    private var interfaceMode: TabSwitcherViewController.InterfaceMode = .regularSize

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
        let action = UIAction { [weak self] _ in self?.actions.onDoneTapped?() }
        let item: UIBarButtonItem
        if #available(iOS 26.0, *) {
            item = UIBarButtonItem(title: nil,
                                   image: DesignSystemImages.Glyphs.Size24.check,
                                   primaryAction: action,
                                   menu: nil)
            item.style = .prominent
        } else {
            item = UIBarButtonItem(systemItem: .done,
                                   primaryAction: action,
                                   menu: nil)
        }
        item.accessibilityLabel = UserText.navigationTitleDone
        return item
    }()

    private lazy var selectionTitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxHeadline()
        label.textColor = UIColor(designSystemColor: .textPrimary)
        return label
    }()

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

    private lazy var editMenuButton: FloatingTabSwitcherMenuButton = {
        let button = FloatingTabSwitcherMenuButton()
        button.configuration = .plain()
        button.configuration?.image = menuImage
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = UserText.actionGenericEdit
        button.translatesAutoresizingMaskIntoConstraints = false
        let buttonSize: CGFloat
        if #available(iOS 26.0, *) {
            buttonSize = Metrics.menuButtonSize
        } else {
            buttonSize = Metrics.fallbackMenuButtonSize
        }
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: buttonSize),
            button.heightAnchor.constraint(equalToConstant: buttonSize),
        ])
        button.onMenuDismissed = { [weak self] in
            self?.actions.onEditMenuDismissed?()
        }
        return button
    }()

    private lazy var editMenuItem: UIBarButtonItem = {
        let item = UIBarButtonItem(customView: editMenuButton)
        item.title = UserText.actionGenericEdit
        return item
    }()

    private lazy var multiSelectMenuItem = UIBarButtonItem(
        title: nil,
        image: menuImage,
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
        title: UserText.tabSwitcherCloseTabsButtonTitle(withCount: 0),
        image: nil,
        primaryAction: UIAction { [weak self] _ in self?.actions.onCloseTabsTapped?() },
        menu: nil)

    // MARK: - TabSwitcherChrome

    func install(in view: UIView, contentView: UIScrollView) {
        hostView = view
        self.contentView = contentView

        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.insetsLayoutMarginsFromSafeArea = false
        toolbar.preservesSuperviewLayoutMargins = false
        toolbar.layoutMargins = .zero

        navigationBar.setItems([navigationItem], animated: false)

        configureBarMaterials()

        fireItem.accessibilityLabel = "Close all tabs and clear data"
        fireItem.accessibilityIdentifier = "Browser.Toolbar.Button.Fire"
        plusItem.accessibilityLabel = UserText.keyCommandNewTab
        plusItem.accessibilityIdentifier = "TabSwitcher.Button.NewTab"
        doneItem.accessibilityIdentifier = "TabSwitcher.Button.Done"
        duckChatItem.accessibilityIdentifier = "TabSwitcher.Button.DuckChat"
        duckChatItem.accessibilityLabel = UserText.duckAiFeatureName
        tabsStyleItem.accessibilityLabel = UserText.tabSwitcherGridViewMenuTitle
        editMenuItem.accessibilityLabel = UserText.actionGenericEdit

        attachTopScrollViewInteraction()
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
        // Intentionally empty: the toolbar is inset to match the webview capsule.
        // A scroll-edge interaction would apply a second, larger device-concentric inset.
    }

    func trackScrollEdge(of scrollView: UIScrollView) {
        guard scrollEdgeScrollView !== scrollView else { return }
        scrollEdgeScrollView = scrollView
        guard #available(iOS 26, *) else { return }
        (scrollViewTopInteraction as? UIScrollEdgeElementContainerInteraction)?.scrollView = scrollView
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
        selectionTitleLabel.text = title
        selectionTitleLabel.sizeToFit()
        navigationBar.setNeedsLayout()
    }

    func configurePlusButtonLongPressMenu(isFireModeEnabled: Bool) {
        self.isFireModeEnabled = isFireModeEnabled
        guard isFireModeEnabled else {
            plusItem.menu = nil
            return
        }

        plusItem.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                PixelKit.fire(Pixel.Event.tabLongPressMenuDisplayed, options: .parameters([
                    PixelParameters.source: "tab_switcher"
                ]))
                completion([
                    UIAction(title: UserText.actionNewFireTab,
                             image: DesignSystemImages.Glyphs.Size16.fireWindow) { [weak self] _ in
                        PixelKit.fire(Pixel.Event.tabLongPressMenuNewFireTab, options: .parameters([
                            PixelParameters.source: "tab_switcher"
                        ]))
                        self?.actions.onNewFireTabTapped?()
                    },
                    UIAction(title: UserText.actionNewTab,
                             image: DesignSystemImages.Glyphs.Size16.add) { [weak self] _ in
                        PixelKit.fire(Pixel.Event.tabLongPressMenuNewNormalTab, options: .parameters([
                            PixelParameters.source: "tab_switcher"
                        ]))
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
        editMenuButton.configuration?.baseForegroundColor = tint
        if #available(iOS 26.0, *) {
            doneItem.tintColor = UIColor(designSystemColor: .accentPrimary)
        } else {
            doneItem.tintColor = theme.navigationBarTintColor
        }
        configureBarMaterials()
    }

    func update(state: TabSwitcherToolbarState,
                tabsStyle: TabSwitcherViewController.TabsStyle,
                canShowSelectionMenu: Bool,
                isEditing: Bool) {
        let params = Parameters(state: state)
        interfaceMode = params.interfaceMode

        tabsStyleItem.image = tabsStyle.image
        tabsStyleItem.primaryAction = nil
        tabsStyleItem.menu = makeTabsStyleMenu(current: tabsStyle)
        editMenuButton.menu = actions.onEditMenuRequested?()
        multiSelectMenuItem.menu = actions.onMultiSelectMenuRequested?()
        multiSelectMenuItem.isEnabled = canShowSelectionMenu
        editMenuItem.isEnabled = params.totalCount > 1 || params.containsWebPages
        editMenuButton.isEnabled = editMenuItem.isEnabled
        configureBackgroundSharing(isLarge: params.interfaceMode.isLarge, isEditing: isEditing)

        let isDoneEnabled = params.canDismissOnEmpty || params.totalCount > 0
        doneItem.isEnabled = isDoneEnabled

        if params.interfaceMode == .editingLargeSize {
            navigationItem.title = nil
            navigationItem.titleView = selectionTitleLabel
            navigationItem.leftBarButtonItems = [doneItem]
            navigationItem.rightBarButtonItems = [multiSelectMenuItem]
            setToolbarItems([])
        } else if params.interfaceMode == .largeSize {
            navigationItem.title = nil
            navigationItem.titleView = centerTitleView()
            navigationItem.leftBarButtonItems = [editMenuItem, tabsStyleItem]

            var items = [doneItem, fireItem, plusItem]
            if params.showAIChat {
                items.append(duckChatItem)
            }
            navigationItem.rightBarButtonItems = items
            setToolbarItems([])
        } else if isEditing {
            navigationItem.title = nil
            navigationItem.titleView = selectionTitleLabel
            navigationItem.leftBarButtonItems = [multiSelectMenuItem]
            navigationItem.rightBarButtonItems = [params.selectedCount == params.totalCount ? deselectAllItem : selectAllItem]

            closeTabsItem.title = UserText.tabSwitcherCloseTabsButtonTitle(withCount: params.selectedCount)
            closeTabsItem.isEnabled = params.selectedCount > 0
            setToolbarItems([closeTabsItem, .flexibleSpace(), doneItem])
        } else {
            navigationItem.title = nil
            navigationItem.titleView = centerTitleView()
            navigationItem.leftBarButtonItems = [tabsStyleItem]
            navigationItem.rightBarButtonItems = [doneItem]

            var items: [UIBarButtonItem] = [editMenuItem, .flexibleSpace(), fireItem, .flexibleSpace(), plusItem]
            if params.showAIChat {
                if #unavailable(iOS 26.0) {
                    items.append(.fixedSpace(Metrics.fallbackAIButtonSpacing))
                }
                items.append(duckChatItem)
            }
            setToolbarItems(items)
        }

        toolbar.isHidden = params.interfaceMode.isLarge
    }

    /// Distance from the host's top to the bottom of the floating navigation bar.
    /// Both pages use this so tab cards keep the same top spacing during a paging swipe.
    var topBarBottomOffset: CGFloat {
        if navigationBar.frame.maxY > 0 {
            return navigationBar.frame.maxY
        }
        return Metrics.topFloatingInset + Metrics.estimatedNavBarHeight
    }

    func applyCollectionContentInset(to collectionView: UICollectionView) {
        collectionView.contentInsetAdjustmentBehavior = .never

        let topInset = topBarBottomOffset
        let toolbarHeight = toolbar.frame.height > 0 ? toolbar.frame.height : Metrics.estimatedToolbarHeight
        let bottomClearance: CGFloat
        if interfaceMode.isLarge {
            bottomClearance = 0
        } else if let hostView, toolbar.frame.height > 0 {
            let toolbarFrameInHost = toolbar.convert(toolbar.bounds, to: hostView)
            bottomClearance = hostView.bounds.maxY - toolbarFrameInHost.minY + Metrics.bottomFloatingInset
        } else {
            bottomClearance = toolbarHeight + Metrics.bottomFloatingInset
        }

        let previousTopInset = collectionView.contentInset.top
        let wasScrolledToTop = abs(collectionView.contentOffset.y + previousTopInset) < 1

        collectionView.contentInset.top = topInset
        collectionView.contentInset.bottom = bottomClearance
        collectionView.verticalScrollIndicatorInsets = collectionView.contentInset

        if wasScrolledToTop {
            collectionView.contentOffset.y = -topInset
        } else {
            collectionView.contentOffset.y += previousTopInset - topInset
        }
    }

    func layout(addressBarPosition: AddressBarPosition,
                interfaceMode: TabSwitcherViewController.InterfaceMode) {
        guard let hostView, let contentView else {
            assertionFailure("FloatingTabSwitcherChrome.layout called before install")
            return
        }

        self.interfaceMode = interfaceMode
        contentView.translatesAutoresizingMaskIntoConstraints = false
        toolbar.isHidden = interfaceMode.isLarge

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = []

        [navigationBar, toolbar, fallbackTopBackgroundView, contentView].forEach { $0.removeFromSuperview() }

        // Content sits behind the glass bars so it scrolls under them.
        hostView.addSubview(contentView)
        if #unavailable(iOS 26.0) {
            hostView.addSubview(fallbackTopBackgroundView)
        }
        hostView.addSubview(toolbar)
        hostView.addSubview(navigationBar)

        let topGuide: UILayoutGuide
        if #available(iOS 26, *), UIDevice.current.userInterfaceIdiom == .pad {
            topGuide = hostView.layoutGuide(for: .margins(cornerAdaptation: .vertical))
        } else {
            topGuide = hostView.layoutMarginsGuide
        }

        var constraints = [
            navigationBar.topAnchor.constraint(equalTo: topGuide.topAnchor, constant: Metrics.topFloatingInset),
            navigationBar.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor),

            contentView.topAnchor.constraint(equalTo: hostView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ]

        if #available(iOS 26.0, *) {
            let horizontalGuide = hostView.layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))
            let verticalGuide = hostView.layoutGuide(for: .safeArea(cornerAdaptation: .vertical))
            constraints.append(contentsOf: [
                toolbar.leadingAnchor.constraint(equalTo: horizontalGuide.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: horizontalGuide.trailingAnchor),
                toolbar.bottomAnchor.constraint(equalTo: verticalGuide.bottomAnchor),
            ])
        } else {
            constraints.append(contentsOf: [
                toolbar.leadingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.trailingAnchor),
                toolbar.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor),
            ])
        }
        if #unavailable(iOS 26.0) {
            constraints.append(contentsOf: [
                fallbackTopBackgroundView.topAnchor.constraint(equalTo: hostView.topAnchor),
                fallbackTopBackgroundView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                fallbackTopBackgroundView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
                fallbackTopBackgroundView.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate(constraints)
        layoutConstraints = constraints
    }

    // MARK: - Private

    private var menuImage: UIImage {
        if #available(iOS 26.0, *) {
            return DesignSystemImages.Glyphs.Size24.menuDotsHorizontal
        }
        return DesignSystemImages.Glyphs.Size24.moreApple
    }

    private func setToolbarItems(_ items: [UIBarButtonItem]) {
        if items.isEmpty {
            toolbar.setItems([], animated: false)
            return
        }

        if #available(iOS 26.0, *) {
            toolbar.setItems(items, animated: false)
        } else {
            toolbar.setItems([.fixedSpace(Metrics.fallbackToolbarHorizontalPadding)] + items
                             + [.fixedSpace(Metrics.fallbackToolbarHorizontalPadding)],
                             animated: false)
        }
    }

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

    private func configureBackgroundSharing(isLarge: Bool, isEditing: Bool) {
        guard #available(iOS 26.0, *) else { return }
        let shouldShareBackground = !isLarge && !isEditing
        editMenuItem.sharesBackground = shouldShareBackground
        editMenuItem.hidesSharedBackground = false
        tabsStyleItem.sharesBackground = shouldShareBackground
        fireItem.sharesBackground = shouldShareBackground
        doneItem.sharesBackground = shouldShareBackground
        closeTabsItem.sharesBackground = false
        multiSelectMenuItem.sharesBackground = false
        plusItem.sharesBackground = true
        duckChatItem.sharesBackground = true
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

private final class FloatingTabSwitcherMenuButton: UIButton {

    var onMenuDismissed: (() -> Void)?

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                         willEndFor configuration: UIContextMenuConfiguration,
                                         animator: UIContextMenuInteractionAnimating?) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)

        guard let animator else {
            DispatchQueue.main.async { [weak self] in
                self?.onMenuDismissed?()
            }
            return
        }

        animator.addCompletion { [weak self] in
            self?.onMenuDismissed?()
        }
    }
}

private extension FloatingTabSwitcherChrome {
    struct Parameters {
        var selectedCount = 0
        var totalCount = 0
        var containsWebPages = false
        var showAIChat = false
        var canDismissOnEmpty = true
        var interfaceMode: TabSwitcherViewController.InterfaceMode = .regularSize

        init(state: TabSwitcherToolbarState) {
            switch state {
            case .regularSize(let selectedCount, let totalCount, let containsWebPages, let showAIChat, let canDismissOnEmpty),
                 .largeSize(let selectedCount, let totalCount, let containsWebPages, let showAIChat, let canDismissOnEmpty):
                self.selectedCount = selectedCount
                self.totalCount = totalCount
                self.containsWebPages = containsWebPages
                self.showAIChat = showAIChat
                self.canDismissOnEmpty = canDismissOnEmpty
            case .editingRegularSize(let selectedCount, let totalCount),
                 .editingLargeSize(let selectedCount, let totalCount):
                self.selectedCount = selectedCount
                self.totalCount = totalCount
            }
            self.interfaceMode = state.interfaceMode
        }
    }
}
