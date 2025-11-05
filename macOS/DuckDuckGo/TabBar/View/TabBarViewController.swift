//
//  TabBarViewController.swift
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

import BrowserServicesKit
import Cocoa
import Combine
import Common
import Lottie
import os.log
import RemoteMessaging
import SwiftUI
import WebKit

final class TabBarViewController: NSViewController, TabBarRemoteMessagePresenting {

    enum HorizontalSpace: CGFloat {
        case pinnedTabsScrollViewPadding = 76
        case pinnedTabsScrollViewPaddingMacOS26 = 84
    }

    private let standardTabHeight: CGFloat
    private let pinnedTabHeight: CGFloat
    private let pinnedTabWidth: CGFloat

    @IBOutlet weak var visualEffectBackgroundView: NSVisualEffectView!
    @IBOutlet weak var backgroundColorView: ColorView!
    @IBOutlet weak var pinnedTabsContainerView: NSView!
    @IBOutlet private weak var collectionView: TabBarCollectionView!
    @IBOutlet private weak var scrollView: TabBarScrollView!
    @IBOutlet weak var pinnedTabsViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var pinnedTabsWindowDraggingView: WindowDraggingView!
    @IBOutlet weak var rightScrollButton: MouseOverButton!
    @IBOutlet weak var leftScrollButton: MouseOverButton!
    @IBOutlet weak var rightShadowImageView: NSImageView!
    @IBOutlet weak var leftShadowImageView: NSImageView!
    @IBOutlet weak var fireButton: MouseOverAnimationButton!
    @IBOutlet weak var draggingSpace: NSView!
    @IBOutlet weak var windowDraggingViewLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var burnerWindowBackgroundView: NSImageView!

    private var pinnedTabsCollectionView: PinnedTabsCollectionView?

    @IBOutlet weak var fireButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var fireButtonHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var addTabButton: MouseOverButton!
    @IBOutlet weak var addTabButtonWidth: NSLayoutConstraint!
    @IBOutlet weak var addTabButtonHeight: NSLayoutConstraint!
    @IBOutlet weak var rightScrollButtonWidth: NSLayoutConstraint!
    @IBOutlet weak var rightScrollButtonHeight: NSLayoutConstraint!
    @IBOutlet weak var leftScrollButtonWidth: NSLayoutConstraint!
    @IBOutlet weak var leftScrollButtonHeight: NSLayoutConstraint!
    @IBOutlet weak var scrollViewHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var pinnedTabsContainerHeightConstraint: NSLayoutConstraint!

    private var pinnedTabsCollectionCancellable: AnyCancellable?
    private var fireButtonMouseOverCancellable: AnyCancellable?

    private var addNewTabButtonFooter: TabBarFooter? {
        guard let indexPath = collectionView.indexPathsForVisibleSupplementaryElements(ofKind: NSCollectionView.elementKindSectionFooter).first,
              let footerView = collectionView.supplementaryView(forElementKind: NSCollectionView.elementKindSectionFooter, at: indexPath) else { return nil }
        return footerView as? TabBarFooter ?? {
            assertionFailure("Unexpected \(footerView), expected TabBarFooter")
            return nil
        }()
    }
    let tabCollectionViewModel: TabCollectionViewModel
    var isInteractionPrevented: Bool = false {
        didSet {
            addNewTabButtonFooter?.isEnabled = !isInteractionPrevented
        }
    }

    private let bookmarkManager: BookmarkManager
    private let fireproofDomains: FireproofDomains
    private let featureFlagger: FeatureFlagger
    private var pinnedTabsViewModel: PinnedTabsViewModel?
    private var pinnedTabsView: PinnedTabsView?
    private var pinnedTabsHostingView: PinnedTabsHostingView?
    private let pinnedTabsManagerProvider: PinnedTabsManagerProviding = Application.appDelegate.pinnedTabsManagerProvider
    private var pinnedTabsDiscoveryPopover: NSPopover?
    private weak var crashPopoverViewController: PopoverMessageViewController?

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    var tabPreviewsEnabled: Bool = true

    /// Are tab previews enabled, is window key, is mouse over a tab
    private var shouldDisplayTabPreviews: Bool {
        guard tabPreviewsEnabled,
              let mouseLocation = mouseLocationInKeyWindow() else { return false }

        let isMouseOverTab = pinnedTabsContainerView.isMouseLocationInsideBounds(mouseLocation)
        || collectionView.withMouseLocationInViewCoordinates(mouseLocation, convert: collectionView.indexPathForItem(at:)) != nil

        return isMouseOverTab
    }

    /// Returns mouse location in window if window is key
    private func mouseLocationInKeyWindow() -> NSPoint? {
        guard let window = view.window, window.isKeyWindow else { return nil }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        return mouseLocation
    }

    /// If mouse is inside view and window is key
    private var isMouseLocationInsideBounds: Bool {
        guard let mouseLocation = mouseLocationInKeyWindow() else { return false }
        let isMouseLocationInsideBounds = view.isMouseLocationInsideBounds(mouseLocation)
        return isMouseLocationInsideBounds
    }

    private var selectionIndexCancellable: AnyCancellable?
    private var mouseDownCancellable: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var previousScrollViewWidth: CGFloat = .zero

    // TabBarRemoteMessagePresentable
    var tabBarRemoteMessageViewModel: TabBarRemoteMessageViewModel
    var tabBarRemoteMessagePopover: NSPopover?
    var tabBarRemoteMessagePopoverHoverTimer: Timer?
    var feedbackBarButtonHostingController: NSHostingController<TabBarRemoteMessageView>?
    var tabBarRemoteMessageCancellable: AnyCancellable?

    @IBOutlet weak var shadowView: TabShadowView!

    @IBOutlet weak var leftSideStackLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var rightSideStackView: NSStackView!

    var footerCurrentWidthDimension: CGFloat {
        if tabMode == .overflow {
            return 0.0
        }

        return theme.tabBarButtonSize + theme.addressBarStyleProvider.addTabButtonPadding
    }

    // MARK: - View Lifecycle

    static func create(
        tabCollectionViewModel: TabCollectionViewModel,
        bookmarkManager: BookmarkManager,
        fireproofDomains: FireproofDomains,
        activeRemoteMessageModel: ActiveRemoteMessageModel,
        featureFlagger: FeatureFlagger
    ) -> TabBarViewController {
        NSStoryboard(name: "TabBar", bundle: nil).instantiateInitialController { coder in
            self.init(
                coder: coder,
                tabCollectionViewModel: tabCollectionViewModel,
                bookmarkManager: bookmarkManager,
                fireproofDomains: fireproofDomains,
                activeRemoteMessageModel: activeRemoteMessageModel,
                featureFlagger: featureFlagger
            )
        }!
    }

    required init?(coder: NSCoder) {
        fatalError("TabBarViewController: Bad initializer")
    }

    init?(coder: NSCoder,
          tabCollectionViewModel: TabCollectionViewModel,
          bookmarkManager: BookmarkManager,
          fireproofDomains: FireproofDomains,
          activeRemoteMessageModel: ActiveRemoteMessageModel,
          featureFlagger: FeatureFlagger,
          themeManager: ThemeManager = NSApp.delegateTyped.themeManager) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.fireproofDomains = fireproofDomains
        self.featureFlagger = featureFlagger
        let tabBarActiveRemoteMessageModel = TabBarActiveRemoteMessage(activeRemoteMessageModel: activeRemoteMessageModel)
        self.tabBarRemoteMessageViewModel = TabBarRemoteMessageViewModel(activeRemoteMessageModel: tabBarActiveRemoteMessageModel,
                                                                         isFireWindow: tabCollectionViewModel.isBurner)
        self.themeManager = themeManager

        standardTabHeight = themeManager.theme.tabStyleProvider.standardTabHeight
        pinnedTabHeight = themeManager.theme.tabStyleProvider.pinnedTabHeight
        pinnedTabWidth = themeManager.theme.tabStyleProvider.pinnedTabWidth

        super.init(coder: coder)

        initializePinnedTabs(themeManager: themeManager)
    }

    private func initializePinnedTabs(themeManager: ThemeManager) {
        guard !tabCollectionViewModel.isBurner, let pinnedTabCollection = tabCollectionViewModel.pinnedTabsManager?.tabCollection else {
            return
        }

        guard featureFlagger.isFeatureOn(.pinnedTabsViewRewrite) else {
            initializePinnedTabsLegacyView(pinnedTabCollection: pinnedTabCollection, themeManager: themeManager)
            return
        }

        initializePinnedTabsAppKitView()
    }

    private func initializePinnedTabsLegacyView(pinnedTabCollection: TabCollection, themeManager: ThemeManager) {
        let pinnedTabsViewModel = PinnedTabsViewModel(collection: pinnedTabCollection, fireproofDomains: fireproofDomains, bookmarkManager: bookmarkManager)
        let pinnedTabsView = PinnedTabsView(model: pinnedTabsViewModel, themeManager: themeManager)
        let pinnedTabsHostingView = PinnedTabsHostingView(rootView: pinnedTabsView)

        self.pinnedTabsViewModel = pinnedTabsViewModel
        self.pinnedTabsView = pinnedTabsView
        self.pinnedTabsHostingView = pinnedTabsHostingView
    }

    private func initializePinnedTabsAppKitView() {
        pinnedTabsCollectionView = PinnedTabsCollectionView(frame: .zero)
        pinnedTabsCollectionView?.isSelectable = true
        pinnedTabsCollectionView?.backgroundColors = [.clear]

        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 120, height: 32)
        layout.sectionInset = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        pinnedTabsCollectionView?.collectionViewLayout = layout

        pinnedTabsCollectionView?.register(TabBarViewItem.self, forItemWithIdentifier: TabBarViewItem.identifier)
        pinnedTabsCollectionView?.register(NSView.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionFooter, withIdentifier: TabBarFooter.identifier)

        // Register for the dropped object types we can accept.
        pinnedTabsCollectionView?.registerForDraggedTypes([.URL, .fileURL, TabBarViewItemPasteboardWriter.utiInternalType, .string])
        // Enable dragging items within and into our CollectionView.
        pinnedTabsCollectionView?.setDraggingSourceOperationMask([.private], forLocal: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        shadowView.isHidden = theme.tabStyleProvider.shouldShowSShapedTab
        scrollView.updateScrollElasticity(with: tabMode)
        observeToScrollNotifications()
        subscribeToSelectionIndex()
        setupFireButton()
        setupPinnedTabsView()
        subscribeToTabModeChanges()
        setupAddTabButton()
        setupAsBurnerWindowIfNeeded()
        subscribeToPinnedTabsSettingChanged()
        setupScrollButtons()
        setupTabsContainersHeight()
        subscribeToThemeChanges()

        applyThemeStyle()
    }

    override func viewWillAppear() {
        updateEmptyTabArea()
        tabCollectionViewModel.delegate = self
        reloadSelection()

        // Detect if tabs are clicked when the window is not in focus
        // https://app.asana.com/0/1177771139624306/1202033879471339
        addMouseMonitors()
        addTabBarRemoteMessageListener()
    }

    override func viewDidAppear() {
        // Running tests or moving Tab Bar from Title to main view on burn (animateBurningIfNeededAndClose)?
        guard view.window != nil else { return }

        enableScrollButtons()
        subscribeToChildWindows()
        setupAccessibility()
    }

    override func viewWillDisappear() {
        mouseDownCancellable = nil
        tabBarRemoteMessageCancellable = nil
    }

    deinit {
#if DEBUG
        _tabPreviewWindowController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        tabBarRemoteMessagePopoverHoverTimer?.ensureObjectDeallocated(after: 1.0, do: .interrupt)

        feedbackBarButtonHostingController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        pinnedTabsDiscoveryPopover?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        tabBarRemoteMessagePopover?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        addTabButton?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
        collectionView?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    override func viewDidLayout() {
        frozenLayout = isMouseLocationInsideBounds
        updateTabMode()
        updateEmptyTabArea()
        pinnedTabsCollectionView?.invalidateLayout()
        collectionView.invalidateLayout()
    }

    // MARK: - Setup

    private func subscribeToSelectionIndex() {
        selectionIndexCancellable = tabCollectionViewModel.$selectionIndex.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reloadSelection()
            self?.adjustStandardTabPosition()
        }
    }

    private func subscribeToPinnedTabsSettingChanged() {
        pinnedTabsManagerProvider.settingChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }

                if tabCollectionViewModel.allTabsCount == 0 {
                    view.window?.close()
                    return
                }

                if featureFlagger.isFeatureOn(.pinnedTabsViewRewrite) {
                    subscribeToPinnedTabsCollection()
                }

                updatePinnedTabsViewModel()
            }.store(in: &cancellables)
    }

    private func updatePinnedTabsViewModel() {
        guard let pinnedTabCollection = tabCollectionViewModel.pinnedTabsCollection else { return }

        // Replace collection
        pinnedTabsViewModel?.replaceCollection(with: pinnedTabCollection)

        // Refresh tab selection
        if let selectionIndex = tabCollectionViewModel.selectionIndex {
            tabCollectionViewModel.select(at: selectionIndex)
        }
        if tabCollectionViewModel.selectionIndex == nil {
            if tabCollectionViewModel.tabs.count > 0 {
                tabCollectionViewModel.select(at: .unpinned(0))
            } else {
                tabCollectionViewModel.select(at: .pinned(0))
            }
        }
    }

    private func setupFireButton() {
        let style = theme.iconsProvider.fireButtonStyleProvider
        fireButton.image = style.icon
        fireButton.toolTip = UserText.clearBrowsingHistoryTooltip

        fireButton.setAccessibilityElement(true)
        fireButton.setAccessibilityRole(.button)
        fireButton.setAccessibilityIdentifier("TabBarViewController.fireButton")
        fireButton.setAccessibilityTitle(UserText.clearBrowsingHistoryTooltip)

        fireButton.setCornerRadius(theme.toolbarButtonsCornerRadius)
        fireButton.animationNames = MouseOverAnimationButton.AnimationNames(aqua: style.lightAnimation,
                                                                            dark: style.darkAnimation)
        fireButton.sendAction(on: .leftMouseDown)
        fireButtonMouseOverCancellable = fireButton.publisher(for: \.isMouseOver)
            .first(where: { $0 }) // only interested when mouse is over
            .sink(receiveValue: { [weak self] _ in
                self?.stopFireButtonPulseAnimation()
            })

        fireButtonWidthConstraint.constant = theme.tabBarButtonSize
        fireButtonHeightConstraint.constant = theme.tabBarButtonSize
    }

    private func setupScrollButtons() {
        leftScrollButton.setCornerRadius(theme.addressBarStyleProvider.addressBarButtonsCornerRadius)
        leftScrollButtonWidth.constant = theme.tabBarButtonSize
        leftScrollButtonHeight.constant = theme.tabBarButtonSize

        rightScrollButton.setCornerRadius(theme.addressBarStyleProvider.addressBarButtonsCornerRadius)

        rightScrollButtonWidth.constant = theme.tabBarButtonSize
        rightScrollButtonHeight.constant = theme.tabBarButtonSize
    }

    private func setupTabsContainersHeight() {
        scrollViewHeightConstraint.constant = theme.tabStyleProvider.tabsScrollViewHeight
        pinnedTabsContainerHeightConstraint.constant = theme.tabStyleProvider.pinnedTabsContainerViewHeight
    }

    private func setupAsBurnerWindowIfNeeded() {
        if tabCollectionViewModel.isBurner {
            burnerWindowBackgroundView.image = theme.fireWindowGraphic
            burnerWindowBackgroundView.isHidden = false
            fireButton.isAnimationEnabled = false
            fireButton.backgroundColor = NSColor.fireButtonRedBackground
            fireButton.mouseOverColor = NSColor.fireButtonRedHover
            fireButton.mouseDownColor = NSColor.fireButtonRedPressed
            fireButton.normalTintColor = NSColor.white
            fireButton.mouseDownTintColor = NSColor.white
            fireButton.mouseOverTintColor = NSColor.white
        }
    }

    private func setupAccessibility() {
        // Set up Accessibility structure:
        // AXWindow (MainWindow)
        // ↪ AXGroup “Tab Bar” (TabBarView)
        //   ↪ AXScrollView (TabBarViewController.CollectionView.ScrollView)
        //     ↪ AXTabGroup (TabBarViewController.CollectionView)
        //       ↪ AXRadioButton (TabBarViewItem)
        //         ↪ AXImage (TabBarViewItem.favicon)
        //         ↪ AXStaticText (TabBarViewItem.title)
        //         ↪ AXButton (TabBarViewItem.closeButton)
        //         ↪ AXButton (TabBarViewItem.permissionButton)
        //         ↪ AXButton (TabBarViewItem.muteButton)
        //         ↪ AXButton (TabBarViewItem.crashButton)
        //      ↪ …
        //      ↪ AXButton “Open a new tab” (NewTabButton)
        //     ↪ AXTabGroup “Pinned Tabs” (PinnedTabsView)
        //      ↪ AXButton …

        scrollView.setAccessibilityIdentifier("TabBarViewController.CollectionView.ScrollView")

        collectionView.setAccessibilityIdentifier("TabBarViewController.CollectionView")
        collectionView.setAccessibilityRole(.tabGroup) // set role to AXTabGroup
        collectionView.setAccessibilitySubrole(nil)
        collectionView.setAccessibilityTitle("Tabs")

        pinnedTabsCollectionView?.setAccessibilityIdentifier("PinnedTabsView")
        pinnedTabsCollectionView?.setAccessibilityRole(.tabGroup)
        pinnedTabsCollectionView?.setAccessibilityTitle("Pinned Tabs")

        addTabButton.cell?.setAccessibilityParent(collectionView)

        leftScrollButton.setAccessibilityIdentifier("TabBarViewController.leftScrollButton")
        leftScrollButton.setAccessibilityTitle("Scroll left")

        rightScrollButton.setAccessibilityIdentifier("TabBarViewController.rightScrollButton")
        rightScrollButton.setAccessibilityTitle("Scroll right")
    }

    // MARK: - Pinned Tabs

    private func setupPinnedTabsView() {
        if featureFlagger.isFeatureOn(.pinnedTabsViewRewrite) {
            layoutPinnedTabsCollectionView()
            subscribeToPinnedTabsCollection()

            pinnedTabsWindowDraggingView.isHidden = true

            pinnedTabsCollectionView?.dataSource = self
            pinnedTabsCollectionView?.delegate = self

        } else {
            layoutPinnedTabsView()
            subscribeToPinnedTabsHostingView()
            subscribeToPinnedTabsViewModelOutputs()
            subscribeToPinnedTabsViewModelInputs()
        }
    }

    private func layoutPinnedTabsView() {
        guard let pinnedTabsHostingView = pinnedTabsHostingView else { return }

        pinnedTabsHostingView.translatesAutoresizingMaskIntoConstraints = false
        pinnedTabsContainerView.addSubview(pinnedTabsHostingView)

        let trailingConstant: CGFloat = theme.tabStyleProvider.shouldShowSShapedTab ? 12 : 0

        NSLayoutConstraint.activate([
            pinnedTabsHostingView.leadingAnchor.constraint(equalTo: pinnedTabsContainerView.leadingAnchor),
            pinnedTabsHostingView.topAnchor.constraint(lessThanOrEqualTo: pinnedTabsContainerView.topAnchor),
            pinnedTabsHostingView.bottomAnchor.constraint(equalTo: pinnedTabsContainerView.bottomAnchor),
            pinnedTabsHostingView.trailingAnchor.constraint(equalTo: pinnedTabsContainerView.trailingAnchor, constant: trailingConstant)
        ])
    }

    private func layoutPinnedTabsCollectionView() {
        guard let pinnedTabsCollectionView else { return }

        pinnedTabsCollectionView.translatesAutoresizingMaskIntoConstraints = false
        pinnedTabsContainerView.addSubview(pinnedTabsCollectionView)

        NSLayoutConstraint.activate([
            pinnedTabsCollectionView.leadingAnchor.constraint(equalTo: pinnedTabsContainerView.leadingAnchor),
            pinnedTabsCollectionView.topAnchor.constraint(lessThanOrEqualTo: pinnedTabsContainerView.topAnchor),
            pinnedTabsCollectionView.bottomAnchor.constraint(equalTo: pinnedTabsContainerView.bottomAnchor),
            pinnedTabsCollectionView.trailingAnchor.constraint(equalTo: pinnedTabsContainerView.trailingAnchor)
        ])
    }

    private func subscribeToPinnedTabsCollection() {
        pinnedTabsCollectionCancellable = tabCollectionViewModel.pinnedTabsCollection?.$tabs
            .removeDuplicates()
            .asVoid()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.pinnedTabsCollectionView?.reloadData()
            }
    }

    private func subscribeToPinnedTabsViewModelInputs() {
        guard let pinnedTabsViewModel = pinnedTabsViewModel else { return }

        tabCollectionViewModel.$selectionIndex
            .map { [weak self] selectedTabIndex -> Tab? in
                switch selectedTabIndex {
                case .pinned(let index):
                    return self?.pinnedTabsViewModel?.items[safe: index]
                default:
                    return nil
                }
            }
            .assign(to: \.selectedItem, onWeaklyHeld: pinnedTabsViewModel)
            .store(in: &cancellables)

        Publishers.CombineLatest(tabCollectionViewModel.$selectionIndex, $tabMode)
            .map { selectedTabIndex, tabMode -> Bool in
                if case .unpinned(0) = selectedTabIndex, tabMode == .divided {
                    return false
                }
                return true
            }
            .assign(to: \.shouldDrawLastItemSeparator, onWeaklyHeld: pinnedTabsViewModel)
            .store(in: &cancellables)
    }

    private func subscribeToPinnedTabsViewModelOutputs() {
        guard let pinnedTabsViewModel = pinnedTabsViewModel else { return }

        pinnedTabsViewModel.tabsDidReorderPublisher
            .sink { [weak self] tabs in
                self?.tabCollectionViewModel.pinnedTabsManager?.tabCollection.reorderTabs(tabs)
            }
            .store(in: &cancellables)

        pinnedTabsViewModel.$selectedItemIndex.dropFirst().removeDuplicates()
            .compactMap { $0 }
            .sink { [weak self] index in
                self?.deselectTabAndSelectPinnedTab(at: index)
            }
            .store(in: &cancellables)

        pinnedTabsViewModel.$hoveredItemIndex.dropFirst().removeDuplicates()
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] index in
                self?.pinnedTabsViewDidUpdateHoveredItem(to: index)
            }
            .store(in: &cancellables)

        pinnedTabsViewModel.contextMenuActionPublisher
            .sink { [weak self] action in
                self?.handlePinnedTabContextMenuAction(action)
            }
            .store(in: &cancellables)

        pinnedTabsViewModel.$dragMovesWindow.map(!)
            .assign(to: \.pinnedTabsWindowDraggingView.isHidden, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    private func subscribeToPinnedTabsHostingView() {
        pinnedTabsHostingView?.middleClickPublisher
            .compactMap { [weak self] in self?.pinnedTabsView?.index(forItemAt: $0) }
            .sink { [weak self] index in
                self?.tabCollectionViewModel.remove(at: .pinned(index))
            }
            .store(in: &cancellables)

        pinnedTabsWindowDraggingView.mouseDownPublisher
            .sink { [weak self] _ in
                self?.pinnedTabsViewModel?.selectedItem = self?.pinnedTabsViewModel?.items.first
            }
            .store(in: &cancellables)
    }

    private func pinnedTabsViewDidUpdateHoveredItem(to index: Int?) {
        if let index {
            showPinnedTabPreview(at: index)
        } else if !shouldDisplayTabPreviews {
            hideTabPreview(allowQuickRedisplay: true)
        }
    }

    private func deselectTabAndSelectPinnedTab(at index: Int) {
        hideTabPreview()
        if tabCollectionViewModel.selectionIndex != .pinned(index), tabCollectionViewModel.select(at: .pinned(index)) {
            let previousSelection = collectionView.selectionIndexPaths
            clearSelection(animated: true)
            collectionView.reloadItems(at: previousSelection)
        }
    }

    // MARK: - Actions

    @objc func addButtonAction(_ sender: NSButton) {
        tabCollectionViewModel.insertOrAppendNewTab()
    }

    @IBAction func rightScrollButtonAction(_ sender: NSButton) {
        collectionView.scrollToEnd()
    }

    @IBAction func leftScrollButtonAction(_ sender: NSButton) {
        collectionView.scrollToBeginning()
    }

    private func handlePinnedTabContextMenuAction(_ action: PinnedTabsViewModel.ContextMenuAction) {
        switch action {
        case let .unpin(index):
            tabCollectionViewModel.unpinTab(at: index)
        case let .duplicate(index):
            duplicateTab(at: .pinned(index))
        case let .bookmark(tab):
            guard let tabViewModel = tabCollectionViewModel.pinnedTabsManager?.tabViewModels[tab] else {
                Logger.general.debug("TabBarViewController: Failed to get tabViewModel for pinned tab")
                return
            }
            addBookmark(for: tabViewModel)
        case let .removeBookmark(tab):
            guard let url = tab.url else {
                Logger.general.debug("TabBarViewController: Failed to get url from tab")
                return
            }
            deleteBookmark(with: url)
        case let .fireproof(tab):
            fireproof(tab)
        case let .removeFireproofing(tab):
            removeFireproofing(from: tab)
        case let .close(index):
            tabCollectionViewModel.remove(at: .pinned(index))
        case let .muteOrUnmute(tab):
            tab.muteUnmuteTab()
        }
    }

    private func reloadSelection() {
        let isPinnedTab = tabCollectionViewModel.selectionIndex?.isPinnedTab == true

        let collectionView: TabBarCollectionView?
        let shouldContinue: Bool
        if featureFlagger.isFeatureOn(.pinnedTabsViewRewrite) {
            shouldContinue = true
            collectionView = isPinnedTab ? pinnedTabsCollectionView : self.collectionView
        } else {
            shouldContinue = !isPinnedTab
            collectionView = self.collectionView
        }

        bringSelectedTabCollectionToFront()

        guard shouldContinue, let collectionView else {
            return
        }

        defer {
            refreshPinnedTabsLastSeparator()
        }

        guard collectionView.selectionIndexPaths.first?.item != tabCollectionViewModel.selectionIndex?.item else {
            collectionView.updateItemsLeftToSelectedItems()
            return
        }

        guard let selectionIndex = tabCollectionViewModel.selectionIndex else {
            Logger.general.error("TabBarViewController: Selection index is nil")
            return
        }

        clearSelection()

        let newSelectionIndexPath = IndexPath(item: selectionIndex.item)
        if tabMode == .divided {
            collectionView.animator().selectItems(at: [newSelectionIndexPath], scrollPosition: .centeredHorizontally)
        } else {
            collectionView.selectItems(at: [newSelectionIndexPath], scrollPosition: .centeredHorizontally)
            collectionView.scrollToSelected()
        }
    }

    private func refreshPinnedTabsLastSeparator() {
        guard featureFlagger.isFeatureOn(.pinnedTabsViewRewrite), let pinnedTabsCollectionView else {
            return
        }

        pinnedTabsCollectionView.setLastItemSeparatorHidden(shouldHideLastPinnedSeparator)
    }

    private var shouldHideLastPinnedSeparator: Bool {
        let isTabModeDivided = tabMode == .divided
        let isFirstUnpinnedTabSelected = tabCollectionViewModel.selectionIndex == .unpinned(.zero)

        return isTabModeDivided && isFirstUnpinnedTabSelected
    }

    private func bringSelectedTabCollectionToFront() {
        if tabCollectionViewModel.selectionIndex?.isPinnedTab == true {
            view.addSubview(pinnedTabsContainerView, positioned: .above, relativeTo: scrollView)
        } else {
            view.addSubview(scrollView, positioned: .above, relativeTo: pinnedTabsContainerView)
        }
    }

    private func clearSelection(animated: Bool = false) {
        collectionView.clearSelection(animated: animated)
        pinnedTabsCollectionView?.clearSelection(animated: animated)
    }

    private func selectTab(with event: NSEvent) {
        let locationInWindow = event.locationInWindow

        if let point = pinnedTabsHostingView?.mouseLocationInsideBounds(locationInWindow),
           let index = pinnedTabsView?.index(forItemAt: point) {

            tabCollectionViewModel.select(at: .pinned(index))

        } else if let point = collectionView.mouseLocationInsideBounds(locationInWindow),
                  let indexPath = collectionView.indexPathForItem(at: point) {
            tabCollectionViewModel.select(at: .unpinned(indexPath.item))
        }
    }

    // MARK: - Window Dragging, Floating Add Button

    private var totalTabWidth: CGFloat {
        let selectedWidth = currentTabWidth(selected: true)
        let restOfTabsWidth = CGFloat(max(collectionView.numberOfItems(inSection: 0) - 1, 0)) * currentTabWidth()
        return selectedWidth + restOfTabsWidth
    }

    private func updateEmptyTabArea() {
        let totalTabWidth = self.totalTabWidth
        let plusButtonWidth: CGFloat = 44

        // Window dragging
        let leadingSpace = min(totalTabWidth + plusButtonWidth, scrollView.frame.size.width)
        windowDraggingViewLeadingConstraint.constant = leadingSpace
    }

    // MARK: - Drag and Drop

    private func moveItemIfNeeded(to newIndex: TabIndex) {
        let tabCollection = newIndex.isPinnedTab ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection
        guard let tabCollection,
              TabDragAndDropManager.shared.sourceUnit?.tabCollectionViewModel === tabCollectionViewModel,
              tabCollection.tabs.indices.contains(newIndex.item),
              let oldIndex = TabDragAndDropManager.shared.sourceUnit?.index,
              oldIndex != newIndex else { return }

        tabCollectionViewModel.moveTab(at: oldIndex, to: newIndex)
        TabDragAndDropManager.shared.setSource(tabCollectionViewModel: tabCollectionViewModel, index: newIndex)
    }

    private func moveToNewWindow(from index: Int, droppingPoint: NSPoint? = nil, burner: Bool) {
        // only allow dragging Tab out when there‘s tabs (or pinned tabs) left
        guard tabCollectionViewModel.tabCollection.tabs.count > 1 || pinnedTabsViewModel?.items.isEmpty == false else { return }
        guard let tabViewModel = tabCollectionViewModel.tabViewModel(at: index) else {
            assertionFailure("TabBarViewController: Failed to get tab view model")
            return
        }

        let tab = tabViewModel.tab
        tabCollectionViewModel.remove(at: .unpinned(index), published: false)
        WindowsManager.openNewWindow(with: tab, droppingPoint: droppingPoint)
    }

    // MARK: - Mouse Monitor

    private func addMouseMonitors() {
        mouseDownCancellable = NSEvent.addLocalCancellableMonitor(forEventsMatching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            return self.mouseDown(with: event)
        }
    }

    func mouseDown(with event: NSEvent) -> NSEvent? {
        if event.window === view.window,
           view.window?.isMainWindow == false {

            selectTab(with: event)
        }

        return event
    }

    // MARK: - Tab Width

    enum TabMode: Equatable {
        case divided
        case overflow
    }

    private var frozenLayout = false
    @Published private var tabMode = TabMode.divided

    private func updateTabMode(for numberOfItems: Int? = nil, updateLayout: Bool? = nil) {
        let items = CGFloat(numberOfItems ?? self.layoutNumberOfItems())
        let footerWidth = footerCurrentWidthDimension
        let tabsWidth = scrollView.bounds.width

        var requiredWidth: CGFloat

        if theme.tabStyleProvider.shouldShowSShapedTab {
            requiredWidth = max(0, (items - 1)) * TabBarViewItem.Width.minimum + TabBarViewItem.Width.minimumSelected + footerWidth
        } else {
            requiredWidth = max(0, (items - 1)) * TabBarViewItem.Width.minimum + TabBarViewItem.Width.minimumSelected
        }

        let newMode: TabMode
        if requiredWidth < tabsWidth {
            newMode = .divided
        } else {
            newMode = .overflow
        }

        guard self.tabMode != newMode else { return }
        self.tabMode = newMode
        if updateLayout ?? !self.frozenLayout {
            self.updateLayout()
        }
    }

    private func updateLayout() {
        scrollView.updateScrollElasticity(with: tabMode)
        displayScrollButtons()
        updateEmptyTabArea()
        collectionView.invalidateLayout()
        frozenLayout = false
    }

    private var cachedLayoutNumberOfItems: Int?
    private func layoutNumberOfItems(removedIndex: Int? = nil) -> Int {
        let actualNumber = collectionView.numberOfItems(inSection: 0)

        guard let numberOfItems = self.cachedLayoutNumberOfItems,
              // skip updating number of items when closing not last Tab
              actualNumber > 0 && numberOfItems > actualNumber,
              tabMode == .divided,
              isMouseLocationInsideBounds
        else {
            self.cachedLayoutNumberOfItems = actualNumber
            return actualNumber
        }

        return numberOfItems
    }

    private func currentTabWidth(selected: Bool = false, removedIndex: Int? = nil) -> CGFloat {
        let numberOfItems = CGFloat(self.layoutNumberOfItems(removedIndex: removedIndex))
        guard numberOfItems > 0 else {
            return 0
        }

        let tabsWidth = scrollView.bounds.width - footerCurrentWidthDimension
        let minimumWidth = selected ? TabBarViewItem.Width.minimumSelected : TabBarViewItem.Width.minimum

        if tabMode == .divided {
            var dividedWidth = tabsWidth / numberOfItems
            // If tabs are shorter than minimumSelected, then the selected tab takes more space
            if dividedWidth < TabBarViewItem.Width.minimumSelected {
                dividedWidth = (tabsWidth - TabBarViewItem.Width.minimumSelected) / (numberOfItems - 1)
            }
            return floor(min(TabBarViewItem.Width.maximum, max(minimumWidth, dividedWidth)))
        } else {
            return minimumWidth
        }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)

        guard shouldDisplayTabPreviews else {
            if tabPreviewWindowController.isPresented {
                hideTabPreview(allowQuickRedisplay: true)
            }
            return
        }

        // show Tab Preview when mouse was moved over a tab when the Tab Preview was hidden before
        guard !tabPreviewWindowController.isPresented else { return }

        if let indexPath = collectionView.withMouseLocationInViewCoordinates(convert: { self.collectionView.indexPathForItem(at: $0) }),
           let tabBarViewItem = collectionView.item(at: indexPath) as? TabBarViewItem {
            showTabPreview(for: tabBarViewItem)
        } else if let pinnedTabIndex = pinnedTabsViewModel?.hoveredItemIndex {
            showPinnedTabPreview(at: pinnedTabIndex)
        }
    }

    override func mouseExited(with event: NSEvent) {
        // did mouse really exit or is it an event generated by a subview and called via the responder chain?
        guard !isMouseLocationInsideBounds else { return }

        self.hideTabPreview(allowQuickRedisplay: true)

        // unfreeze "frozen layout" on mouse exit
        // we‘re keeping tab width unchanged when closing the tabs when the cursor is inside the tab bar
        guard cachedLayoutNumberOfItems != collectionView.numberOfItems(inSection: 0) || frozenLayout else { return }

        cachedLayoutNumberOfItems = nil
        let shouldScroll = collectionView.isAtEndScrollPosition
        collectionView.animator().performBatchUpdates {
            if shouldScroll {
                collectionView.animator().scroll(CGPoint(x: scrollView.contentView.bounds.origin.x, y: 0))
            }
        } completionHandler: { [weak self] _ in
            guard let self else { return }
            self.updateLayout()
            self.enableScrollButtons()
        }
    }

    // MARK: - Scroll Buttons

    private func observeToScrollNotifications() {
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewContentRectDidChange(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewContentRectDidChange(_:)), name: NSView.frameDidChangeNotification, object: collectionView)
        previousScrollViewWidth = scrollView.bounds.size.width
        NotificationCenter.default.addObserver(self, selector: #selector(scrollViewFrameDidChange(_:)), name: NSView.frameDidChangeNotification, object: scrollView)
    }

    @objc private func scrollViewContentRectDidChange(_ notification: Notification) {
        enableScrollButtons()
        hideTabPreview(allowQuickRedisplay: true)
    }

    @objc private func scrollViewFrameDidChange(_ notification: Notification) {
        adjustScrollPositionOnResize()
        enableScrollButtons()
        hideTabPreview(allowQuickRedisplay: true)
    }

    private func enableScrollButtons() {
        rightScrollButton.isEnabled = !collectionView.isAtEndScrollPosition
        leftScrollButton.isEnabled = !collectionView.isAtStartScrollPosition
    }

    private func displayScrollButtons() {
        let scrollViewsAreHidden = tabMode == .divided
        rightScrollButton.isHidden = scrollViewsAreHidden
        leftScrollButton.isHidden = scrollViewsAreHidden
        rightShadowImageView.isHidden = scrollViewsAreHidden
        leftShadowImageView.isHidden = scrollViewsAreHidden
        addTabButton.isHidden = scrollViewsAreHidden

        adjustStandardTabPosition()
    }

    private func adjustStandardTabPosition() {
        /// When we need to show the s-shaped tabs, given that the pinned tabs view is moved 12 points to the left
        /// we need to do the same with the left side scroll view (when on overflow), if not the pinned tabs container
        /// will overlap the arrow button.
        let shouldShowSShapedTabs = theme.tabStyleProvider.shouldShowSShapedTab
        let noPinnedTabs = pinnedTabsViewModel?.items.isEmpty ?? true
        let isLeftScrollButtonVisible = !leftScrollButton.isHidden

        if !noPinnedTabs && shouldShowSShapedTabs && isLeftScrollButtonVisible {
            leftSideStackLeadingConstraint.constant = 12
        } else if noPinnedTabs && shouldShowSShapedTabs && !isLeftScrollButtonVisible {
            leftSideStackLeadingConstraint.constant = -12
        } else {
            leftSideStackLeadingConstraint.constant = 0
        }
    }

    /// Adjust the right edge scroll position to keep Selected Tab visible when resizing (or bring it into view expanding the right edge when it‘s behind the edge)
    private func adjustScrollPositionOnResize() {
        let newWidth = scrollView.bounds.size.width
        let resizeAmount = newWidth - previousScrollViewWidth
        previousScrollViewWidth = newWidth

        guard resizeAmount != 0,
              let selectedIndexPath = collectionView.selectionIndexPaths.first,
              collectionView.isIndexPathValid(selectedIndexPath),
              let layoutAttributes = collectionView.layoutAttributesForItem(at: selectedIndexPath) else { return }

        let visibleRect = collectionView.visibleRect
        let selectedItemFrame = layoutAttributes.frame

        let isExpanding = resizeAmount > 0

        let selectedItemLeft = selectedItemFrame.minX
        let selectedItemRight = selectedItemFrame.maxX
        let visibleLeft = visibleRect.minX
        let visibleRight = visibleRect.maxX
        let currentOriginX = scrollView.documentVisibleRect.origin.x

        // CONTRACTING: if selected item is beyond the right edge, preserve right edge
        if !isExpanding && selectedItemRight > visibleRight {
            let newOriginX = currentOriginX + abs(resizeAmount)
            collectionView.scroll(NSPoint(x: newOriginX, y: 0))

        // EXPANDING: if selected item is beyond the left edge, preserve right edge
        } else if isExpanding && selectedItemLeft < visibleLeft {
            let newOriginX = max(0, currentOriginX - abs(resizeAmount))
            collectionView.scroll(NSPoint(x: newOriginX, y: 0))
        }
    }

    private func setupAddTabButton() {
        addTabButton.delegate = self
        addTabButton.registerForDraggedTypes([.string])
        addTabButton.target = self
        addTabButton.action = #selector(addButtonAction(_:))
        addTabButton.setCornerRadius(theme.addressBarStyleProvider.addressBarButtonsCornerRadius)
        addTabButtonWidth.constant = theme.tabBarButtonSize
        addTabButtonHeight.constant = theme.tabBarButtonSize
        addTabButton.toolTip = UserText.newTabTooltip
        addTabButton.setAccessibilityIdentifier("NewTabButton")
        addTabButton.setAccessibilityTitle(UserText.newTabTooltip)
    }

    private func subscribeToTabModeChanges() {
        $tabMode
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] _ in
            self?.displayScrollButtons()
        })
        .store(in: &cancellables)
    }

    // MARK: - Tab Preview

    private var _tabPreviewWindowController: TabPreviewWindowController?
    private var tabPreviewWindowController: TabPreviewWindowController {
        if let tabPreviewWindowController = _tabPreviewWindowController {
            return tabPreviewWindowController
        }
        let tabPreviewWindowController = TabPreviewWindowController()
        _tabPreviewWindowController = tabPreviewWindowController
        return tabPreviewWindowController
    }

    private func subscribeToChildWindows() {
        guard let window = view.window else {
            assert([.unitTests, .integrationTests].contains(AppVersion.runType), "No window set at the moment of subscription")
            return
        }
        // hide Tab Preview when a non-Tab Preview child window is shown (Suggestions, Bookmarks etc…)
        window.publisher(for: \.childWindows)
            .debounce(for: 0.05, scheduler: DispatchQueue.main)
            .sink { [weak self] childWindows in
                guard let self, let childWindows, childWindows.contains(where: {
                    !(
                        $0.windowController is TabPreviewWindowController
                        || $0 === self.view.window?.titlebarView?.window // fullscreen titlebar owning window
                    )
                }) else { return }

                hideTabPreview()
            }
            .store(in: &cancellables)
    }

    private func showTabPreview(for tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        // don‘t show tab previews when a child window is shown (Suggestions, Bookmarks etc…)
        guard view.window?.childWindows?.contains(where: { !($0.windowController is TabPreviewWindowController) }) != true,
              let collectionView,
              let indexPath = collectionView.indexPath(for: tabBarViewItem)
        else {
            Logger.general.error("TabBarViewController: Showing tab preview window failed - cannot determine index path for tab")
            return
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)

        guard let tabViewModel = tabCollectionViewModel.tabViewModel(at: tabIndex) else {
            Logger.general.error("TabBarViewController: Showing tab preview window failed - tabViewModel not found for index \(String(reflecting: tabIndex))")
            return
        }

        if isPinned {
            let position = pinnedTabsContainerView.frame.minX + tabBarViewItem.view.frame.minX
            showTabPreview(for: tabViewModel, from: position)
        } else {
            guard let clipView = collectionView.clipView else {
                Logger.general.error("TabBarViewController: Showing tab preview window failed - clip view not found")
                return
            }
            let position = scrollView.frame.minX + tabBarViewItem.view.frame.minX - clipView.bounds.origin.x
            showTabPreview(for: tabViewModel, from: position)
        }
    }

    private func showPinnedTabPreview(at index: Int) {
        guard let tabViewModel = tabCollectionViewModel.pinnedTabsManager?.tabViewModel(at: index) else {
            Logger.general.error("TabBarViewController: Showing pinned tab preview window failed")
            return
        }

        let pinnedTabWidth = theme.tabStyleProvider.pinnedTabWidth
        let position = pinnedTabsContainerView.frame.minX + pinnedTabWidth * CGFloat(index)
        showTabPreview(for: tabViewModel, from: position)
    }

    private func showTabPreview(for tabViewModel: TabViewModel, from xPosition: CGFloat) {
        guard shouldDisplayTabPreviews else {
            Logger.tabPreview.error("Not showing tab preview: shouldDisplayTabPreviews == false")
            hideTabPreview(allowQuickRedisplay: true)
            return
        }

        let isSelected = tabCollectionViewModel.selectedTabViewModel === tabViewModel
        tabPreviewWindowController.tabPreviewViewController.display(tabViewModel: tabViewModel,
                                                                    isSelected: isSelected)

        guard let window = view.window else {
            Logger.general.error("TabBarViewController: Showing tab preview window failed")
            return
        }

        var point = view.bounds.origin
        point.y -= TabPreviewWindowController.padding
        point.x += xPosition
        let pointInWindow = view.convert(point, to: nil)
        tabPreviewWindowController.show(parentWindow: window, topLeftPointInWindow: pointInWindow, shouldDisplayPreviewAfterDelay: { [weak self] in
            self?.shouldDisplayTabPreviews ?? false
        })
    }

    func hideTabPreview(withDelay: Bool = false, allowQuickRedisplay: Bool = false) {
        _tabPreviewWindowController?.hide(withDelay: withDelay, allowQuickRedisplay: allowQuickRedisplay)
    }

}
// MARK: - MouseOverButtonDelegate
extension TabBarViewController: MouseOverButtonDelegate {

    func mouseOverButton(_ sender: MouseOverButton, draggingEntered info: any NSDraggingInfo, isMouseOver: UnsafeMutablePointer<Bool>) -> NSDragOperation {
        assert(sender === addTabButton || sender === addNewTabButtonFooter?.addButton)
        let pasteboard = info.draggingPasteboard

        if let types = pasteboard.types, types.contains(.string) {
            return .copy
        }
        return .none
    }

    func mouseOverButton(_ sender: MouseOverButton, performDragOperation info: any NSDraggingInfo) -> Bool {
        assert(sender === addTabButton || sender === addNewTabButtonFooter?.addButton)
        if let string = info.draggingPasteboard.string(forType: .string), let url = URL.makeURL(from: string) {
            tabCollectionViewModel.insertOrAppendNewTab(.url(url, credential: nil, source: .appOpenUrl))
            return true
        }

        return true
    }
}

// MARK: - ThemeUpdateListening
extension TabBarViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: any ThemeStyleProviding) {
        let colorsProvider = theme.colorsProvider
        let isFireWindow = tabCollectionViewModel.isBurner

        backgroundColorView.backgroundColor = colorsProvider.baseBackgroundColor

        fireButton.normalTintColor = isFireWindow ? .white : colorsProvider.iconsColor
        fireButton.mouseOverColor = isFireWindow ? .fireButtonRedHover : colorsProvider.buttonMouseOverColor

        leftScrollButton.normalTintColor = colorsProvider.iconsColor
        leftScrollButton.mouseOverColor = colorsProvider.buttonMouseOverColor

        rightScrollButton.normalTintColor = colorsProvider.iconsColor
        rightScrollButton.mouseOverColor = colorsProvider.buttonMouseOverColor

        addTabButton.normalTintColor = colorsProvider.iconsColor
        addTabButton.mouseOverColor = colorsProvider.buttonMouseOverColor
    }
}

// MARK: - TabCollectionViewModelDelegate
extension TabBarViewController: TabCollectionViewModelDelegate {

    func tabCollectionViewModelDidAppend(_ tabCollectionViewModel: TabCollectionViewModel, selected: Bool) {
        appendToCollectionView(selected: selected)
    }

    func tabCollectionViewModelDidInsert(_ tabCollectionViewModel: TabCollectionViewModel, at index: TabIndex, selected: Bool) {
        let collectionView = index.isPinnedTab ? pinnedTabsCollectionView : self.collectionView
        guard let collectionView else {
            Logger.general.error("collection view is nil")
            return
        }
        let indexPathSet = Set(arrayLiteral: IndexPath(item: index.item))
        if selected {
            clearSelection(animated: true)
        }
        collectionView.animator().insertItems(at: indexPathSet)
        if selected {
            collectionView.selectItems(at: indexPathSet, scrollPosition: .centeredHorizontally)
            collectionView.scrollToSelected()
        }

        hideTabPreview()

        if index.isUnpinnedTab {
            updateTabMode()
            updateEmptyTabArea()
            if tabMode == .overflow {
                let isLastItem = collectionView.numberOfItems(inSection: 0) == index.item + 1
                if isLastItem {
                    scrollCollectionViewToEnd()
                } else {
                    collectionView.scroll(to: IndexPath(item: index.item))
                }
            }
        }
    }

    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel,
                                didRemoveTabAt removedIndex: Int,
                                andSelectTabAt selectionIndex: Int?) {
        let removedIndexPathSet = Set(arrayLiteral: IndexPath(item: removedIndex))
        guard let selectionIndex else {
            collectionView.animator().deleteItems(at: removedIndexPathSet)
            return
        }
        let selectionIndexPathSet = Set(arrayLiteral: IndexPath(item: selectionIndex))

        self.updateTabMode(for: collectionView.numberOfItems(inSection: 0) - 1, updateLayout: false)

        // don't scroll when mouse over and removing non-last Tab
        let shouldScroll = collectionView.isAtEndScrollPosition
            && (!isMouseLocationInsideBounds || removedIndex == self.collectionView.numberOfItems(inSection: 0) - 1)
        let visiRect = collectionView.enclosingScrollView!.contentView.documentVisibleRect
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15

            collectionView.animator().performBatchUpdates {
                let tabWidth = currentTabWidth(removedIndex: removedIndex)
                if shouldScroll {
                    collectionView.animator().scroll(CGPoint(x: scrollView.contentView.bounds.origin.x - tabWidth, y: 0))
                }

                if collectionView.selectionIndexPaths != selectionIndexPathSet {
                    clearSelection()
                    collectionView.animator().selectItems(at: selectionIndexPathSet, scrollPosition: .centeredHorizontally)
                }
                collectionView.animator().deleteItems(at: removedIndexPathSet)
            } completionHandler: { [weak self] _ in
                guard let self else { return }

                self.frozenLayout = isMouseLocationInsideBounds
                if !self.frozenLayout {
                    self.updateLayout()
                }
                self.updateEmptyTabArea()
                self.enableScrollButtons()
                self.hideTabPreview()

                if !shouldScroll {
                    self.collectionView.enclosingScrollView!.contentView.scroll(to: visiRect.origin)
                }
            }
        }
    }

    /// index and newIndex are guaranteed to be from the same collection (pinned or unpinned)
    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didMoveTabAt index: TabIndex, to newIndex: TabIndex) {
        let collectionView = index.isPinnedTab ? pinnedTabsCollectionView : self.collectionView
        guard let collectionView else {
            return
        }

        let indexPath = IndexPath(item: index.item)
        let newIndexPath = IndexPath(item: newIndex.item)
        collectionView.animator().moveItem(at: indexPath, to: newIndexPath)

        if index.isUnpinnedTab {
            updateTabMode()
            hideTabPreview()
        }
    }

    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didSelectAt selectionIndex: Int?) {
        clearSelection(animated: true)
        if let selectionIndex = selectionIndex {
            let selectionIndexPathSet = Set(arrayLiteral: IndexPath(item: selectionIndex))
            collectionView.animator().selectItems(at: selectionIndexPathSet, scrollPosition: .centeredHorizontally)
            collectionView.scrollToSelected()
        }
    }

    func tabCollectionViewModelDidMultipleChanges(_ tabCollectionViewModel: TabCollectionViewModel) {
        collectionView.reloadData()
        reloadSelection()

        updateTabMode()
        enableScrollButtons()
        hideTabPreview()
        updateEmptyTabArea()

        if frozenLayout {
            updateLayout()
        }
    }

    private func appendToCollectionView(selected: Bool) {
        let lastIndex = max(0, tabCollectionViewModel.tabCollection.tabs.count - 1)
        let lastIndexPathSet = Set(arrayLiteral: IndexPath(item: lastIndex))

        if frozenLayout {
            updateLayout()
        }
        updateTabMode(for: collectionView.numberOfItems(inSection: 0) + 1)

        if selected {
            clearSelection()
        }

        if tabMode == .divided {
            collectionView.animator().insertItems(at: lastIndexPathSet)
            if selected {
                collectionView.selectItems(at: lastIndexPathSet, scrollPosition: .centeredHorizontally)
            }
        } else {
            collectionView.insertItems(at: lastIndexPathSet)
            if selected {
                collectionView.selectItems(at: lastIndexPathSet, scrollPosition: .centeredHorizontally)
            }
            scrollCollectionViewToEnd()
        }
        updateEmptyTabArea()
        hideTabPreview()
    }

    private func scrollCollectionViewToEnd() {
        // Old frameworks... need a special treatment
        collectionView.scrollToEnd { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.collectionView.scrollToEnd()
            }
        }
    }

    // MARK: - Tab Actions

    private func duplicateTab(at tabIndex: TabIndex) {
        if tabIndex.isUnpinnedTab {
            clearSelection()
        }
        tabCollectionViewModel.duplicateTab(at: tabIndex)
    }

    private func addBookmark(for tabViewModel: any TabBarViewModel) {
        // open Add Bookmark modal dialog
        guard let url = tabViewModel.tabContent.userEditableUrl else { return }

        let dialog = BookmarksDialogViewFactory.makeAddBookmarkView(
            currentTab: WebsiteInfo(url: url, title: tabViewModel.title),
            bookmarkManager: bookmarkManager
        )
        dialog.show(in: view.window)
    }

    private func deleteBookmark(with url: URL) {
        guard let bookmark = bookmarkManager.getBookmark(for: url) else {
            Logger.general.error("TabBarViewController: Failed to fetch bookmark for url \(url)")
            return
        }
        bookmarkManager.remove(bookmark: bookmark, undoManager: nil)
    }

    private func fireproof(_ tab: Tab) {
        guard let url = tab.url, let host = url.host else {
            Logger.general.error("TabBarViewController: Failed to get url of tab bar view item")
            return
        }

        fireproofDomains.add(domain: host)
    }

    private func removeFireproofing(from tab: Tab) {
        guard let host = tab.url?.host else {
            Logger.general.error("TabBarViewController: Failed to get url of tab bar view item")
            return
        }

        fireproofDomains.remove(domain: host)
    }

}

// MARK: - NSCollectionViewDelegateFlowLayout

extension TabBarViewController: NSCollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        guard collectionView != pinnedTabsCollectionView else {
            return NSSize(width: pinnedTabWidth, height: pinnedTabHeight)
        }
        let isItemSelected = tabCollectionViewModel.selectionIndex == .unpinned(indexPath.item)
        return NSSize(width: self.currentTabWidth(selected: isItemSelected), height: standardTabHeight)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets {
        let isPinnedTabs = collectionView == pinnedTabsCollectionView
        if isPinnedTabs {
            return NSEdgeInsetsZero
        }
        if theme.tabStyleProvider.shouldShowSShapedTab {
            let isRightScrollButtonVisible = !isPinnedTabs && !rightScrollButton.isHidden
            let isLeftScrollButonVisible = !isPinnedTabs && !leftScrollButton.isHidden
            return NSEdgeInsets(top: 0, left: isLeftScrollButonVisible ? 6 : 12, bottom: 0, right: isRightScrollButtonVisible ? 6 : -12)
        } else if let flowLayout = collectionViewLayout as? NSCollectionViewFlowLayout {
            return flowLayout.sectionInset
        } else {
            return NSEdgeInsetsZero
        }
    }
}

// MARK: - NSCollectionViewDataSource

extension TabBarViewController: NSCollectionViewDataSource {

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == pinnedTabsCollectionView {
            return tabCollectionViewModel.pinnedTabsCollection?.tabs.count ?? 0
        }
        return tabCollectionViewModel.tabCollection.tabs.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: TabBarViewItem.identifier, for: indexPath)
        guard let tabBarViewItem = item as? TabBarViewItem else {
            assertionFailure("TabBarViewController: Failed to get reusable TabBarViewItem instance")
            return item
        }

        let tabIndex: TabIndex = collectionView == pinnedTabsCollectionView ? .pinned(indexPath.item) : .unpinned(indexPath.item)

        guard let tabViewModel = tabCollectionViewModel.tabViewModel(at: tabIndex) else {
            tabBarViewItem.clear()
            return tabBarViewItem
        }

        tabBarViewItem.fireproofDomains = fireproofDomains
        tabBarViewItem.delegate = self
        tabBarViewItem.isBurner = tabCollectionViewModel.isBurner
        tabBarViewItem.subscribe(to: tabViewModel)

        if let pinnedTabsCollectionView, pinnedTabsCollectionView == collectionView {
            tabBarViewItem.isLeftToSelected = pinnedTabsCollectionView.isLastItemInSection(indexPath: indexPath) && shouldHideLastPinnedSeparator
        }

        return tabBarViewItem
    }

    func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind, at indexPath: IndexPath) -> NSView {
        let view = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: TabBarFooter.identifier, for: indexPath)
        if let tabBarFooter = view as? TabBarFooter {
            tabBarFooter.target = self
        }
        return view
    }

    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        (item as? TabBarViewItem)?.clear()
    }

}

// MARK: - NSCollectionViewDelegate

extension TabBarViewController: NSCollectionViewDelegate {

    func collectionView(_ collectionView: NSCollectionView,
                        didChangeItemsAt indexPaths: Set<IndexPath>,
                        to highlightState: NSCollectionViewItem.HighlightState) {
        guard indexPaths.count == 1, let indexPath = indexPaths.first else {
            assertionFailure("TabBarViewController: More than 1 item highlighted")
            return
        }

        if highlightState == .forSelection {
            clearSelection()

            let tabIndex: TabIndex = collectionView == pinnedTabsCollectionView ? .pinned(indexPath.item) : .unpinned(indexPath.item)
            tabCollectionViewModel.select(at: tabIndex)

            // Poor old NSCollectionView
            DispatchQueue.main.async {
                self.collectionView.scrollToSelected()
            }
        }

        hideTabPreview()
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        TabBarViewItemPasteboardWriter()
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
        session.animatesToStartingPositionsOnCancelOrFail = false

        assert(indexPaths.count == 1, "TabBarViewController: More than 1 dragging index path")
        guard let indexPath = indexPaths.first else { return }

        let tabIndex: TabIndex = collectionView == pinnedTabsCollectionView ? .pinned(indexPath.item) : .unpinned(indexPath.item)

        TabDragAndDropManager.shared.setSource(tabCollectionViewModel: tabCollectionViewModel, index: tabIndex)
        hideTabPreview()
    }

    private static let dropToOpenDistance: CGFloat = 100

    func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        switch (collectionView, draggingInfo.draggingSource as? NSCollectionView) {
        case (self.collectionView, pinnedTabsCollectionView), (pinnedTabsCollectionView, self.collectionView):
            /// drag & drop between pinned and unpinned collection is not supported yet
            return .none
        default:
            break
        }

        // allow dropping URLs or files
        guard draggingInfo.draggingPasteboard.url == nil else { return .copy }

        // Check if the pasteboard contains string data
        if draggingInfo.draggingPasteboard.availableType(from: [.string]) != nil {
            return .copy
        }

        // dragging a tab
        guard case .private = draggingInfo.draggingSourceOperationMask,
              draggingInfo.draggingPasteboard.types == [TabBarViewItemPasteboardWriter.utiInternalType] else { return .none }

        let tabIndex: TabIndex = collectionView == pinnedTabsCollectionView ? .pinned(proposedDropIndexPath.pointee.item) : .unpinned(proposedDropIndexPath.pointee.item)

        // move tab within one window if needed: bail out if we're outside the CollectionView Bounds!
        let isPinnedTabsRewriteEnabled = featureFlagger.isFeatureOn(.pinnedTabsViewRewrite)
        let locationInView = collectionView.convert(draggingInfo.draggingLocation, from: nil)

        guard collectionView.frame.contains(locationInView) || !isPinnedTabsRewriteEnabled else {
            return .none
        }

        moveItemIfNeeded(to: tabIndex)

        return .private
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let tabCollection = collectionView == pinnedTabsCollectionView ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection
        guard let tabCollection else {
            return false
        }

        let newIndex = min(indexPath.item + 1, tabCollection.tabs.count)
        let tabIndex: TabIndex = collectionView == pinnedTabsCollectionView ? .pinned(newIndex) : .unpinned(newIndex)

        if let url = draggingInfo.draggingPasteboard.url {
            // dropping URL or file
            tabCollectionViewModel.insert(Tab(content: .url(url, source: .appOpenUrl), burnerMode: tabCollectionViewModel.burnerMode),
                                          at: tabIndex,
                                          selected: true)
            return true
        } else if let string = draggingInfo.draggingPasteboard.string(forType: .string), let url = URL.makeURL(from: string) {
            tabCollectionViewModel.insertOrAppendNewTab(.url(url, credential: nil, source: .appOpenUrl))
            return true
        }

        guard case .private = draggingInfo.draggingSourceOperationMask,
              draggingInfo.draggingPasteboard.types == [TabBarViewItemPasteboardWriter.utiInternalType] else { return false }

        // update drop destination
        TabDragAndDropManager.shared.setDestination(tabCollectionViewModel: tabCollectionViewModel, index: tabIndex)

        return true
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        // dropping a tab, dropping of url handled in collectionView:acceptDrop:
        guard session.draggingPasteboard.types == [TabBarViewItemPasteboardWriter.utiInternalType] else { return }

        // Don't allow drag and drop from Burner Window
        guard !tabCollectionViewModel.burnerMode.isBurner else { return }

        defer {
            TabDragAndDropManager.shared.clear()
        }

        if case .private = operation {
            // Perform the drag and drop between multiple windows
            TabDragAndDropManager.shared.performDragAndDropIfNeeded()
            DispatchQueue.main.async {
                self.collectionView.scrollToSelected()
            }
            return
        }
        // dropping not on a tab bar
        guard case .none = operation else { return }

        // Create a new window if dragged upward or too distant
        let frameRelativeToWindow = view.convert(view.bounds, to: nil)
        guard TabDragAndDropManager.shared.sourceUnit?.tabCollectionViewModel === tabCollectionViewModel,
              let sourceIndex = TabDragAndDropManager.shared.sourceUnit?.index,
              let frameRelativeToScreen = view.window?.convertToScreen(frameRelativeToWindow) else {
            return
        }

        // Check if the drop point is above the tab bar by more than 10 points
        let isDroppedAboveTabBar = screenPoint.y > (frameRelativeToScreen.maxY + 10)

        // Create new window if dropped above tab bar or too far away
        // But not for pinned tabs
        if collectionView != pinnedTabsCollectionView && (isDroppedAboveTabBar || !screenPoint.isNearRect(frameRelativeToScreen, allowedDistance: Self.dropToOpenDistance)) {
            moveToNewWindow(from: sourceIndex.item,
                           droppingPoint: screenPoint,
                           burner: tabCollectionViewModel.isBurner)
        }
    }

    func collectionView(_ collectionView: NSCollectionView,
                        layout collectionViewLayout: NSCollectionViewLayout,
                        referenceSizeForFooterInSection section: Int) -> NSSize {
        guard collectionView != pinnedTabsCollectionView else {
            return .zero
        }
        if tabMode == .overflow {
            return .zero
        } else {
            let width = footerCurrentWidthDimension
            return NSSize(width: width, height: collectionView.frame.size.height)
        }
    }

}

// MARK: - TabBarViewItemDelegate

extension TabBarViewController: TabBarViewItemDelegate {

    func tabBarViewItemSelectTab(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
        tabCollectionViewModel.select(at: tabIndex)
    }

    func tabBarViewItemCrashAction(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
        tabCollectionViewModel.tabViewModel(at: tabIndex)?.tab.killWebContentProcess()
    }

    func tabBarViewItemCrashMultipleTimesAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        tabCollectionViewModel.tabViewModel(at: indexPath.item)?.tab.killWebContentProcessMultipleTimes()
    }

    func tabBarViewItemDidUpdateCrashInfoPopoverVisibility(_ tabBarViewItem: TabBarViewItem, sender: NSButton, shouldShow: Bool) {
        guard shouldShow else {
            crashPopoverViewController?.dismiss()
            return
        }

        DispatchQueue.main.async {
            let viewController = PopoverMessageViewController(
                title: UserText.tabCrashPopoverTitle,
                message: UserText.tabCrashPopoverMessage,
                presentMultiline: true,
                maxWidth: TabCrashIndicatorModel.Const.popoverWidth,
                autoDismissDuration: nil,
                onDismiss: {
                    tabBarViewItem.hideCrashIndicatorButton()
                },
                onClick: {
                    tabBarViewItem.hideCrashIndicatorButton()
                }
            )
            self.crashPopoverViewController = viewController
            viewController.show(onParent: self, relativeTo: sender, behavior: .semitransient)
        }
    }

    func tabBarViewItem(_ tabBarViewItem: TabBarViewItem, isMouseOver: Bool) {
        if isMouseOver {
            // Show tab preview for visible tab bar items
            if collectionView.visibleRect.intersects(tabBarViewItem.view.frame) {
                showTabPreview(for: tabBarViewItem)
            }
        } else if !shouldDisplayTabPreviews {
            hideTabPreview(withDelay: true, allowQuickRedisplay: true)
        }
    }

    func tabBarViewItemShouldHideSeparator(_ tabBarViewItem: TabBarViewItem) -> Bool {
        guard
            let sourceCollectionView = tabBarViewItem.isPinned ? pinnedTabsCollectionView : collectionView,
            let sourceIndexPath = sourceCollectionView.indexPath(for: tabBarViewItem) else { return false }

        // Scenario: Last Pinned Item
        if tabBarViewItem.isPinned && sourceCollectionView.isLastItemInSection(indexPath: sourceIndexPath) {
            return shouldHideLastPinnedSeparator
        }

        // Scenario: The Item itself is Highlighted
        if tabBarViewItem.isMouseOver || tabBarViewItem.isSelected {
            return true
        }

        // Scenario: Item on the Right Hand Side Exists
        if let rightItem = sourceCollectionView.nextItem(for: sourceIndexPath) as? TabBarViewItem {
            return rightItem.isSelected || rightItem.isMouseOver
        }

        return false
    }

    func tabBarViewItemCanBeDuplicated(_ tabBarViewItem: TabBarViewItem) -> Bool {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return false
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
        return tabCollectionViewModel.tabViewModel(at: tabIndex)?.tab.content.canBeDuplicated ?? false
    }

    func tabBarViewItemDuplicateAction(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        duplicateTab(at: isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item))
    }

    func tabBarViewItemCanBePinned(_ tabBarViewItem: TabBarViewItem) -> Bool {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        guard !isPinned else {
            return false
        }
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return false
        }

        return tabCollectionViewModel.tabViewModel(at: indexPath.item)?.tab.content.canBePinned ?? false
    }

    func tabBarViewItemPinAction(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        clearSelection()

        if isPinned {
            tabCollectionViewModel.unpinTab(at: indexPath.item)
        } else {
            tabCollectionViewModel.pinTab(at: indexPath.item)
            presentPinnedTabsDiscoveryPopoverIfNecessary()
        }

    }

    func presentPinnedTabsDiscoveryPopoverIfNecessary() {
        guard !PinnedTabsDiscoveryPopover.popoverPresented else { return }
        PinnedTabsDiscoveryPopover.popoverPresented = true

        // Present only in case shared pinned tabs are set
        guard pinnedTabsManagerProvider.pinnedTabsMode == .shared else { return }

        // Wait until pinned tab change is applied to pinned tabs view
        DispatchQueue.main.asyncAfter(deadline: .now() + 1/3) { [weak self] in
            guard let self else { return }

            let popover = self.pinnedTabsDiscoveryPopover ?? PinnedTabsDiscoveryPopover(callback: { [weak self ] _ in
                self?.pinnedTabsDiscoveryPopover?.close()
            })

            self.pinnedTabsDiscoveryPopover = popover

            guard let view = self.pinnedTabsHostingView else { return }
            let pinnedTabWidth = theme.tabStyleProvider.pinnedTabWidth
            popover.show(relativeTo: NSRect(x: view.bounds.maxX - pinnedTabWidth,
                                            y: view.bounds.minY,
                                            width: pinnedTabWidth,
                                            height: view.bounds.height),
                         of: view,
                         preferredEdge: .maxY)
        }
    }

    func tabBarViewItemCanBeBookmarked(_ tabBarViewItem: TabBarViewItem) -> Bool {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return false
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
        return tabCollectionViewModel.tabViewModel(at: tabIndex)?.tab.content.canBeBookmarked ?? false
    }

    func tabBarViewItemIsAlreadyBookmarked(_ tabBarViewItem: TabBarViewItem) -> Bool {
        guard let tabViewModel = tabBarViewItem.tabViewModel,
              let url = tabViewModel.tabContent.userEditableUrl else { return false }

        return bookmarkManager.isUrlBookmarked(url: url)
    }

    func tabBarViewItemBookmarkThisPageAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabViewModel = tabBarViewItem.tabViewModel else { return }
        addBookmark(for: tabViewModel)
    }

    func tabBarViewItemRemoveBookmarkAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabViewModel = tabBarViewItem.tabViewModel,
              let url = tabViewModel.tabContent.userEditableUrl else { return }

        deleteBookmark(with: url)
    }

    func tabBarViewAllItemsCanBeBookmarked(_ tabBarViewItem: TabBarViewItem) -> Bool {
        tabCollectionViewModel.canBookmarkAllOpenTabs()
    }

    func tabBarViewItemBookmarkAllOpenTabsAction(_ tabBarViewItem: TabBarViewItem) {
        let websitesInfo = tabCollectionViewModel.tabs.compactMap(WebsiteInfo.init)
        BookmarksDialogViewFactory.makeBookmarkAllOpenTabsView(
            websitesInfo: websitesInfo,
            bookmarkManager: bookmarkManager
        ).show()
    }

    func tabBarViewItemWillOpenContextMenu(_: TabBarViewItem) {
        hideTabPreview()
    }

    func tabBarViewItemCloseAction(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
        tabCollectionViewModel.remove(at: tabIndex)
    }

    func tabBarViewItemTogglePermissionAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem),
              let permissions = tabCollectionViewModel.tabViewModel(at: indexPath.item)?.tab.permissions
        else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item or its permissions")
            return
        }

        if permissions.permissions.camera.isActive || permissions.permissions.microphone.isActive {
            permissions.set([.camera, .microphone], muted: true)
        } else if permissions.permissions.camera.isPaused || permissions.permissions.microphone.isPaused {
            permissions.set([.camera, .microphone], muted: false)
        } else {
            assertionFailure("Unexpected Tab Permissions state")
        }
    }

    func tabBarViewItemCloseOtherAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        tabCollectionViewModel.removeAllTabs(except: indexPath.item)
    }

    func tabBarViewItemCloseToTheLeftAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        tabCollectionViewModel.removeTabs(before: indexPath.item)
    }

    func tabBarViewItemCloseToTheRightAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        tabCollectionViewModel.removeTabs(after: indexPath.item)
    }

    func tabBarViewItemMoveToNewWindowAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        moveToNewWindow(from: indexPath.item, burner: false)
    }

    func tabBarViewItemMoveToNewBurnerWindowAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        moveToNewWindow(from: indexPath.item, burner: true)
    }

    func tabBarViewItemFireproofSite(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView
        let tabCollection = isPinned ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem),
              let tab = tabCollection?.tabs[safe: indexPath.item]
        else {
            assertionFailure("TabBarViewController: Failed to get tab from tab bar view item")
            return
        }

        fireproof(tab)
    }

    func tabBarViewItemMuteUnmuteSite(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView
        let tabCollection = isPinned ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem),
              let tab = tabCollection?.tabs[safe: indexPath.item]
        else {
            assertionFailure("TabBarViewController: Failed to get tab from tab bar view item")
            return
        }

        tab.muteUnmuteTab()
    }

    func tabBarViewItemRemoveFireproofing(_ tabBarViewItem: TabBarViewItem) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView
        let tabCollection = isPinned ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem),
              let tab = tabCollection?.tabs[safe: indexPath.item]
        else {
            assertionFailure("TabBarViewController: Failed to get tab from tab bar view item")
            return
        }

        removeFireproofing(from: tab)
    }

    func tabBarViewItem(_ tabBarViewItem: TabBarViewItem, replaceContentWithDroppedStringValue stringValue: String) {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView
        let tabCollection = isPinned ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem),
              let tab = tabCollection?.tabs[safe: indexPath.item] else { return }

        if let url = URL.makeURL(from: stringValue) {
            tab.setContent(.url(url, credential: nil, source: .userEntered(stringValue, downloadRequested: false)))
        }
    }

    func otherTabBarViewItemsState(for tabBarViewItem: TabBarViewItem) -> OtherTabBarViewItemsState {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView
        let tabCollection = isPinned ? tabCollectionViewModel.pinnedTabsCollection : tabCollectionViewModel.tabCollection

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return .init(hasItemsToTheLeft: false, hasItemsToTheRight: false)
        }
        return .init(hasItemsToTheLeft: indexPath.item > 0,
                     hasItemsToTheRight: indexPath.item + 1 < (tabCollection?.tabs.count ?? 0))
    }

}

extension TabBarViewController {

    func startFireButtonPulseAnimation() {
        ViewHighlighter.highlight(view: fireButton, inParent: view)
    }

    func stopFireButtonPulseAnimation() {
        ViewHighlighter.stopHighlighting(view: fireButton)
    }

}

// MARK: - TabBarViewItemPasteboardWriter

final class TabBarViewItemPasteboardWriter: NSObject, NSPasteboardWriting {

    static let utiInternalType = NSPasteboard.PasteboardType(rawValue: "com.duckduckgo.tab.internal")

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [Self.utiInternalType]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        [String: Any]()
    }

}
