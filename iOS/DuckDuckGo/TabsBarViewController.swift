//
//  TabsBarViewController.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Combine
import Core
import DesignResourcesKit
import DesignResourcesKitIcons
import BrowserServicesKit
import AIChat
import Persistence
import PrivacyConfig

protocol TabsBarDelegate: NSObjectProtocol {
    
    func tabsBar(_ controller: TabsBarViewController, didSelectTabAtIndex index: Int)
    func tabsBar(_ controller: TabsBarViewController, didRemoveTabAtIndex index: Int)
    func tabsBar(_ controller: TabsBarViewController, didRequestMoveTabFromIndex fromIndex: Int, toIndex: Int)
    func tabsBarDidRequestNewTab(_ controller: TabsBarViewController)
    func tabsBarDidRequestForgetAll(_ controller: TabsBarViewController, fireRequest: FireRequest)
    func tabsBarDidRequestFireEducationDialog(_ controller: TabsBarViewController)
    func tabsBarDidRequestTabSwitcher(_ controller: TabsBarViewController)
    func tabsBarDidRequestNewFireTab(_ controller: TabsBarViewController)
    func tabsBarDidRequestNewNormalTab(_ controller: TabsBarViewController)
    func tabsBarDidRequestAIChat(_ controller: TabsBarViewController)
    func tabsBarDidRequestToggleAIChatContextualSheet(_ controller: TabsBarViewController)
    func tabsBarDidRequestOpenAISettings(_ controller: TabsBarViewController)
    func tabsBarDidRequestDismissContextualSheet(_ controller: TabsBarViewController, completion: @escaping () -> Void)

}

class TabsBarViewController: UIViewController, UIGestureRecognizerDelegate {

    public static let viewDidLayoutNotification = Notification.Name("com.duckduckgo.app.TabsBarViewControllerViewDidLayout")
    
    struct Constants {

        static let buttonWidth: CGFloat = 44
        static let buttonHeight: CGFloat = 40
        static let stackSpacing: CGFloat = 12
        static let minItemWidth: CGFloat = 120
        static let maxItemWidthFraction: CGFloat = 0.33
        static let narrowMaxItemWidthFraction: CGFloat = 0.5
        static let leadingInset: CGFloat = 16
    }
    
    enum NewTabType {
        case normal
        case fire
        case currentMode
    }
    
    private let tabsBarView = TabsBarView()

    var collectionView: UICollectionView { tabsBarView.collectionView }
    var buttonsStack: UIStackView { tabsBarView.buttonsStack }
    var buttonsBackground: UIView { tabsBarView.buttonsBackground }

    lazy var fireButton: UIButton = {
        createButton(image: DesignSystemImages.Glyphs.Size24.fireSolid)
    }()

    lazy var addTabButton: UIButton = {
        createButton(image: DesignSystemImages.Glyphs.Size24.add)
    }()

    lazy var aiChatChip: DuckAIChromeChipView = {
        let chip = DuckAIChromeChipView()
        // Hidden until updateAIChatButtonVisibility() runs (viewWillAppear / settings change).
        // Prevents a brief visible-then-hidden flicker if the flag or per-shortcut preference is off.
        chip.isHidden = true
        return chip
    }()

    weak var delegate: TabsBarDelegate?
    var tabManager: TabManaging?
    var historyManager: HistoryManaging?
    var fireproofing: Fireproofing?
    var aiChatSettings: AIChatSettingsProvider?
    var featureFlagger: FeatureFlagger? {
        didSet {
            registerForFeatureFlagChanges()
        }
    }
    var keyValueStore: ThrowingKeyValueStoring?
    var daxDialogsManager: DaxDialogsManaging?
    var fireModeCapability: FireModeCapable? {
        didSet {
            configureTabSwitcherLongPressMenu()
            configureAddTabButtonLongPressMenu()
        }
    }
    private weak var tabsModel: TabsModelManaging?

    private lazy var tabSwitcherButton: TabSwitcherStaticButton = TabSwitcherStaticButton(showMenuOnLongPress: false)

    private let longPressTabGesture = UILongPressGestureRecognizer()
    private var cancellables = Set<AnyCancellable>()
    
    private weak var pressedCell: TabsBarCell?

    var tabsCount: Int {
        return tabsModel?.count ?? 0
    }
    
    var hasUnread: Bool {
        return tabsModel?.hasUnread ?? false
    }
    
    var currentIndex: Int? {
        return tabsModel?.currentIndex
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    static func create() -> TabsBarViewController {
        TabsBarViewController()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = tabsBarView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        setUpSubviews()
        decorate()
        configureGestures()
        enableInteractionsWithPointer()
        registerForAIChatSettingsChanges()
    }

    private func setUpSubviews() {

        collectionView.clipsToBounds = true
        collectionView.delegate = self
        collectionView.dataSource = self
        // Prefetching can drop a still-visible cell during a fast scroll and not re-display it
        // (a gap). Prefetching gains are marginal here and on top of that we're not handling it properly (no willDisplay).
        collectionView.isPrefetchingEnabled = false
        collectionView.register(TabsBarCell.self, forCellWithReuseIdentifier: TabsBarCell.reuseIdentifier)

        addTabButton.setImage(DesignSystemImages.Glyphs.Size24.add, for: .normal)
        fireButton.setImage(DesignSystemImages.Glyphs.Size24.fireSolid, for: .normal)

        buttonsStack.spacing = Constants.stackSpacing
        buttonsStack.alignment = .center

        buttonsStack.addArrangedSubview(addTabButton)
        buttonsStack.addArrangedSubview(aiChatChip)
        buttonsStack.addArrangedSubview(fireButton)
        buttonsStack.addArrangedSubview(tabSwitcherButton)

        addTabButton.addTarget(self, action: #selector(onNewTabPressed), for: .touchUpInside)
        aiChatChip.textButton.addTarget(self, action: #selector(onAIChatPressed), for: .touchUpInside)
        aiChatChip.iconButton.addTarget(self, action: #selector(onAIChatContextualSheetIconPressed), for: .touchUpInside)
        configureAIChatChipMenu()
        fireButton.addTarget(self, action: #selector(onFireButtonPressed), for: .touchUpInside)
        tabSwitcherButton.delegate = self

        // Set width and height for all icon buttons
        // Width is set to 44 to properly align with OmniBar buttons that are displayed below
        [addTabButton, fireButton, tabSwitcherButton].forEach { button in
            button.heightAnchor.constraint(equalToConstant: Constants.buttonHeight).isActive = true
            button.widthAnchor.constraint(equalToConstant: Constants.buttonWidth).isActive = true
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabSwitcherButton.layoutSubviews()
        reloadData()
        updateAIChatButtonVisibility()
    }

    private func registerForAIChatSettingsChanges() {
        NotificationCenter.default.publisher(for: .aiChatSettingsChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAIChatButtonVisibility()
            }
            .store(in: &cancellables)
    }

    private func registerForFeatureFlagChanges() {
        // The chrome shortcut flag is .internalOnly, so flipping internal-user state at runtime
        // (debug menu) changes visibility — react to it without requiring an app restart.
        featureFlagger?.internalUserDecider.isInternalUserPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAIChatButtonVisibility()
            }
            .store(in: &cancellables)

        guard let overridesHandler = featureFlagger?.localOverrides?.actionHandler as? FeatureFlagOverridesPublishingHandler<FeatureFlag> else {
            return
        }
        overridesHandler.flagDidChangePublisher
            .filter { $0.0 == .aiChatChromeShortcutIPad }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAIChatButtonVisibility()
            }
            .store(in: &cancellables)
    }

    private func updateAIChatButtonVisibility() {
        guard let featureFlagger, let aiChatSettings else {
            aiChatChip.isHidden = true
            return
        }
        let shortcutEnabled = aiChatSettings.isAIChatTabBarUserSettingsEnabled
        let showDuckAIButton = aiChatSettings.isAIChatTabBarDuckAIButtonVisible
        let showContextualSheetButton = aiChatSettings.isAIChatTabBarContextualSheetButtonVisible
        aiChatChip.isHidden = !DuckAIChromeShortcutVisibility.isChromeButtonVisible(
            featureFlagger: featureFlagger,
            isTabBarShortcutEnabled: shortcutEnabled,
            isDuckAIButtonVisible: showDuckAIButton,
            isContextualSheetButtonVisible: showContextualSheetButton
        )
        aiChatChip.setTextVisible(showDuckAIButton)
        aiChatChip.setIconVisible(showContextualSheetButton)
    }

    /// Pushes per-tab state into the chip. Called by `MainViewController` when the
    /// current tab changes or its contextual sheet is presented/dismissed.
    func updateAIChatChipState(isContextualSheetPresented: Bool) {
        aiChatChip.setSheetState(isContextualSheetPresented ? .open : .closed)
    }

    @objc private func onFireButtonPressed() {
        
        func showClearDataAlert() {
            guard let tabManager, let daxDialogsManager else {
                assertionFailure("TabsBarViewController is not configured properly. Check MainViewController.loadTabsBarIfNeeded()")
                return
            }
            let presenter = FireConfirmationPresenter()
            presenter.presentFireConfirmation(
                on: self,
                attachPopoverTo: fireButton,
                tabViewModel: tabManager.viewModelForCurrentTab(),
                pixelSource: .browsing,
                fireContext: .default(daxDialogsManager: daxDialogsManager),
                isSingleTab: tabManager.currentTabsModel.count == 1,
                browsingMode: tabManager.currentBrowsingMode,
                onConfirm: { [weak self] fireRequest in
                    guard let self = self else { return }
                    self.delegate?.tabsBarDidRequestForgetAll(self, fireRequest: fireRequest)
                },
                onCancel: { }
            )
        }

        delegate?.tabsBarDidRequestFireEducationDialog(self)
        delegate?.tabsBarDidRequestDismissContextualSheet(self) {
            showClearDataAlert()
        }
    }

    @objc private func onNewTabPressed() {
        DailyPixel.fireDailyAndCount(pixel: .tabBarNewTab)
        requestNewTab(type: .currentMode)
    }

    @objc private func onAIChatPressed() {
        DailyPixel.fireDailyAndCount(pixel: .openAIChatFromNavigationBarShortcut)
        delegate?.tabsBarDidRequestAIChat(self)
    }

    @objc private func onAIChatContextualSheetIconPressed() {
        if aiChatChip.sheetState == .closed {
            DailyPixel.fireDailyAndCount(pixel: .aiChatNavigationBarContextualSheetOpened)
        }
        delegate?.tabsBarDidRequestToggleAIChatContextualSheet(self)
    }

    func refresh(tabsModel: TabsModelManaging?, scrollToSelected: Bool = false) {
        self.tabsModel = tabsModel

        tabSwitcherButton.isAccessibilityElement = true
        tabSwitcherButton.accessibilityLabel = UserText.tabSwitcherAccessibilityLabel
        tabSwitcherButton.accessibilityHint = UserText.numberOfTabs(tabsCount)

        recomputeItemSize()
        reloadData()
        fireUsageDailyPixels()

        if scrollToSelected {
            DispatchQueue.main.async {
                if let currentIndex = self.currentIndex {
                    self.collectionView.scrollToItem(at: IndexPath(row: currentIndex, section: 0), at: [], animated: true)
                }
            }
        }

    }

    /// After a resize/rotation reflows the strip, nudge the current tab fully into view, but only if
    /// it ended up partially clipped. If it's already fully visible there's nothing to do; if the
    /// user had scrolled it entirely out of view, their scroll position is left untouched.
    func scrollCurrentTabIntoView() {
        DispatchQueue.main.async {
            guard let currentIndex = self.currentIndex else { return }
            let indexPath = IndexPath(row: currentIndex, section: 0)
            guard let attributes = self.collectionView.layoutAttributesForItem(at: indexPath) else { return }
            let visibleRect = CGRect(origin: self.collectionView.contentOffset, size: self.collectionView.bounds.size)
            let isPartiallyClipped = visibleRect.intersects(attributes.frame) && !visibleRect.contains(attributes.frame)
            guard isPartiallyClipped else { return }
            self.collectionView.scrollToItem(at: indexPath, at: [], animated: true)
        }
    }

    private func recomputeItemSize() {
        let availableWidth = collectionView.frame.size.width
        guard tabsCount > 0 else { return }

        let itemWidth = Self.itemWidth(
            availableWidth: availableWidth,
            visibleItems: tabsCount,
            minWidth: Constants.minItemWidth,
            maxWidth: maxItemWidth(forStripWidth: availableWidth)
        )

        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.itemSize = CGSize(width: itemWidth, height: view.frame.size.height)
        }
    }

    /// Half the strip, but in landscape also capped at a third of the full-screen strip so a resize
    /// to full width eases to a third instead of snapping.
    private func maxItemWidth(forStripWidth availableWidth: CGFloat) -> CGFloat {
        let half = availableWidth * Constants.narrowMaxItemWidthFraction
        guard let window = view.window, let windowScene = window.windowScene,
              windowScene.interfaceOrientation.isLandscape else {
            return half
        }
        let chrome = window.bounds.width - availableWidth
        let screenBounds = windowScene.screen.bounds
        let landscapeFullStripWidth = max(screenBounds.width, screenBounds.height) - chrome
        return min(half, landscapeFullStripWidth * Constants.maxItemWidthFraction)
    }

    /// Once-per-day baseline snapshots: open-tab count (bucketed) and whether the strip overflows
    /// (scroll required). DailyPixel dedupes per day, so these capture the first qualifying state of the day.
    private func fireUsageDailyPixels() {
        guard tabsCount > 0 else { return }

        if let tabCountBucket = TabSwitcherOpenDailyPixel.tabCountBucket(forCount: tabsCount) {
            DailyPixel.fire(pixel: .tabBarOpenTabCountDaily, withAdditionalParameters: ["tab_count": tabCountBucket])
        }

        let availableWidth = collectionView.frame.size.width
        let itemWidth = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize.width ?? 0
        if availableWidth > 0, itemWidth > 0, CGFloat(tabsCount) * itemWidth > availableWidth {
            DailyPixel.fire(pixel: .tabBarOverflowDaily)
        }
    }

    /// Equal share of the strip, capped at `maxWidth` then floored at `minWidth` (floor wins).
    static func itemWidth(availableWidth: CGFloat, visibleItems: Int, minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        guard visibleItems > 0 else { return 0 }
        var width = availableWidth / CGFloat(visibleItems)
        width = min(width, maxWidth)
        width = max(width, minWidth)
        return width
    }

    private func reloadData() {
        collectionView.reloadData()
        tabSwitcherButton.tabCount = tabsCount
        tabSwitcherButton.isFireMode = (tabManager?.currentBrowsingMode ?? .normal) == .fire
        tabSwitcherButton.hasUnread = hasUnread
    }

    func backgroundTabAdded() {
        recomputeItemSize()
        reloadData()
        tabSwitcherButton.animateUpdate {
            self.tabSwitcherButton.tabCount = self.tabsCount
        }
    }

    func reloadCell(for tab: Tab) {
        guard let index = tabsModel?.indexOf(tab: tab) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        guard collectionView.indexPathsForVisibleItems.contains(indexPath) else { return }
        collectionView.reloadItems(at: [indexPath])
    }

    private func configureGestures() {
        longPressTabGesture.addTarget(self, action: #selector(handleLongPressTabGesture))
        longPressTabGesture.minimumPressDuration = 0.1
        longPressTabGesture.delegate = self
        collectionView.addGestureRecognizer(longPressTabGesture)
    }

    private var offCenterAdjustment: CGFloat = 0
    @objc func handleLongPressTabGesture(gesture: UILongPressGestureRecognizer) {
        let locationInCollectionView = gesture.location(in: collectionView)
        
        switch gesture.state {
        case .began:
            guard let path = collectionView.indexPathForItem(at: locationInCollectionView) else { return }
            offCenterAdjustment = 0
            delegate?.tabsBar(self, didSelectTabAtIndex: path.row)

        case .changed:
            guard let path = collectionView.indexPathForItem(at: locationInCollectionView) else { return }
            if pressedCell == nil, let cell = collectionView.cellForItem(at: path) as? TabsBarCell {
                offCenterAdjustment = cell.bounds.midX - gesture.location(in: cell).x
                cell.isPressed = true
                pressedCell = cell
                collectionView.beginInteractiveMovementForItem(at: path)
            }

            let location = CGPoint(x: locationInCollectionView.x + offCenterAdjustment, y: collectionView.center.y)
            collectionView.updateInteractiveMovementTargetPosition(location)
            
        case .ended:
            collectionView.endInteractiveMovement()
            releasePressedCell()

        default:
            collectionView.cancelInteractiveMovement()
            releasePressedCell()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let path = collectionView.indexPathForItem(at: touch.location(in: collectionView)),
              let cell = collectionView.cellForItem(at: path) as? TabsBarCell else {
            return true
        }

        // Don't recognize if pressing delete button
        return cell.removeButton.hitTest(touch.location(in: cell.removeButton), with: nil) == nil
    }

    private func releasePressedCell() {
        pressedCell?.isPressed = false
        pressedCell = nil
    }
    
    private func enableInteractionsWithPointer() {
        fireButton.isPointerInteractionEnabled = true
        addTabButton.isPointerInteractionEnabled = true
        tabSwitcherButton.pointer?.frame.size.width = 34
    }
    
    private func requestNewTab(type: NewTabType) {
        switch type {
        case .normal:
            delegate?.tabsBarDidRequestNewNormalTab(self)
        case .fire:
            delegate?.tabsBarDidRequestNewFireTab(self)
        case .currentMode:
            delegate?.tabsBarDidRequestNewTab(self)
        }
        DispatchQueue.main.async {
            if let currentIndex = self.currentIndex {
                self.collectionView.scrollToItem(at: IndexPath(row: currentIndex, section: 0), at: [], animated: true)
            }
        }
    }

    private func configureTabSwitcherLongPressMenu() {
        tabSwitcherButton.showMenuOnLongPress = fireModeCapability?.isFireModeEnabled ?? false
    }

    private func configureAddTabButtonLongPressMenu() {
        guard fireModeCapability?.isFireModeEnabled ?? false else {
            addTabButton.menu = nil
            return
        }

        let menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                Pixel.fire(pixel: .tabLongPressMenuDisplayed, withAdditionalParameters: [
                    PixelParameters.source: "tabs_bar"
                ])
                completion([
                    UIAction(title: UserText.actionNewFireTab,
                             image: DesignSystemImages.Glyphs.Size16.fireWindow) { [weak self] _ in
                                 Pixel.fire(pixel: .tabLongPressMenuNewFireTab, withAdditionalParameters: [
                                     PixelParameters.source: "tabs_bar"
                                 ])
                                 self?.requestNewTab(type: .fire)
                             },
                    UIAction(title: UserText.actionNewTab,
                             image: DesignSystemImages.Glyphs.Size16.add) { [weak self] _ in
                                 Pixel.fire(pixel: .tabLongPressMenuNewNormalTab, withAdditionalParameters: [
                                     PixelParameters.source: "tabs_bar"
                                 ])
                                 self?.requestNewTab(type: .normal)
                             }
                ])
            }
        ])

        addTabButton.menu = menu
        addTabButton.showsMenuAsPrimaryAction = false
    }

    private func configureAIChatChipMenu() {
        let menu = makeAIChatChipMenu()
        aiChatChip.textButton.menu = menu
        aiChatChip.textButton.showsMenuAsPrimaryAction = false
        aiChatChip.iconButton.menu = menu
        aiChatChip.iconButton.showsMenuAsPrimaryAction = false
        aiChatChip.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    private func makeAIChatChipMenu() -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                DailyPixel.fireDailyAndCount(pixel: .aiChatNavigationBarShortcutMenuOpened)
                let duckAIVisible = self?.aiChatSettings?.isAIChatTabBarDuckAIButtonVisible ?? true
                let sheetVisible = self?.aiChatSettings?.isAIChatTabBarContextualSheetButtonVisible ?? true
                completion([
                    UIAction(title: duckAIVisible ? UserText.actionHideAIChatDuckAIButton : UserText.actionShowAIChatDuckAIButton) { [weak self] _ in
                        if duckAIVisible {
                            DailyPixel.fireDailyAndCount(pixel: .aiChatNavigationBarShortcutMenuHideTapped)
                        }
                        self?.aiChatSettings?.setAIChatTabBarDuckAIButtonVisible(!duckAIVisible)
                    },
                    UIAction(title: sheetVisible ? UserText.actionHideAIChatContextualSheetButton : UserText.actionShowAIChatContextualSheetButton) { [weak self] _ in
                        if sheetVisible {
                            DailyPixel.fireDailyAndCount(pixel: .aiChatNavigationBarShortcutMenuHideTapped)
                        }
                        self?.aiChatSettings?.setAIChatTabBarContextualSheetButtonVisible(!sheetVisible)
                    },
                    UIAction(title: UserText.actionOpenAISettings) { [weak self] _ in
                        guard let self else { return }
                        DailyPixel.fireDailyAndCount(pixel: .aiChatNavigationBarShortcutMenuOpenSettingsTapped)
                        self.delegate?.tabsBarDidRequestOpenAISettings(self)
                    }
                ])
            }
        ])
    }

    private func createButton(image: UIImage) -> UIButton {
        let button = BrowserChromeButton()
        button.setImage(image)
        return button
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        NotificationCenter.default.post(name: TabsBarViewController.viewDidLayoutNotification, object: self)
    }
}

extension TabsBarViewController: UIContextMenuInteractionDelegate {

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            self?.makeAIChatChipMenu()
        }
    }

}

extension TabsBarViewController: TabSwitcherButtonDelegate {
    
    func showTabSwitcher(_ button: TabSwitcherButton) {
        delegate?.tabsBarDidRequestTabSwitcher(self)
    }
    
    func launchNewTabWithCurrentMode(_ button: any TabSwitcherButton) {
        requestNewTab(type: .currentMode)
    }
    
    func launchNewNormalTab(_ button: TabSwitcherButton) {
        requestNewTab(type: .normal)
    }

    func launchNewFireTab(_ button: TabSwitcherButton) {
        requestNewTab(type: .fire)
    }
}

extension TabsBarViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        DailyPixel.fireDailyAndCount(pixel: .tabBarTabSelected)
        delegate?.tabsBar(self, didSelectTabAtIndex: indexPath.row)
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }

    func collectionView(_ collectionView: UICollectionView, targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        delegate?.tabsBar(self, didRequestMoveTabFromIndex: sourceIndexPath.row, toIndex: destinationIndexPath.row)
    }
    
}

extension TabsBarViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabsCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TabsBarCell.reuseIdentifier, for: indexPath) as? TabsBarCell else {
            fatalError("Unable to create TabBarCell")
        }
        
        guard let model = tabsModel?.get(tabAt: indexPath.row) else {
            assertionFailure("TabsBarViewController: failed to load tab at \(indexPath.row) of \(tabsCount)")
            DailyPixel.fireDailyAndCount(pixel: .debugTabsBarCellIndexOutOfRange)
            cell.configurePlaceholder(withTheme: ThemeManager.shared.currentTheme)
            return cell
        }
        let isCurrent = indexPath.row == currentIndex
        let isNextCurrent = indexPath.row + 1 == currentIndex
        let isFireModeEnabled = fireModeCapability?.isFireModeEnabled ?? false
        cell.update(model: model, isCurrent: isCurrent, isNextCurrent: isNextCurrent, isFireModeEnabled: isFireModeEnabled, withTheme: ThemeManager.shared.currentTheme)
        cell.onRemove = { [weak self, weak model] in
            guard let self = self, let model = model,
                let tabIndex = self.tabsModel?.indexOf(tab: model)
                else { return }
            let tabState = tabIndex == self.currentIndex ? "active" : "inactive"
            DailyPixel.fireDailyAndCount(pixel: .tabBarTabClosed, withAdditionalParameters: [PixelParameters.tabState: tabState])
            self.delegate?.tabsBar(self, didRemoveTabAtIndex: tabIndex)
        }
        return cell
    }

}

extension TabsBarViewController {

    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        view.backgroundColor = theme.tabsBarBackgroundColor
        view.tintColor = theme.barTintColor
        collectionView.backgroundColor = theme.tabsBarBackgroundColor
        buttonsBackground.backgroundColor = theme.tabsBarBackgroundColor
        
        collectionView.reloadData()
    }

}

extension MainViewController: TabsBarDelegate {
  
    func tabsBar(_ controller: TabsBarViewController, didSelectTabAtIndex index: Int) {
        guard let tab = tabManager.currentTabsModel.get(tabAt: index) else {
            return
        }

        currentTab?.aiChatContextualSheetCoordinator.dismissSheet()
        dismissOmniBar()

        // Tabs bar is iPad only and this is to work around on a problem iOS 26 which will be fixed later with Xcode 26.
        if tab !== self.tabManager.currentTabsModel.currentTab {
            chromeManager.preventNextScrollToTop()
        }
        
        selectTab(tab)
    }
    
    func tabsBar(_ controller: TabsBarViewController, didRemoveTabAtIndex index: Int) {
        if let tab = tabManager.currentTabsModel.get(tabAt: index) {
            closeTab(tab)
        }
    }
    
    func tabsBar(_ controller: TabsBarViewController, didRequestMoveTabFromIndex fromIndex: Int, toIndex: Int) {
        let tabsModel = tabManager.currentTabsModel
        guard let tab = tabsModel.get(tabAt: fromIndex) else {
            return
        }
        tabsModel.move(tab: tab, to: toIndex)
        selectTab(tab)
    }
    
    func tabsBarDidRequestNewTab(_ controller: TabsBarViewController) {
        newTab()
    }
    
    func tabsBarDidRequestForgetAll(_ controller: TabsBarViewController, fireRequest: FireRequest) {
        forgetAllWithAnimation(request: fireRequest)
    }
    
    func tabsBarDidRequestFireEducationDialog(_ controller: TabsBarViewController) {
        currentTab?.dismissContextualDaxFireDialog()
        ViewHighlighter.hideAll()
    }
    
    func tabsBarDidRequestTabSwitcher(_ controller: TabsBarViewController) {
        dismissContextualSheetIfNeeded {
            self.showTabSwitcher()
        }
    }

    func tabsBarDidRequestNewFireTab(_ controller: TabsBarViewController) {
        tabManager.setBrowsingMode(.fire, source: .longPressTabsIcon)
        newTab()
    }

    func tabsBarDidRequestNewNormalTab(_ controller: TabsBarViewController) {
        tabManager.setBrowsingMode(.normal, source: .longPressTabsIcon)
        newTab()
    }

    func tabsBarDidRequestAIChat(_ controller: TabsBarViewController) {
        // Chrome button always opens Duck.ai in a new tab unless current tab is blank — matches macOS.
        if let currentTab, currentTab.tabModel.link != nil {
            currentTab.openNewChatInNewTab()
        } else {
            openAIChat()
        }
    }

    func tabsBarDidRequestToggleAIChatContextualSheet(_ controller: TabsBarViewController) {
        // Materialize the focused tab's view controller if it hasn't been instantiated yet
        // (multi-tab restoration / cache eviction can leave currentTab nil even with a focused tab).
        guard let currentTab = tabManager.current(createIfNeeded: true) else { return }
        // Subscribe to the coordinator now that the VC exists — bind may have skipped earlier
        // when currentTab was still nil (createIfNeeded: false at that time).
        bindAIChatChromeChipToCurrentTab()
        let coordinator = currentTab.aiChatContextualSheetCoordinator
        if coordinator.isSheetPresented {
            coordinator.dismissSheet()
        } else {
            // Route through TabViewController so the cold-restore `contextualChatURL`
            // is honored — presenting the coordinator directly would skip it and open a blank chat.
            currentTab.presentContextualAIChatSheet(from: self)
        }
    }

    func tabsBarDidRequestOpenAISettings(_ controller: TabsBarViewController) {
        segueToSettingsAIChat()
    }

    func tabsBarDidRequestDismissContextualSheet(_ controller: TabsBarViewController, completion: @escaping () -> Void) {
        dismissContextualSheetIfNeeded(completion: completion)
    }

}
