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

import Cocoa
import Combine
import Common
import Lottie
import os.log
import PixelKit
import PrivacyConfig
import RemoteMessaging
import SwiftUI
import WebKit

final class TabBarViewController: NSViewController, TabBarRemoteMessagePresenting {

    enum HorizontalSpace: CGFloat {
        case pinnedTabsScrollViewPadding = 76
        case pinnedTabsScrollViewPaddingMacOS26 = 84
    }

    private enum AIChatPresentationMode {
        case hidden, sidebar, floating
    }

    private enum Constants {
        static let duckAISidebarOpenImageName = NSImage.Name("Sidebar-Open-16")
        static let duckAISidebarCloseImageName = NSImage.Name("Sidebar-Close-16")
        static let duckAISidebarDetachedImageName = NSImage.Name("Sidebar-Detached-16")
        static let duckAIControlSpacingBeforeFireButton: CGFloat = 5
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

    private var fireWindowBackgroundView: NSImageView?

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
    private var aiChatChromeSidebarFeatureFlagCancellable: AnyCancellable?
    private var aiChatSidebarPresenceCancellable: AnyCancellable?
    private var aiChatFloatingStateCancellable: AnyCancellable?
    private var aiChatMenuConfigCancellable: AnyCancellable?
    private var aiChatButtonHoverCancellable: AnyCancellable?
    private var duckAIChromeButtonsVisibilityCancellable: AnyCancellable?
    private var duckAIChromeDividerInsetConstraint: NSLayoutConstraint?
    private var duckAIChromeDividerFullConstraint: NSLayoutConstraint?
    private var currentAIChatPresentationMode: AIChatPresentationMode = .hidden
    private var selectedTabViewModelCancellable: AnyCancellable?
    private var tabContentCancellable: AnyCancellable?
    private let duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging
    private lazy var duckAIChromeContextMenu: NSMenu = {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }()

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
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let pinnedTabsManagerProvider: PinnedTabsManagerProviding = Application.appDelegate.pinnedTabsManagerProvider
    private var pinnedTabsDiscoveryPopover: NSPopover?
    private weak var crashPopoverViewController: PopoverMessageViewController?
    private let autoconsentStatsPopoverCoordinator: AutoconsentStatsPopoverCoordinating?

    let themeManager: ThemeManaging
    private let tabDragAndDropManager: TabDragAndDropManager
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
    var aiChatCoordinator: AIChatCoordinating? {
        didSet {
            subscribeToAIChatSidebarChanges()
            updateDuckAIChromeSegmentedControlState()
        }
    }
    private var aiChatCloseWarningPresenter: WarnBeforeQuitOverlayPresenter?

    // TabBarRemoteMessagePresentable
    var tabBarRemoteMessageViewModel: TabBarRemoteMessageViewModel
    var tabBarRemoteMessagePopover: NSPopover?
    var tabBarRemoteMessagePopoverHoverTimer: Timer?
    var feedbackBarButtonHostingController: NSHostingController<TabBarRemoteMessageView>?
    var tabBarRemoteMessageCancellable: AnyCancellable?

    @IBOutlet weak var shadowView: TabShadowView!

    @IBOutlet weak var leftSideStackLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var rightSideStackView: NSStackView!
    private var duckAIChromeControlContainer: ColorView?
    var duckAISplitButtonContainer: NSView? { duckAIChromeControlContainer }
    private var duckAIChromeBlurView: NSVisualEffectView?
    private var duckAIChromeTitleButton: MouseOverButton?
    private var duckAIChromeSidebarButton: MouseOverButton?
    private var duckAIChromeDivider: ColorView?

    private var isFireWindow: Bool {
        tabCollectionViewModel.isBurner
    }

    private var isChromeSidebarFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatChromeSidebar)
    }

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
        featureFlagger: FeatureFlagger,
        aiChatMenuConfig: AIChatMenuVisibilityConfigurable = NSApp.delegateTyped.aiChatMenuConfiguration,
        duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging = LocalDuckAIChromeButtonsVisibilityManager(),
        tabDragAndDropManager: TabDragAndDropManager,
        autoconsentStatsPopoverCoordinator: AutoconsentStatsPopoverCoordinating? = nil
    ) -> TabBarViewController {
        NSStoryboard(name: "TabBar", bundle: nil).instantiateInitialController { coder in
            self.init(
                coder: coder,
                tabCollectionViewModel: tabCollectionViewModel,
                bookmarkManager: bookmarkManager,
                fireproofDomains: fireproofDomains,
                activeRemoteMessageModel: activeRemoteMessageModel,
                featureFlagger: featureFlagger,
                aiChatMenuConfig: aiChatMenuConfig,
                duckAIChromeButtonsVisibilityManager: duckAIChromeButtonsVisibilityManager,
                tabDragAndDropManager: tabDragAndDropManager,
                autoconsentStatsPopoverCoordinator: autoconsentStatsPopoverCoordinator
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
          aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
          duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging,
          themeManager: ThemeManager = NSApp.delegateTyped.themeManager,
          tabDragAndDropManager: TabDragAndDropManager,
          autoconsentStatsPopoverCoordinator: AutoconsentStatsPopoverCoordinating? = nil) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.fireproofDomains = fireproofDomains
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfig = aiChatMenuConfig
        self.duckAIChromeButtonsVisibilityManager = duckAIChromeButtonsVisibilityManager
        let tabBarActiveRemoteMessageModel = TabBarActiveRemoteMessage(activeRemoteMessageModel: activeRemoteMessageModel)
        self.tabBarRemoteMessageViewModel = TabBarRemoteMessageViewModel(
            activeRemoteMessageModel: tabBarActiveRemoteMessageModel,
            isFireWindow: tabCollectionViewModel.isBurner
        )
        self.themeManager = themeManager
        self.tabDragAndDropManager = tabDragAndDropManager
        self.autoconsentStatsPopoverCoordinator = autoconsentStatsPopoverCoordinator

        standardTabHeight = themeManager.theme.tabStyleProvider.standardTabHeight
        pinnedTabHeight = themeManager.theme.tabStyleProvider.pinnedTabHeight
        pinnedTabWidth = themeManager.theme.tabStyleProvider.pinnedTabWidth

        super.init(coder: coder)

        initializePinnedTabs()
    }

    private func initializePinnedTabs() {
        guard !tabCollectionViewModel.isBurner else {
            return
        }

        initializePinnedTabsAppKitView()
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
        setupConstraints()
        setupFireButton()
        subscribeToChromeSidebarFeatureFlag()
        subscribeToDuckAIChromeButtonsVisibilityChanges()
        setupPinnedTabsView()
        subscribeToTabModeChanges()
        setupAddTabButton()
        setupAsBurnerWindowIfNeeded(theme: theme)
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

    override func mouseDown(with event: NSEvent) {
        if showDuckAIChromeContextMenuIfNeeded(for: event) { return }
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if showDuckAIChromeContextMenuIfNeeded(for: event) { return }
        super.rightMouseDown(with: event)
    }

    private func showDuckAIChromeContextMenuIfNeeded(for event: NSEvent) -> Bool {
        guard isChromeSidebarFeatureEnabled,
              aiChatMenuConfig.shouldDisplayAnyAIChatFeature,
              let container = duckAIChromeControlContainer,
              !container.isHidden else { return false }
        let clickInContainer = container.bounds.contains(container.convert(event.locationInWindow, from: nil))
        let isContextEvent = event.isContextClick || event.type == .rightMouseDown

        guard clickInContainer, isContextEvent else { return false }
        NSMenu.popUpContextMenu(duckAIChromeContextMenu, with: event, for: container)
        return true
    }

    override func viewWillDisappear() {
        mouseDownCancellable = nil
        tabBarRemoteMessageCancellable = nil
        disableChromeSidebarObservers()
        dismissAIChatCloseWarningPresenter()
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
        dismissAIChatCloseWarningPresenter()
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
            self?.updateDuckAIChromeSegmentedControlState()
        }
    }

    private func subscribeToSelectedTabViewModel() {
        selectedTabViewModelCancellable = tabCollectionViewModel.$selectedTabViewModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedTabViewModel in
                self?.subscribeToTabContent(selectedTabViewModel: selectedTabViewModel)
                self?.updateDuckAIChromeSegmentedControlState()
            }
    }

    private func subscribeToTabContent(selectedTabViewModel: TabViewModel?) {
        tabContentCancellable = selectedTabViewModel?.tab.$content
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDuckAIChromeSegmentedControlState()
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

                subscribeToPinnedTabsCollection()
                updatePinnedTabsViewModel()
            }.store(in: &cancellables)
    }

    private func updatePinnedTabsViewModel() {
        guard tabCollectionViewModel.pinnedTabsCollection != nil else { return }

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

    private func setupConstraints() {
        var pinnedTabsLeadingSpace: TabBarViewController.HorizontalSpace = .pinnedTabsScrollViewPadding
        if #available(macOS 26, *) {
            pinnedTabsLeadingSpace = .pinnedTabsScrollViewPaddingMacOS26
        }

        pinnedTabsViewLeadingConstraint.constant = pinnedTabsLeadingSpace.rawValue
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

    private func setupDuckAIChromeSegmentedControl() {
        guard duckAIChromeControlContainer == nil else { return }

        enableDuckAIChromeContextMenuOnTabBar()

        let container = ColorView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setAccessibilityIdentifier("TabBarViewController.duckAIChromeControlContainer")

        let titleButton = MouseOverButton(frame: .zero)
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        titleButton.title = UserText.aiChatTitle
        titleButton.isBordered = false
        titleButton.setButtonType(.momentaryPushIn)
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.target = self
        titleButton.action = #selector(duckAITitlebarButtonAction(_:))
        titleButton.sendAction(on: .leftMouseDown)
        titleButton.setAccessibilityIdentifier("TabBarViewController.duckAIChromeTitleButton")
        titleButton.setAccessibilityTitle(UserText.aiChatOpenNewTabButton)
        titleButton.toolTip = UserText.aiChatOpenNewTabButton

        let divider = ColorView(frame: .zero)
        divider.translatesAutoresizingMaskIntoConstraints = false

        let sidebarButton = MouseOverButton(frame: .zero)
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false
        sidebarButton.isBordered = false
        sidebarButton.target = self
        sidebarButton.action = #selector(duckAIChromeSidebarButtonAction(_:))
        sidebarButton.sendAction(on: .leftMouseDown)
        sidebarButton.image = duckAISidebarIcon(for: .hidden)
        sidebarButton.setAccessibilityIdentifier("TabBarViewController.duckAIChromeSidebarButton")
        sidebarButton.setAccessibilityTitle(UserText.aiChatOpenSidebarButton)
        sidebarButton.toolTip = UserText.aiChatOpenSidebarButton

        let contentStack = NSStackView(views: [titleButton, divider, sidebarButton])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.distribution = .fill
        contentStack.spacing = 0
        container.addSubview(contentStack)

        let dividerInset = divider.heightAnchor.constraint(equalToConstant: max(12, theme.tabBarButtonSize - 12))
        let dividerFull = divider.heightAnchor.constraint(equalTo: container.heightAnchor)
        dividerInset.isActive = true

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: theme.tabBarButtonSize),
            titleButton.heightAnchor.constraint(equalTo: container.heightAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            sidebarButton.heightAnchor.constraint(equalTo: container.heightAnchor),
            sidebarButton.widthAnchor.constraint(equalToConstant: theme.tabBarButtonSize + 4)
        ])

        duckAIChromeDividerInsetConstraint = dividerInset
        duckAIChromeDividerFullConstraint = dividerFull

        if let fireButtonIndex = rightSideStackView.arrangedSubviews.firstIndex(of: fireButton) {
            rightSideStackView.insertArrangedSubview(container, at: fireButtonIndex)
        } else {
            rightSideStackView.addArrangedSubview(container)
        }
        rightSideStackView.setCustomSpacing(rightSideStackView.spacing + Constants.duckAIControlSpacingBeforeFireButton, after: container)

        duckAIChromeControlContainer = container
        duckAIChromeTitleButton = titleButton
        duckAIChromeSidebarButton = sidebarButton
        duckAIChromeDivider = divider

        aiChatButtonHoverCancellable = Publishers.Merge4(
            titleButton.publisher(for: \.isMouseOver),
            titleButton.publisher(for: \.isMouseDown),
            sidebarButton.publisher(for: \.isMouseOver),
            sidebarButton.publisher(for: \.isMouseDown)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.updateDuckAIChromeDividerState() }

        container.menu = duckAIChromeContextMenu

        updateDuckAIChromeSegmentedControlAppearance()
        applyDuckAIChromeButtonVisibility()
        updateDuckAIChromeSegmentedControlState()
    }

    private func applyDuckAIChromeButtonVisibility() {
        guard let container = duckAIChromeControlContainer,
              let titleButton = duckAIChromeTitleButton,
              let sidebarButton = duckAIChromeSidebarButton,
              let divider = duckAIChromeDivider else { return }

        guard aiChatMenuConfig.shouldDisplayAnyAIChatFeature else {
            disableDuckAIChromeContextMenuOnTabBar()
            container.menu = nil
            titleButton.isHidden = true
            sidebarButton.isHidden = true
            divider.isHidden = true
            container.isHidden = true
            updateDuckAIChromeVibrancyBackground()
            return
        }

        enableDuckAIChromeContextMenuOnTabBar()
        container.menu = duckAIChromeContextMenu

        let duckAIHidden = duckAIChromeButtonsVisibilityManager.isHidden(.duckAI)
        let sidebarHidden = duckAIChromeButtonsVisibilityManager.isHidden(.sidebar)

        titleButton.isHidden = duckAIHidden
        sidebarButton.isHidden = sidebarHidden
        divider.isHidden = duckAIHidden || sidebarHidden
        container.isHidden = duckAIHidden && sidebarHidden

        if !duckAIHidden && !sidebarHidden {
            titleButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
            sidebarButton.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            container.backgroundColor = isFireWindow ? .clear : theme.colorsProvider.buttonMouseOverColor
        } else if !duckAIHidden {
            titleButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            container.backgroundColor = isFireWindow ? .clear : theme.colorsProvider.buttonMouseOverColor
        } else if !sidebarHidden {
            sidebarButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            container.backgroundColor = .clear
        }

        updateDuckAIChromeVibrancyBackground()
    }

    func refreshDuckAIChromeButtonsVisibility() {
        applyDuckAIChromeButtonVisibility()
        updateDuckAIChromeSegmentedControlState()
    }

    private func subscribeToDuckAIChromeButtonsVisibilityChanges() {
        duckAIChromeButtonsVisibilityCancellable = NotificationCenter.default.publisher(for: .duckAIChromeButtonsVisibilityChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDuckAIChromeButtonsVisibility()
            }
    }

    private func updateDuckAIChromeSegmentedControlAppearance() {
        guard let duckAIChromeControlContainer, let duckAIChromeTitleButton, let duckAIChromeSidebarButton else { return }

        let colorsProvider = theme.colorsProvider
        duckAIChromeControlContainer.backgroundColor = isFireWindow ? .clear : colorsProvider.buttonMouseOverColor
        duckAIChromeControlContainer.cornerRadius = theme.toolbarButtonsCornerRadius
        duckAIChromeControlContainer.borderColor = nil
        duckAIChromeControlContainer.borderWidth = 0

        updateDuckAIChromeVibrancyBackground()

        let titleFont = NSFont.systemFont(ofSize: 13)
        duckAIChromeTitleButton.attributedTitle = NSAttributedString(string: UserText.aiChatTitle, attributes: [
            .foregroundColor: colorsProvider.textPrimaryColor,
            .font: titleFont
        ])
        duckAIChromeTitleButton.backgroundColor = .clear
        duckAIChromeTitleButton.mouseOverColor = colorsProvider.buttonMouseDownColor
        duckAIChromeTitleButton.mouseDownColor = colorsProvider.buttonMouseDownPressedColor
        duckAIChromeTitleButton.setCornerRadius(theme.toolbarButtonsCornerRadius)
        duckAIChromeTitleButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        duckAIChromeTitleButton.horizontalPadding = 16

        duckAIChromeSidebarButton.backgroundColor = .clear
        duckAIChromeSidebarButton.mouseOverColor = colorsProvider.buttonMouseDownColor
        duckAIChromeSidebarButton.mouseDownColor = colorsProvider.buttonMouseDownPressedColor
        duckAIChromeSidebarButton.normalTintColor = colorsProvider.iconsColor
        duckAIChromeSidebarButton.mouseOverTintColor = colorsProvider.iconsColor
        duckAIChromeSidebarButton.mouseDownTintColor = colorsProvider.iconsColor
        duckAIChromeSidebarButton.setCornerRadius(theme.toolbarButtonsCornerRadius)
        duckAIChromeSidebarButton.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        applyDuckAIChromeButtonVisibility()
        updateDuckAIChromeDividerState()
    }

    private func updateDuckAIChromeDividerState() {
        let isInteractionEnabled = duckAIChromeTitleButton?.isEnabled == true &&
            duckAIChromeSidebarButton?.isEnabled == true
        let isInteracting = isInteractionEnabled && (
            duckAIChromeTitleButton?.isMouseOver == true ||
                            duckAIChromeTitleButton?.isMouseDown == true ||
                            duckAIChromeSidebarButton?.isMouseOver == true ||
                            duckAIChromeSidebarButton?.isMouseDown == true
        )
        let showFullHeight = isInteracting || currentAIChatPresentationMode != .hidden

        if showFullHeight {
            duckAIChromeDividerInsetConstraint?.isActive = false
            duckAIChromeDividerFullConstraint?.isActive = true
        } else {
            duckAIChromeDividerFullConstraint?.isActive = false
            duckAIChromeDividerInsetConstraint?.isActive = true
        }
        let colorsProvider = theme.colorsProvider
        duckAIChromeDivider?.backgroundColor = showFullHeight ?
            colorsProvider.separatorActiveColor : colorsProvider.separatorColor
    }

    private func updateDuckAIChromeVibrancyBackground() {
        guard let duckAIChromeControlContainer else { return }

        if isFireWindow {
            if duckAIChromeBlurView == nil {
                let vibrancyView = NSVisualEffectView()
                vibrancyView.translatesAutoresizingMaskIntoConstraints = false
                vibrancyView.material = .hudWindow
                vibrancyView.blendingMode = .withinWindow
                vibrancyView.state = .active
                vibrancyView.wantsLayer = true
                vibrancyView.layer?.cornerRadius = theme.toolbarButtonsCornerRadius
                vibrancyView.layer?.masksToBounds = true

                duckAIChromeControlContainer.addSubview(vibrancyView, positioned: .below, relativeTo: duckAIChromeControlContainer.subviews.first)

                NSLayoutConstraint.activate([
                    vibrancyView.leadingAnchor.constraint(equalTo: duckAIChromeControlContainer.leadingAnchor),
                    vibrancyView.trailingAnchor.constraint(equalTo: duckAIChromeControlContainer.trailingAnchor),
                    vibrancyView.topAnchor.constraint(equalTo: duckAIChromeControlContainer.topAnchor),
                    vibrancyView.bottomAnchor.constraint(equalTo: duckAIChromeControlContainer.bottomAnchor)
                ])
                duckAIChromeBlurView = vibrancyView
            }

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
            shadow.shadowOffset = CGSize(width: 0, height: -0.5)
            shadow.shadowBlurRadius = 1.5
            duckAIChromeControlContainer.shadow = shadow
            duckAIChromeControlContainer.wantsLayer = true
            duckAIChromeControlContainer.layer?.masksToBounds = false
        } else {
            duckAIChromeBlurView?.removeFromSuperview()
            duckAIChromeBlurView = nil
            duckAIChromeControlContainer.shadow = nil
        }
    }

    private func removeDuckAIChromeSegmentedControl() {
        duckAIChromeBlurView?.removeFromSuperview()
        duckAIChromeBlurView = nil

        guard let duckAIChromeControlContainer else { return }
        rightSideStackView.removeArrangedSubview(duckAIChromeControlContainer)
        duckAIChromeControlContainer.removeFromSuperview()
        disableDuckAIChromeContextMenuOnTabBar()
        self.duckAIChromeControlContainer = nil
        self.duckAIChromeTitleButton = nil
        self.duckAIChromeSidebarButton = nil
        self.duckAIChromeDivider = nil
        self.aiChatButtonHoverCancellable = nil
        self.duckAIChromeDividerInsetConstraint = nil
        self.duckAIChromeDividerFullConstraint = nil
    }

    private func enableDuckAIChromeContextMenuOnTabBar() {
        view.menu = duckAIChromeContextMenu
        visualEffectBackgroundView.menu = duckAIChromeContextMenu
        backgroundColorView.menu = duckAIChromeContextMenu
        scrollView.menu = duckAIChromeContextMenu
        collectionView.menu = duckAIChromeContextMenu
        pinnedTabsContainerView.menu = duckAIChromeContextMenu
        pinnedTabsCollectionView?.menu = duckAIChromeContextMenu
        rightSideStackView.menu = duckAIChromeContextMenu
    }

    private func disableDuckAIChromeContextMenuOnTabBar() {
        view.menu = nil
        visualEffectBackgroundView.menu = nil
        backgroundColorView.menu = nil
        scrollView.menu = nil
        collectionView.menu = nil
        pinnedTabsContainerView.menu = nil
        pinnedTabsCollectionView?.menu = nil
        rightSideStackView.menu = nil
    }

    private func subscribeToChromeSidebarFeatureFlag() {
        aiChatChromeSidebarFeatureFlagCancellable = featureFlagger.updatesPublisher
            .map { [weak self] in
                self?.isChromeSidebarFeatureEnabled ?? false
            }
            .prepend(isChromeSidebarFeatureEnabled)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyChromeSidebarFeatureFlagState(isEnabled: isEnabled)
            }
    }

    private func applyChromeSidebarFeatureFlagState(isEnabled: Bool) {
        if isEnabled {
            setupDuckAIChromeSegmentedControl()
            enableChromeSidebarObservers()
            subscribeToAIChatSidebarChanges()
            subscribeToAIChatMenuConfigChanges()
            updateDuckAIChromeSegmentedControlState()
            return
        }

        disableChromeSidebarObservers()
        aiChatSidebarPresenceCancellable = nil
        aiChatFloatingStateCancellable = nil
        aiChatMenuConfigCancellable = nil
        removeDuckAIChromeSegmentedControl()
    }

    private func subscribeToAIChatSidebarChanges() {
        aiChatSidebarPresenceCancellable = aiChatCoordinator?.sidebarPresenceDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDuckAIChromeSegmentedControlState()
            }
        aiChatFloatingStateCancellable = aiChatCoordinator?.chatFloatingStateDidChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDuckAIChromeSegmentedControlState()
            }
    }

    private func subscribeToAIChatMenuConfigChanges() {
        aiChatMenuConfigCancellable = aiChatMenuConfig.valuesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshDuckAIChromeButtonsVisibility()
            }
    }

    private func enableChromeSidebarObservers() {
        guard selectedTabViewModelCancellable == nil else { return }
        subscribeToSelectedTabViewModel()
    }

    private func disableChromeSidebarObservers() {
        selectedTabViewModelCancellable = nil
        tabContentCancellable = nil
    }

    private func canToggleDuckAISidebar(for tab: Tab) -> Bool {
        if isChromeSidebarFeatureEnabled {
            return true
        }

        let tabID = tab.uuid
        let isSidebarOpen = aiChatCoordinator?.isSidebarOpen(for: tabID) ?? false
        let isChatFloating = aiChatCoordinator?.isChatFloating(for: tabID) ?? false

        var canToggleSidebar = false
        if isSidebarOpen || isChatFloating {
            canToggleSidebar = true
        } else if aiChatMenuConfig.shouldOpenAIChatInSidebar, case .url = tab.content {
            canToggleSidebar = true
        }

        return canToggleSidebar
    }

    private func duckAISidebarIcon(for mode: AIChatPresentationMode) -> NSImage? {
        switch mode {
        case .floating: return NSImage(named: Constants.duckAISidebarDetachedImageName)
        case .sidebar:  return NSImage(named: Constants.duckAISidebarCloseImageName)
        case .hidden:   return NSImage(named: Constants.duckAISidebarOpenImageName)
        }
    }

    private var isDuckAIChromeButtonsEnabled: Bool {
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab else { return false }
        return tab.content != .onboarding
    }

    private func updateDuckAIChromeSegmentedControlState() {
        guard let duckAIChromeTitleButton, let duckAIChromeSidebarButton else { return }
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab,
              isDuckAIChromeButtonsEnabled else {
            currentAIChatPresentationMode = .hidden
            duckAIChromeTitleButton.isEnabled = false
            duckAIChromeSidebarButton.isEnabled = false
            duckAIChromeSidebarButton.state = .off
            duckAIChromeSidebarButton.image = duckAISidebarIcon(for: .hidden)
            duckAIChromeSidebarButton.backgroundColor = .clear
            duckAIChromeSidebarButton.toolTip = UserText.aiChatOpenSidebarButton
            duckAIChromeSidebarButton.setAccessibilityTitle(UserText.aiChatOpenSidebarButton)
            updateDuckAIChromeDividerState()
            return
        }

        let presentationMode: AIChatPresentationMode
        if aiChatCoordinator?.isChatFloating(for: tab.uuid) == true {
            presentationMode = .floating
        } else if aiChatCoordinator?.isSidebarOpen(for: tab.uuid) == true {
            presentationMode = .sidebar
        } else {
            presentationMode = .hidden
        }
        currentAIChatPresentationMode = presentationMode

        let canToggleSidebar = canToggleDuckAISidebar(for: tab)
        let tooltip: String
        switch presentationMode {
        case .floating: tooltip = UserText.aiChatShowButton
        case .sidebar:  tooltip = UserText.aiChatCloseSidebarButton
        case .hidden:   tooltip = UserText.aiChatOpenSidebarButton
        }
        duckAIChromeTitleButton.isEnabled = true
        duckAIChromeSidebarButton.image = duckAISidebarIcon(for: presentationMode)
        duckAIChromeSidebarButton.backgroundColor = presentationMode != .hidden ? theme.colorsProvider.buttonMouseDownColor : .clear
        duckAIChromeSidebarButton.isEnabled = canToggleSidebar
        duckAIChromeSidebarButton.toolTip = tooltip
        duckAIChromeSidebarButton.setAccessibilityTitle(tooltip)
        duckAIChromeSidebarButton.state = presentationMode != .hidden ? .on : .off
        updateDuckAIChromeDividerState()
    }

    @objc private func duckAITitlebarButtonAction(_ sender: NSButton) {
        if let mainViewController = parent as? MainViewController {
            PixelKit.fire(AIChatPixel.aiChatTabbarButtonClicked, frequency: .dailyAndStandard)
            mainViewController.openNewDuckAIChatTab()
            return
        }

        Logger.general.error("TabBarViewController: Failed to find MainViewController to open Duck.ai")
    }

    @objc private func duckAIChromeSidebarButtonAction(_ sender: NSButton) {
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab else {
            return
        }

        let tabID = tab.uuid
        let isChatFloating = aiChatCoordinator?.isChatFloating(for: tabID) ?? false
        let canToggleSidebar = canToggleDuckAISidebar(for: tab)

        if isChatFloating {
            aiChatCoordinator?.focusFloatingWindow(for: tabID)
        } else if canToggleSidebar {
            let isSidebarOpen = aiChatCoordinator?.isSidebarOpen(for: tabID) ?? false
            if isSidebarOpen {
                PixelKit.fire(AIChatPixel.aiChatSidebarClosed(source: .tabbarButton), frequency: .dailyAndStandard)
            } else {
                PixelKit.fire(
                    AIChatPixel.aiChatSidebarOpened(
                        source: .tabbarButton,
                        shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                        minutesSinceSidebarHidden: aiChatCoordinator?.sidebarHiddenAt(for: tabID)?.minutesSinceNow()
                    ),
                    frequency: .dailyAndStandard
                )
            }
            aiChatCoordinator?.toggleSidebar()
        } else {
            updateDuckAIChromeSegmentedControlState()
            return
        }

        updateDuckAIChromeSegmentedControlState()
    }

    @objc private func hideDuckAITitleButtonAction() {
        duckAIChromeButtonsVisibilityManager.setHidden(true, for: .duckAI)
    }

    @objc private func showDuckAITitleButtonAction() {
        duckAIChromeButtonsVisibilityManager.setHidden(false, for: .duckAI)
    }

    @objc private func hideDuckAISidebarButtonAction() {
        duckAIChromeButtonsVisibilityManager.setHidden(true, for: .sidebar)
    }

    @objc private func showDuckAISidebarButtonAction() {
        duckAIChromeButtonsVisibilityManager.setHidden(false, for: .sidebar)
    }

    @objc private func openAISettingsAction() {
        NSApp.delegateTyped.windowControllersManager.showPreferencesTab(withSelectedPane: .aiChat)
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

    private func addFireWindowBackgroundViewIfNeeded() {
        guard !tabCollectionViewModel.isPopup else { return }

        if fireWindowBackgroundView == nil {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleAxesIndependently
            imageView.imageAlignment = .alignBottom
            imageView.isHidden = true
            fireWindowBackgroundView = imageView
        }

        guard let fireWindowBackgroundView, fireWindowBackgroundView.superview == nil else { return }

        view.addSubview(fireWindowBackgroundView, positioned: .above, relativeTo: visualEffectBackgroundView)

        NSLayoutConstraint.activate([
            fireWindowBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            fireWindowBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            fireWindowBackgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fireWindowBackgroundView.widthAnchor.constraint(equalToConstant: 96)
        ])
    }

    private func setupAsBurnerWindowIfNeeded(theme: (any ThemeStyleProviding)? = nil) {
        guard tabCollectionViewModel.isBurner,
              !tabCollectionViewModel.isPopup else { return }

        fireButton.isAnimationEnabled = false
        fireButton.backgroundColor = NSColor.fireButtonRedBackground
        fireButton.mouseOverColor = NSColor.fireButtonRedHover
        fireButton.mouseDownColor = NSColor.fireButtonRedPressed
        fireButton.normalTintColor = NSColor.white
        fireButton.mouseDownTintColor = NSColor.white
        fireButton.mouseOverTintColor = NSColor.white

        addFireWindowBackgroundViewIfNeeded()

        let currentTheme = theme ?? self.theme
        guard let fireWindowBackgroundView else { return }
        fireWindowBackgroundView.image = currentTheme.fireWindowGraphic
        fireWindowBackgroundView.isHidden = false
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
        pinnedTabsCollectionView?.setAccessibilitySubrole(nil)
        pinnedTabsCollectionView?.setAccessibilityTitle("Pinned Tabs")

        addTabButton.cell?.setAccessibilityParent(collectionView)

        leftScrollButton.setAccessibilityIdentifier("TabBarViewController.leftScrollButton")
        leftScrollButton.setAccessibilityTitle("Scroll left")

        rightScrollButton.setAccessibilityIdentifier("TabBarViewController.rightScrollButton")
        rightScrollButton.setAccessibilityTitle("Scroll right")
    }

    // MARK: - Pinned Tabs

    private func setupPinnedTabsView() {
        layoutPinnedTabsCollectionView()
        subscribeToPinnedTabsCollection()

        pinnedTabsWindowDraggingView.isHidden = true

        pinnedTabsCollectionView?.dataSource = self
        pinnedTabsCollectionView?.delegate = self
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

    // MARK: - Actions

    @objc func addButtonAction(_ sender: NSButton) {
        autoconsentStatsPopoverCoordinator?.dismissDialogDueToNewTabBeingShown()
        tabCollectionViewModel.insertOrAppendNewTab()
    }

    @IBAction func rightScrollButtonAction(_ sender: NSButton) {
        collectionView.scrollToEnd()
    }

    @IBAction func leftScrollButtonAction(_ sender: NSButton) {
        collectionView.scrollToBeginning()
    }

    private func reloadSelection() {
        let isPinnedTab = tabCollectionViewModel.selectionIndex?.isPinnedTab == true

        let collectionView: TabBarCollectionView? = isPinnedTab ? pinnedTabsCollectionView : self.collectionView

        bringSelectedTabCollectionToFront()

        guard let collectionView else {
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
        guard let pinnedTabsCollectionView else {
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

        if let indexPath = collectionView.indexPathForItemAtMouseLocation(locationInWindow) {
            tabCollectionViewModel.select(at: .unpinned(indexPath.item))
            return
        }

        if let indexPath = pinnedTabsCollectionView?.indexPathForItemAtMouseLocation(locationInWindow) {
            tabCollectionViewModel.select(at: .pinned(indexPath.item))
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
              tabDragAndDropManager.sourceUnit?.tabCollectionViewModel === tabCollectionViewModel,
              tabCollection.tabs.indices.contains(newIndex.item),
              let oldIndex = tabDragAndDropManager.sourceUnit?.index,
              oldIndex != newIndex else { return }

        tabCollectionViewModel.moveTab(at: oldIndex, to: newIndex)
        tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: newIndex)
    }

    private func moveToNewWindow(unpinnedIndex: Int, droppingPoint: NSPoint? = nil, burner: Bool) {
        let sourceTab: TabIndex = .unpinned(unpinnedIndex)
        guard tabCollectionViewModel.canMoveTabToNewWindow(tabIndex: sourceTab) else {
            return
        }

        guard let tabViewModel = tabCollectionViewModel.tabViewModel(at: unpinnedIndex) else {
            assertionFailure("TabBarViewController: Failed to get tab view model")
            return
        }

        let tab = tabViewModel.tab
        tabCollectionViewModel.remove(at: sourceTab, published: false)
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
        guard !tabPreviewWindowController.isPresented else {
            return
        }

        let locationInWindow = event.locationInWindow
        guard let tabBarViewItem = collectionView.tabBarItemAtMouseLocation(locationInWindow) ?? pinnedTabsCollectionView?.tabBarItemAtMouseLocation(locationInWindow) else {
            return
        }

        showTabPreview(for: tabBarViewItem)
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
        let isLeftScrollButtonVisible = !leftScrollButton.isHidden

        if shouldShowSShapedTabs && !isLeftScrollButtonVisible {
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
        setupAsBurnerWindowIfNeeded(theme: theme)

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
        updateDuckAIChromeSegmentedControlAppearance()
    }
}

// MARK: - TabCollectionViewModelDelegate
extension TabBarViewController: TabCollectionViewModelDelegate {

    func tabCollectionViewModelDidAppend(_ tabCollectionViewModel: TabCollectionViewModel, selected: Bool) {
        appendToCollectionView(selected: selected)
    }

    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didReplaceTabAt index: TabIndex) {
        let collectionView = index.isPinnedTab ? pinnedTabsCollectionView : self.collectionView
        guard let collectionView else {
            Logger.general.error("collection view is nil")
            return
        }
        let indexPathSet = Set(arrayLiteral: IndexPath(item: index.item))
        collectionView.reloadItems(at: indexPathSet)
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
            return NSEdgeInsets(top: 0, left: isLeftScrollButonVisible ? 10 : 12, bottom: 0, right: isRightScrollButtonVisible ? 10 : -12)
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

        tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: tabIndex)
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
        let locationInView = collectionView.convert(draggingInfo.draggingLocation, from: nil)

        guard collectionView.frame.contains(locationInView) else {
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
        tabDragAndDropManager.setDestination(tabCollectionViewModel: tabCollectionViewModel, index: tabIndex)

        return true
    }

    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) {
        // dropping a tab, dropping of url handled in collectionView:acceptDrop:
        guard session.draggingPasteboard.types == [TabBarViewItemPasteboardWriter.utiInternalType] else { return }

        // Don't allow drag and drop from Burner Window
        guard !tabCollectionViewModel.burnerMode.isBurner else { return }

        defer {
            tabDragAndDropManager.clear()
        }

        if case .private = operation {
            // Perform the drag and drop between multiple windows
            tabDragAndDropManager.performDragAndDropIfNeeded()
            DispatchQueue.main.async {
                self.collectionView.scrollToSelected()
            }
            return
        }
        // dropping not on a tab bar
        guard case .none = operation else { return }

        // Create a new window if dragged upward or too distant
        let frameRelativeToWindow = view.convert(view.bounds, to: nil)
        guard tabDragAndDropManager.sourceUnit?.tabCollectionViewModel === tabCollectionViewModel,
              let sourceIndex = tabDragAndDropManager.sourceUnit?.index,
              let frameRelativeToScreen = view.window?.convertToScreen(frameRelativeToWindow) else {
            return
        }

        // Check if the drop point is above the tab bar by more than 10 points
        let isDroppedAboveTabBar = screenPoint.y > (frameRelativeToScreen.maxY + 10)

        // Create new window if dropped above tab bar or too far away
        // But not for pinned tabs
        if collectionView != pinnedTabsCollectionView && (isDroppedAboveTabBar || !screenPoint.isNearRect(frameRelativeToScreen, allowedDistance: Self.dropToOpenDistance)) {
            moveToNewWindow(unpinnedIndex: sourceIndex.item,
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
                autoDismissDuration: nil,
                maxWidth: TabCrashIndicatorModel.Const.popoverWidth,
                presentMultiline: true,
                clickAction: {
                    tabBarViewItem.hideCrashIndicatorButton()
                },
                onDismiss: {
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
            let sourceCollectionView = tabBarViewItem.isPinned ? pinnedTabsCollectionView : collectionView
            if sourceCollectionView?.visibleRect.intersects(tabBarViewItem.view.frame) == true {
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

    func tabBarViewItemNewToTheRightAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        insertNewTab(nextTo: tabIndex)
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

    func cell(forPinnedTabAt index: Int) -> NSView? {
        guard let pinnedTabsCollectionView,
              let item = pinnedTabsCollectionView.item(at: IndexPath(item: index, section: 0)) as? TabBarViewItem else {
            return nil
        }
        return item.view
    }

    func cell(forTabAt index: Int) -> NSView? {
        guard let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? TabBarViewItem else {
            return nil
        }
        return item.view
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

            guard let view = self.pinnedTabsCollectionView else { return }
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
        if tryPresentWarnBeforeCloseForFloatingAIChatIfNeeded(for: tabIndex) {
            return
        }

        if let tabID = tabCollectionViewModel.tabViewModel(at: tabIndex)?.tab.uuid {
            aiChatCoordinator?.closeFloatingWindow(for: tabID)
        }
        tabCollectionViewModel.remove(at: tabIndex)
    }

    private func shouldWarnBeforeClosingFloatingAIChat(tabID: String) -> Bool {
        aiChatCoordinator?.isChatFloating(for: tabID) == true
    }

    @discardableResult
    func tryPresentWarnBeforeCloseForFloatingAIChatIfNeeded(for tabIndex: TabIndex) -> Bool {
        guard let tabID = tabCollectionViewModel.tabViewModel(at: tabIndex)?.tab.uuid,
              shouldWarnBeforeClosingFloatingAIChat(tabID: tabID),
              let tabBarViewItem = tabBarViewItem(for: tabIndex) else {
            return false
        }

        dismissAIChatCloseWarningPresenter()

        let presenter = WarnBeforeQuitOverlayPresenter(
            action: .closeTabWithFloatingAIChat,
            buttonHandlers: [.closeTab: { [weak self] in
                self?.dismissAIChatCloseWarningPresenter()
                self?.closeTab(for: tabID)
            },
            .dismiss: { [weak self] in
                self?.dismissAIChatCloseWarningPresenter()
            }],
            anchorViewProvider: {
                tabBarViewItem.view
            }
        )

        let manager = WarnBeforeQuitManager(
            action: .closeTabWithFloatingAIChat,
            isWarningEnabled: { true }
        )

        aiChatCloseWarningPresenter = presenter
        presenter.bindForManualPresentation(to: manager) { }
        return true
    }

    private func dismissAIChatCloseWarningPresenter() {
        aiChatCloseWarningPresenter?.dismiss()
        aiChatCloseWarningPresenter = nil
    }

    private func tabBarViewItem(for tabIndex: TabIndex) -> TabBarViewItem? {
        switch tabIndex {
        case .pinned(let index):
            return pinnedTabsCollectionView?.item(at: IndexPath(item: index, section: 0)) as? TabBarViewItem
        case .unpinned(let index):
            return collectionView.item(at: IndexPath(item: index, section: 0)) as? TabBarViewItem
        }
    }

    private func closeTab(for tabID: String) {
        aiChatCoordinator?.closeFloatingWindow(for: tabID)
        guard let tabIndex = tabCollectionViewModel.indexInAllTabs(where: { $0.uuid == tabID }) else { return }
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

        moveToNewWindow(unpinnedIndex: indexPath.item, burner: false)
    }

    func tabBarViewItemMoveToNewBurnerWindowAction(_ tabBarViewItem: TabBarViewItem) {
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        moveToNewWindow(unpinnedIndex: indexPath.item, burner: true)
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

    func tabBarViewItemSuspendAction(_ tabBarViewItem: TabBarViewItem) {
        guard featureFlagger.isFeatureOn(.tabSuspension), featureFlagger.isFeatureOn(.tabSuspensionDebugging) else { return }

        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : self.collectionView

        guard let indexPath = collectionView?.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        let tabIndex: TabIndex = isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
        if tabBarViewItem.tabViewModel?.isSuspended == true {
            tabCollectionViewModel.resumeTab(at: tabIndex)
        } else {
            tabCollectionViewModel.suspendTab(at: tabIndex)
        }
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

private extension TabBarViewController {

    func insertNewTab(nextTo tabIndex: TabIndex) {
        /// `New Tab Next to Pinned`:  We'll create a new Tab at the location `0`
        let targetIndex: TabIndex = tabIndex.isPinnedTab
            ? .unpinned(.zero)
            : tabIndex.makeNext()

        let tab = Tab(content: .newtab, burnerMode: tabCollectionViewModel.burnerMode)
        tabCollectionViewModel.insert(tab, at: targetIndex, selected: true)
    }

    func tabIndex(forTabBarViewItem item: TabBarViewItem) -> TabIndex? {
        let isPinned = item.tabViewModel?.isPinned == true
        let collectionView = isPinned ? pinnedTabsCollectionView : collectionView
        guard let indexPath = collectionView?.indexPath(for: item) else {
            return nil
        }

        return isPinned ? .pinned(indexPath.item) : .unpinned(indexPath.item)
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

// MARK: - Duck.ai Chrome Context Menu

extension TabBarViewController: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === duckAIChromeContextMenu else { return }
        menu.removeAllItems()

        guard isChromeSidebarFeatureEnabled, aiChatMenuConfig.shouldDisplayAnyAIChatFeature else {
            return
        }

        let duckAIHidden = duckAIChromeButtonsVisibilityManager.isHidden(.duckAI)
        let sidebarHidden = duckAIChromeButtonsVisibilityManager.isHidden(.sidebar)

        let duckAIItem = NSMenuItem(
            title: duckAIHidden ? UserText.aiChatChromeShowDuckAIButton : UserText.aiChatChromeHideDuckAIButton,
            action: duckAIHidden ? #selector(showDuckAITitleButtonAction) : #selector(hideDuckAITitleButtonAction),
            keyEquivalent: "Y"
        )
        duckAIItem.target = self
        menu.addItem(duckAIItem)

        let sidebarItem = NSMenuItem(
            title: sidebarHidden ? UserText.aiChatChromeShowSidebarButton : UserText.aiChatChromeHideSidebarButton,
            action: sidebarHidden ? #selector(showDuckAISidebarButtonAction) : #selector(hideDuckAISidebarButtonAction),
            keyEquivalent: "U"
        )
        sidebarItem.target = self
        menu.addItem(sidebarItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: UserText.aiChatChromeOpenAISettings,
            action: #selector(openAISettingsAction),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
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
