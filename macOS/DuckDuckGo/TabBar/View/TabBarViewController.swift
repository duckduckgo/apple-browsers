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

import AIChat
import Cocoa
import Combine
import Common
import DesignResourcesKitIcons
import FoundationExtensions
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

    /// Represents an item in the tab bar - either a regular tab or a group header
    enum TabBarDisplayItem {
        case tab(AnyTab)
        case groupHeader(TabGroup)

        var tab: AnyTab? {
            if case .tab(let tab) = self { return tab }
            return nil
        }

        var groupHeader: TabGroup? {
            if case .groupHeader(let group) = self { return group }
            return nil
        }
    }

    private let standardTabHeight: CGFloat
    private let pinnedTabHeight: CGFloat
    private let pinnedTabWidth: CGFloat

    private(set) var visualEffectBackgroundView: NSVisualEffectView!
    private(set) var backgroundColorView: ColorView!
    private(set) var pinnedTabsContainerView: NSView!
    private var collectionView: TabBarCollectionView!
    private var scrollView: TabBarScrollView!
    private(set) var pinnedTabsViewLeadingConstraint: NSLayoutConstraint!
    private(set) var pinnedTabsWindowDraggingView: WindowDraggingView!
    private(set) var rightScrollButton: MouseOverButton!
    private(set) var leftScrollButton: MouseOverButton!
    private(set) var rightShadowImageView: NSImageView!
    private(set) var leftShadowImageView: NSImageView!
    private(set) var fireButton: MouseOverAnimationButton!
    private(set) var draggingSpace: NSView!
    private(set) var windowDraggingViewLeadingConstraint: NSLayoutConstraint!

    private var pinnedTabsCollectionView: PinnedTabsCollectionView?

    private(set) var fireButtonWidthConstraint: NSLayoutConstraint!
    private(set) var fireButtonHeightConstraint: NSLayoutConstraint!
    private(set) var addTabButton: MouseOverButton!
    private(set) var addTabButtonWidth: NSLayoutConstraint!
    private(set) var addTabButtonHeight: NSLayoutConstraint!
    private(set) var rightScrollButtonWidth: NSLayoutConstraint!
    private(set) var rightScrollButtonHeight: NSLayoutConstraint!
    private(set) var leftScrollButtonWidth: NSLayoutConstraint!
    private(set) var leftScrollButtonHeight: NSLayoutConstraint!
    private(set) var scrollViewHeightConstraint: NSLayoutConstraint!
    private(set) var pinnedTabsContainerHeightConstraint: NSLayoutConstraint!

    private var pinnedTabsCollectionCancellable: AnyCancellable?
    private var fireButtonMouseOverCancellable: AnyCancellable?
    private var aiChatChromeSidebarFeatureFlagCancellable: AnyCancellable?
    private var tabOrganizerButton: MouseOverButton?
    private var tabOrganizerFeatureFlagCancellable: AnyCancellable?
    private var duckAIChromeLayoutCancellable: AnyCancellable?
    private var aiChatSidebarPresenceCancellable: AnyCancellable?
    private var aiChatFloatingStateCancellable: AnyCancellable?
    private var aiChatMenuConfigCancellable: AnyCancellable?
    private var aiChatButtonHoverCancellable: AnyCancellable?
    private var duckAIChromeButtonsVisibilityCancellable: AnyCancellable?
    private var isChatsMenuItemEnabled = true
    private var didPerformInitialChromeSidebarApply = false
    private var duckAIChromeDividerInsetConstraint: NSLayoutConstraint?
    private var duckAIChromeDividerFullConstraint: NSLayoutConstraint?
    private var currentAIChatPresentationMode: AIChatPresentationMode = .hidden
    private var selectedTabViewModelCancellable: AnyCancellable?
    private var tabContentCancellable: AnyCancellable?
    private let duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging
    private let duckAIMenuButtonPixelFirer = AIChatMenuButtonPixelFirer()
    /// The sidebar entry the menu last offered. The item's action reads it rather than the tab's state,
    /// so it does what the item said and what the menu-shown pixel reported.
    private var duckAIMenuSidebarEntry: AIChatMenuButtonSidebarEntry?
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
    private let nativeStorageHandler: DuckAiNativeStorageHandling?
    private let pinnedTabsManagerProvider: PinnedTabsManagerProviding = Application.appDelegate.pinnedTabsManagerProvider
    private var pinnedTabsDiscoveryPopover: NSPopover?
    private weak var crashPopoverViewController: PopoverMessageViewController?
    private let cookiePopupsBlockedPromoDelegate: CookiePopupsBlockedPromoDelegate? // swiftlint:disable:this weak_delegate

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

    private var selectionNeedsLayoutInvalidation = false

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

    // MARK: - Tab Group Display Items

    /// Builds the list of display items for the unpinned tabs collection view.
    /// Inserts group headers before each group's first tab and hides tabs in collapsed groups.
    private var displayItems: [TabBarDisplayItem] {
        let tabGroupManager = tabCollectionViewModel.tabGroupManager
        let tabs = tabCollectionViewModel.tabCollection.tabs

        var items: [TabBarDisplayItem] = []
        var seenGroups: Set<UUID> = []

        for tab in tabs {
            if let groupID = tabGroupManager.groupID(for: tab),
               let group = tabGroupManager.groups.first(where: { $0.id == groupID }) {
                // Tab is in a group
                if !seenGroups.contains(groupID) {
                    // First tab of this group - insert header
                    seenGroups.insert(groupID)
                    items.append(.groupHeader(group))
                }

                // Only show tab if group is not collapsed
                if !tabGroupManager.isCollapsed(groupID: groupID) {
                    items.append(.tab(tab))
                }
            } else {
                // Ungrouped tab - always show
                items.append(.tab(tab))
            }
        }

        return items
    }

    // TabBarRemoteMessagePresentable
    var tabBarRemoteMessageViewModel: TabBarRemoteMessageViewModel
    var tabBarRemoteMessagePopover: NSPopover?
    var tabBarRemoteMessagePopoverHoverTimer: Timer?
    var feedbackBarButtonHostingController: NSHostingController<TabBarRemoteMessageView>?
    var tabBarRemoteMessageCancellable: AnyCancellable?
    var foregroundBrowserWindowObserver: ForegroundBrowserWindowObserver?
    var foregroundBrowserWindowCancellable: AnyCancellable?
    lazy var tabBarRemoteMessageImpressionTracker = TabBarRemoteMessageImpressionTracker { [weak self] messageID in
        guard let self else { return }
        self.tabBarRemoteMessageViewModel.refreshRemoteMessageForPresentation()
        self.reconcileTabBarRemoteMessageImpression()
        guard self.feedbackBarButtonHostingController?.rootView.model.id == messageID,
              self.isTabBarRemoteMessageEligibleForImpression else { return }
        self.tabBarRemoteMessageViewModel.markTabBarRemoteMessageAsShown(withID: messageID)
    }

    private(set) var shadowView: TabShadowView!

    private(set) var leftSideStackLeadingConstraint: NSLayoutConstraint!
    private(set) var rightSideStackView: NSStackView!
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

    /// Single "Ask Duck.ai" menu pill instead of the two-part split button. Layered on the sidebar flag.
    var isMenuButtonLayout: Bool {
        isChromeSidebarFeatureEnabled && featureFlagger.isFeatureOn(.aiChatChromeMenuButton)
    }

    /// Whether the current tab is a real web page whose content can be attached to Duck.ai. When false
    /// (e.g. the new-tab page) the "Ask About Page" affordance becomes a plain "Open Sidebar".
    var isCurrentPageAttachableForAIChat: Bool {
        tabCollectionViewModel.selectedTabViewModel?.tab.content.urlForWebView?.isHttpOrHttps == true
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
        nativeStorageHandler: DuckAiNativeStorageHandling? = NSApp.delegateTyped.duckAiNativeStorageHandler,
        duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging = LocalDuckAIChromeButtonsVisibilityManager(),
        tabDragAndDropManager: TabDragAndDropManager,
        cookiePopupsBlockedPromoDelegate: CookiePopupsBlockedPromoDelegate? = nil
    ) -> TabBarViewController {
        self.init(
                tabCollectionViewModel: tabCollectionViewModel,
                bookmarkManager: bookmarkManager,
                fireproofDomains: fireproofDomains,
                activeRemoteMessageModel: activeRemoteMessageModel,
                featureFlagger: featureFlagger,
                aiChatMenuConfig: aiChatMenuConfig,
                nativeStorageHandler: nativeStorageHandler,
                duckAIChromeButtonsVisibilityManager: duckAIChromeButtonsVisibilityManager,
                tabDragAndDropManager: tabDragAndDropManager,
                cookiePopupsBlockedPromoDelegate: cookiePopupsBlockedPromoDelegate
            )
    }

    required init?(coder: NSCoder) {
        fatalError("TabBarViewController: Bad initializer")
    }

    // MARK: - View construction

    private enum LayoutConstants {
        static let contentSize = CGSize(width: 845, height: 38)
        static let barHeight: CGFloat = 38
        static let scrollViewHeight: CGFloat = 36
        static let scrollViewSize = CGSize(width: 683, height: 36)
        static let pinnedTabsHeight: CGFloat = 32
        static let pinnedTabsLeading: CGFloat = 76
        static let buttonSide: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 4
        static let draggingSpaceSize = CGSize(width: 40, height: 28)
        static let shadowImageWidth: CGFloat = 5
        static let rightSideStackTrailing: CGFloat = 12
        static let rightSideStackSpacing: CGFloat = 2
        static let itemSize = NSSize(width: 120, height: 32)
    }

    /// Square, image-only button with no bezel: `MouseOverButton` draws the hover and pressed fills itself.
    private func configureBarButton(_ button: MouseOverButton,
                                    image: NSImage,
                                    target: AnyObject?,
                                    action: Selector?) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.alignment = .center
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor(resource: .button)
        button.normalTintColor = button.contentTintColor
        button.mouseOverColor = NSColor(resource: .buttonMouseOver)
        button.mouseDownColor = NSColor(resource: .buttonMouseDown)
        button.cornerRadius = LayoutConstants.buttonCornerRadius
        button.target = target
        button.action = action
    }

    private func makeShadowImageView(image: NSImage) -> NSImageView {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignLeft
        imageView.refusesFirstResponder = true
        imageView.image = image
        imageView.setContentHuggingPriority(.init(251), for: .horizontal)
        imageView.setContentHuggingPriority(.init(251), for: .vertical)
        return imageView
    }

    // swiftlint:disable:next function_body_length
    override func loadView() {
        let view = TabBarView(frame: NSRect(origin: .zero, size: LayoutConstants.contentSize))

        backgroundColorView = ColorView(frame: .zero, backgroundColor: NSColor(resource: .windowBackground))
        backgroundColorView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectBackgroundView = NSVisualEffectView()
        visualEffectBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectBackgroundView.blendingMode = .behindWindow
        visualEffectBackgroundView.material = .sidebar
        visualEffectBackgroundView.state = .active
        visualEffectBackgroundView.addSubview(backgroundColorView)

        // Full-width dragging view behind everything else.
        let backgroundWindowDraggingView = WindowDraggingView()
        backgroundWindowDraggingView.translatesAutoresizingMaskIntoConstraints = false

        shadowView = TabShadowView()
        shadowView.translatesAutoresizingMaskIntoConstraints = false

        leftScrollButton = MouseOverButton(frame: .zero)
        configureBarButton(leftScrollButton,
                           image: NSImage(resource: .tabOverflowBack),
                           target: self,
                           action: #selector(leftScrollButtonAction(_:)))
        leftScrollButton.isHidden = true
        leftScrollButtonWidth = leftScrollButton.widthAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)
        leftScrollButtonHeight = leftScrollButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)

        let leftSideStackView = NSStackView(views: [leftScrollButton])
        leftSideStackView.translatesAutoresizingMaskIntoConstraints = false
        leftSideStackView.orientation = .horizontal
        leftSideStackView.distribution = .fillEqually
        leftSideStackView.alignment = .top
        leftSideStackView.spacing = 0
        leftSideStackView.detachesHiddenViews = true

        pinnedTabsContainerView = NSView()
        pinnedTabsContainerView.translatesAutoresizingMaskIntoConstraints = false
        pinnedTabsContainerView.setContentHuggingPriority(.init(251), for: .horizontal)
        pinnedTabsContainerView.setContentCompressionResistancePriority(.init(749), for: .horizontal)
        pinnedTabsContainerHeightConstraint = pinnedTabsContainerView.heightAnchor
            .constraint(equalToConstant: LayoutConstants.pinnedTabsHeight)

        collectionView = TabBarCollectionView(frame: .zero)
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = false
        collectionView.autoresizingMask = [.height]
        collectionView.backgroundColors = [.clear]
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = LayoutConstants.itemSize
        flowLayout.sectionInset = NSEdgeInsets(top: 2, left: 0, bottom: 0, right: 0)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.minimumLineSpacing = 0
        collectionView.collectionViewLayout = flowLayout
        // Registration has to follow the layout assignment — see `registerItemsAndDraggedTypes()`.
        collectionView.registerItemsAndDraggedTypes()
        collectionView.dataSource = self
        collectionView.delegate = self

        scrollView = TabBarScrollView(frame: NSRect(x: 0, y: 0,
                                                    width: LayoutConstants.scrollViewSize.width,
                                                    height: LayoutConstants.scrollViewSize.height))
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Sized to the scroll view and resizing with it: starting at zero would leave the collection
        // view laid out against a collapsed container.
        let clipView = NSClipView(frame: scrollView.frame)
        clipView.translatesAutoresizingMaskIntoConstraints = true
        clipView.autoresizingMask = [.width, .height]
        clipView.drawsBackground = false
        clipView.documentView = collectionView
        scrollView.wantsLayer = true
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.contentView = clipView
        scrollViewHeightConstraint = scrollView.heightAnchor
            .constraint(equalToConstant: LayoutConstants.scrollViewHeight)

        rightScrollButton = MouseOverButton(frame: .zero)
        configureBarButton(rightScrollButton,
                           image: NSImage(resource: .tabOverflowForward),
                           target: self,
                           action: #selector(rightScrollButtonAction(_:)))
        rightScrollButton.isHidden = true
        rightScrollButtonWidth = rightScrollButton.widthAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)
        rightScrollButtonHeight = rightScrollButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)

        addTabButton = MouseOverButton(frame: .zero)
        configureBarButton(addTabButton, image: NSImage(resource: .add), target: nil, action: nil)
        // The Add glyph is already the right size; scaling it down blurs it.
        addTabButton.imageScaling = .scaleNone
        addTabButton.isHidden = true
        addTabButtonWidth = addTabButton.widthAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)
        addTabButtonHeight = addTabButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)

        draggingSpace = NSView()
        draggingSpace.translatesAutoresizingMaskIntoConstraints = false

        // Sent up the responder chain rather than to this controller, which does not handle it.
        fireButton = MouseOverAnimationButton(frame: .zero)
        configureBarButton(fireButton,
                           image: NSImage(resource: .burn),
                           target: nil,
                           action: #selector(MainViewController.fireButtonAction(_:)))
        fireButtonWidthConstraint = fireButton.widthAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)
        fireButtonHeightConstraint = fireButton.heightAnchor.constraint(equalToConstant: LayoutConstants.buttonSide)

        rightSideStackView = NSStackView(views: [rightScrollButton, addTabButton, draggingSpace, fireButton])
        rightSideStackView.translatesAutoresizingMaskIntoConstraints = false
        rightSideStackView.orientation = .horizontal
        rightSideStackView.distribution = .fillEqually
        rightSideStackView.alignment = .top
        rightSideStackView.spacing = LayoutConstants.rightSideStackSpacing
        rightSideStackView.detachesHiddenViews = true

        rightShadowImageView = makeShadowImageView(image: NSImage(resource: .tabBarShadowRight))
        leftShadowImageView = makeShadowImageView(image: NSImage(resource: .tabBarShadowLeft))

        pinnedTabsWindowDraggingView = WindowDraggingView()
        pinnedTabsWindowDraggingView.translatesAutoresizingMaskIntoConstraints = false

        // Sits in front of the tab strip so the gaps between tabs still drag the window.
        let scrollAreaWindowDraggingView = WindowDraggingView()
        scrollAreaWindowDraggingView.translatesAutoresizingMaskIntoConstraints = false

        // Order matters: the backgrounds go first, the dragging views last, so they receive clicks
        // on any area the tabs do not cover.
        view.addSubview(visualEffectBackgroundView)
        view.addSubview(backgroundWindowDraggingView)
        view.addSubview(shadowView)
        view.addSubview(leftSideStackView)
        view.addSubview(pinnedTabsContainerView)
        view.addSubview(scrollView)
        view.addSubview(rightSideStackView)
        view.addSubview(rightShadowImageView)
        view.addSubview(leftShadowImageView)
        view.addSubview(pinnedTabsWindowDraggingView)
        view.addSubview(scrollAreaWindowDraggingView)

        pinnedTabsViewLeadingConstraint = pinnedTabsContainerView.leadingAnchor
            .constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.pinnedTabsLeading)
        leftSideStackLeadingConstraint = leftSideStackView.leadingAnchor
            .constraint(equalTo: pinnedTabsContainerView.trailingAnchor)
        windowDraggingViewLeadingConstraint = scrollAreaWindowDraggingView.leadingAnchor
            .constraint(equalTo: scrollView.leadingAnchor)
        windowDraggingViewLeadingConstraint.priority = .init(250)

        let leftSideStackFallbackLeading = leftSideStackView.leadingAnchor
            .constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.pinnedTabsLeading)
        leftSideStackFallbackLeading.priority = .init(600)

        let draggingViewTrailing = scrollView.trailingAnchor
            .constraint(equalTo: scrollAreaWindowDraggingView.trailingAnchor, constant: -4)
        draggingViewTrailing.priority = .init(250)
        let draggingViewTop = scrollAreaWindowDraggingView.topAnchor.constraint(equalTo: view.topAnchor)
        draggingViewTop.priority = .init(750)
        let draggingViewBottom = view.bottomAnchor.constraint(equalTo: scrollAreaWindowDraggingView.bottomAnchor)
        draggingViewBottom.priority = .init(750)

        NSLayoutConstraint.activate([
            visualEffectBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: visualEffectBackgroundView.trailingAnchor),
            visualEffectBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: visualEffectBackgroundView.bottomAnchor),

            backgroundColorView.leadingAnchor.constraint(equalTo: visualEffectBackgroundView.leadingAnchor),
            visualEffectBackgroundView.trailingAnchor.constraint(equalTo: backgroundColorView.trailingAnchor),
            backgroundColorView.topAnchor.constraint(equalTo: visualEffectBackgroundView.topAnchor),
            visualEffectBackgroundView.bottomAnchor.constraint(equalTo: backgroundColorView.bottomAnchor),

            backgroundWindowDraggingView.heightAnchor.constraint(equalToConstant: LayoutConstants.barHeight),
            backgroundWindowDraggingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: backgroundWindowDraggingView.trailingAnchor),
            backgroundWindowDraggingView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: backgroundWindowDraggingView.bottomAnchor),

            shadowView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: shadowView.trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: shadowView.bottomAnchor),

            leftScrollButtonWidth,
            leftScrollButtonHeight,
            leftSideStackView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            leftSideStackLeadingConstraint,
            leftSideStackFallbackLeading,

            pinnedTabsContainerHeightConstraint,
            pinnedTabsViewLeadingConstraint,
            scrollView.bottomAnchor.constraint(equalTo: pinnedTabsContainerView.bottomAnchor),

            scrollViewHeightConstraint,
            scrollView.leadingAnchor.constraint(equalTo: leftSideStackView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            rightScrollButtonWidth,
            rightScrollButtonHeight,
            addTabButtonWidth,
            addTabButtonHeight,
            draggingSpace.widthAnchor.constraint(equalToConstant: LayoutConstants.draggingSpaceSize.width),
            draggingSpace.heightAnchor.constraint(equalToConstant: LayoutConstants.draggingSpaceSize.height),
            fireButtonWidthConstraint,
            fireButtonHeightConstraint,
            rightSideStackView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            view.trailingAnchor.constraint(equalTo: rightSideStackView.trailingAnchor,
                                           constant: LayoutConstants.rightSideStackTrailing),
            rightSideStackView.leadingAnchor.constraint(equalTo: scrollAreaWindowDraggingView.trailingAnchor),

            rightShadowImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.shadowImageWidth),
            rightShadowImageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            rightShadowImageView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: rightShadowImageView.bottomAnchor),

            leftShadowImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.shadowImageWidth),
            scrollView.leadingAnchor.constraint(equalTo: leftShadowImageView.leadingAnchor),
            leftShadowImageView.topAnchor.constraint(equalTo: view.topAnchor),
            view.bottomAnchor.constraint(equalTo: leftShadowImageView.bottomAnchor),

            pinnedTabsWindowDraggingView.leadingAnchor.constraint(equalTo: pinnedTabsContainerView.leadingAnchor),
            pinnedTabsWindowDraggingView.trailingAnchor.constraint(equalTo: pinnedTabsContainerView.trailingAnchor),
            pinnedTabsWindowDraggingView.topAnchor.constraint(equalTo: pinnedTabsContainerView.topAnchor),
            pinnedTabsWindowDraggingView.bottomAnchor.constraint(equalTo: pinnedTabsContainerView.bottomAnchor),

            windowDraggingViewLeadingConstraint,
            draggingViewTrailing,
            draggingViewTop,
            draggingViewBottom,
        ])

        self.view = view
    }

    init(tabCollectionViewModel: TabCollectionViewModel,
         bookmarkManager: BookmarkManager,
         fireproofDomains: FireproofDomains,
         activeRemoteMessageModel: ActiveRemoteMessageModel,
         featureFlagger: FeatureFlagger,
         aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
         nativeStorageHandler: DuckAiNativeStorageHandling?,
         duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging,
         themeManager: ThemeManager = NSApp.delegateTyped.themeManager,
         tabDragAndDropManager: TabDragAndDropManager,
         cookiePopupsBlockedPromoDelegate: CookiePopupsBlockedPromoDelegate? = nil) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.fireproofDomains = fireproofDomains
        self.featureFlagger = featureFlagger
        self.aiChatMenuConfig = aiChatMenuConfig
        self.nativeStorageHandler = nativeStorageHandler
        self.duckAIChromeButtonsVisibilityManager = duckAIChromeButtonsVisibilityManager
        let tabBarActiveRemoteMessageModel = TabBarActiveRemoteMessage(activeRemoteMessageModel: activeRemoteMessageModel)
        self.tabBarRemoteMessageViewModel = TabBarRemoteMessageViewModel(
            activeRemoteMessageModel: tabBarActiveRemoteMessageModel,
            isFireWindow: tabCollectionViewModel.isBurner
        )
        self.themeManager = themeManager
        self.tabDragAndDropManager = tabDragAndDropManager
        self.cookiePopupsBlockedPromoDelegate = cookiePopupsBlockedPromoDelegate

        standardTabHeight = themeManager.theme.tabStyleProvider.standardTabHeight
        pinnedTabHeight = themeManager.theme.tabStyleProvider.pinnedTabHeight
        pinnedTabWidth = themeManager.theme.tabStyleProvider.pinnedTabWidth

        super.init(nibName: nil, bundle: nil)

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
        setupTabOrganizerButton()
        subscribeToChromeSidebarFeatureFlag()
        subscribeToDuckAIChromeLayoutChanges()
        subscribeToDuckAIChromeButtonsVisibilityChanges()
        subscribeToNativeChats()
        setupPinnedTabsView()
        subscribeToTabModeChanges()
        setupAddTabButton()
        setupAsBurnerWindowIfNeeded()
        subscribeToPinnedTabsSettingChanged()
        setupScrollButtons()
        setupScrollInsets()
        setupTabsContainersHeight()
        subscribeToThemeChanges()
        subscribeToTabGroupChanges()

        applyThemeStyle()
    }

    private func subscribeToTabGroupChanges() {
        let tabGroupManager = tabCollectionViewModel.tabGroupManager

        // One reload once group changes settle: applying a proposal changes many tabs and moves them,
        // and reloads in the middle of that, while the tab bar animates, can leave stale items behind.
        Publishers.Merge3(tabGroupManager.$tabToGroup.map { _ in () },
                          tabGroupManager.$collapsedGroups.map { _ in () },
                          tabGroupManager.$groups.map { _ in () })
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.reloadForTabGroupChange()
            }
            .store(in: &cancellables)
    }

#if DEBUG
    /// Hack days diagnostics: what the model says vs what the tab bar shows.
    private func logTabGroupState(_ reason: String) {
        let manager = tabCollectionViewModel.tabGroupManager
        let tabs = tabCollectionViewModel.tabCollection.tabs.enumerated().map { index, tab in
            "\(index):\((tab.title ?? "").prefix(12))[\(manager.group(for: tab)?.name ?? "-")]"
        }
        let expected = displayItems.enumerated().map { index, item -> String in
            switch item {
            case .groupHeader(let group): return "\(index):HEADER(\(group.name))"
            case .tab(let tab): return "\(index):\((tab.title ?? "").prefix(12))"
            }
        }
        let shown = collectionView.indexPathsForVisibleItems().sorted().map { indexPath -> String in
            guard let item = collectionView.item(at: indexPath) as? TabBarViewItem else { return "\(indexPath.item):?" }
            if let group = item.currentHeaderGroup { return "\(indexPath.item):HEADER(\(group.name))" }
            return "\(indexPath.item):\((item.tabViewModel?.title ?? "").prefix(12))"
        }
        print("TABGROUPS \(reason) items=\(collectionView.numberOfItems(inSection: 0)) expected=\(expected.count)")
        print("TABGROUPS tabs     \(tabs.joined(separator: " | "))")
        print("TABGROUPS expected \(expected.joined(separator: " | "))")
        print("TABGROUPS shown    \(shown.joined(separator: " | "))")
    }
#endif

    private func reloadForTabGroupChange() {
#if DEBUG
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.logTabGroupState("0.5s after group change")
            }
        }
#endif
        // Keeps every group's tabs together whichever way the groups changed.
        tabCollectionViewModel.arrangeTabsByGroup()
        reloadDataAndSelectWithoutAnimation()
        updateTabMode()
        enableScrollButtons()
        // A selection animation started elsewhere swallows reloads made while it runs; redo once it's over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.reloadDataAndSelectWithoutAnimation()
        }
    }

    private func reloadDataAndSelectWithoutAnimation() {
        reloadDataAndLayout()
        guard let selectionIndex = tabCollectionViewModel.selectionIndex, selectionIndex.isUnpinnedTab,
              let tab = tabCollectionViewModel.tabCollection.tabs[safe: selectionIndex.item],
              let displayIndex = displayItemIndex(for: tab) else { return }
        collectionView.selectItems(at: [IndexPath(item: displayIndex)], scrollPosition: [])
    }

    private func refreshTabGroupBackgrounds() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            if let item = collectionView.item(at: indexPath) as? TabBarViewItem {
                item.updateGroupBackground()
            }
        }
        for indexPath in pinnedTabsCollectionView?.indexPathsForVisibleItems() ?? [] {
            if let item = pinnedTabsCollectionView?.item(at: indexPath) as? TabBarViewItem {
                item.updateGroupBackground()
            }
        }
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
        guard let window = view.window else { return }

        let observer = ForegroundBrowserWindowObserver(window: window)
        foregroundBrowserWindowObserver = observer
        foregroundBrowserWindowCancellable = observer.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reconcileTabBarRemoteMessageImpression() }
        reconcileTabBarRemoteMessageImpression()

        enableScrollButtons()
        subscribeToChildWindows()
        setupAccessibility()

        performInitialChromeSidebarApplyIfNeeded()
    }

    private func performInitialChromeSidebarApplyIfNeeded() {
        guard !didPerformInitialChromeSidebarApply else { return }
        didPerformInitialChromeSidebarApply = true
        applyChromeSidebarFeatureFlagState(isEnabled: isChromeSidebarFeatureEnabled)
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
        foregroundBrowserWindowCancellable = nil
        foregroundBrowserWindowObserver = nil
        tabBarRemoteMessageImpressionTracker.update(isEligible: false, messageID: nil)
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
        fireButton.animationNames = MouseOverAnimationButton.AnimationNames(aqua: style.animationName,
                                                                            dark: style.animationName)
        fireButton.sendAction(on: .leftMouseDown)
        fireButtonMouseOverCancellable = fireButton.publisher(for: \.isMouseOver)
            .first(where: { $0 }) // only interested when mouse is over
            .sink(receiveValue: { [weak self] _ in
                self?.stopFireButtonPulseAnimation()
            })

        fireButtonWidthConstraint.constant = theme.tabBarButtonSize
        fireButtonHeightConstraint.constant = theme.tabBarButtonSize
    }

    private func setupTabOrganizerButton() {
        let button = MouseOverButton(frame: .zero)
        configureBarButton(button,
                           image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil) ?? NSImage(),
                           target: self,
                           action: #selector(tabOrganizerButtonAction(_:)))
        button.toolTip = "Organize tabs"
        button.setAccessibilityIdentifier("TabBarViewController.tabOrganizerButton")
        button.setCornerRadius(theme.toolbarButtonsCornerRadius)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: theme.tabBarButtonSize),
            button.heightAnchor.constraint(equalToConstant: theme.tabBarButtonSize)
        ])
        let fireButtonIndex = rightSideStackView.arrangedSubviews.firstIndex(of: fireButton) ?? rightSideStackView.arrangedSubviews.count
        rightSideStackView.insertArrangedSubview(button, at: fireButtonIndex)
        tabOrganizerButton = button

        tabOrganizerFeatureFlagCancellable = featureFlagger.updatesPublisher
            .prepend(())
            .map { [weak self] in self?.featureFlagger.isFeatureOn(.aiTabOrganizer) ?? false }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.tabOrganizerButton?.isHidden = !isEnabled || self?.isFireWindow == true
            }
    }

    @objc private func tabOrganizerButtonAction(_ sender: NSButton) {
        TabOrganizerPopover.show(relativeTo: sender, tabCollectionViewModel: tabCollectionViewModel)
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

        // Menu-button layout: a single "Ask Duck.ai" pill; the sidebar sub-button and divider never render.
        if isMenuButtonLayout {
            // Runs at most once, here rather than at launch because the layout can flip on a config
            // fetch. Reading the flag straight after picks up the migrated value, so there's no flicker.
            duckAIChromeButtonsVisibilityManager.migrateVisibilityForMenuButtonLayoutIfNeeded()
            let duckAIHidden = duckAIChromeButtonsVisibilityManager.isHidden(.duckAI)
            titleButton.isHidden = duckAIHidden
            sidebarButton.isHidden = true
            divider.isHidden = true
            container.isHidden = duckAIHidden
            titleButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            container.backgroundColor = isFireWindow ? .clear : theme.colorsProvider.buttonMouseOverColor
            updateDuckAIChromeVibrancyBackground()
            return
        }

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
        let cornerRadius = theme.toolbarButtonsCornerRadius
        duckAIChromeControlContainer.backgroundColor = isFireWindow ? .clear : colorsProvider.buttonMouseOverColor
        duckAIChromeControlContainer.cornerRadius = cornerRadius
        duckAIChromeControlContainer.borderColor = nil
        duckAIChromeControlContainer.borderWidth = 0

        updateDuckAIChromeVibrancyBackground()

        let titleFont = NSFont.systemFont(ofSize: 13)
        if isMenuButtonLayout {
            // "Ask Duck.ai" button with the AI-Chat glyph, tinted to match the title text; click opens the menu.
            let icon = DesignSystemImages.Glyphs.Size16.aiChat
            icon.isTemplate = true
            duckAIChromeTitleButton.image = icon
            duckAIChromeTitleButton.imagePosition = .imageLeading
            duckAIChromeTitleButton.imageHugsTitle = true
            duckAIChromeTitleButton.normalTintColor = colorsProvider.textPrimaryColor
            duckAIChromeTitleButton.mouseOverTintColor = colorsProvider.textPrimaryColor
            duckAIChromeTitleButton.mouseDownTintColor = colorsProvider.textPrimaryColor
            // Leading space widens the icon↔label gap (imageHugsTitle otherwise sits them flush).
            duckAIChromeTitleButton.attributedTitle = NSAttributedString(string: " " + UserText.askAIChatButtonTitle, attributes: [
                .foregroundColor: colorsProvider.textPrimaryColor,
                .font: titleFont
            ])
            duckAIChromeTitleButton.toolTip = UserText.askAIChatButtonTitle
            duckAIChromeTitleButton.setAccessibilityTitle(UserText.askAIChatButtonTitle)
            duckAIChromeTitleButton.sendAction(on: [.leftMouseDown, .otherMouseUp])
            duckAIChromeTitleButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        } else {
            duckAIChromeTitleButton.image = nil
            duckAIChromeTitleButton.imagePosition = .noImage
            duckAIChromeTitleButton.attributedTitle = NSAttributedString(string: UserText.aiChatTitle, attributes: [
                .foregroundColor: colorsProvider.textPrimaryColor,
                .font: titleFont
            ])
            duckAIChromeTitleButton.toolTip = UserText.aiChatOpenNewTabButton
            duckAIChromeTitleButton.setAccessibilityTitle(UserText.aiChatOpenNewTabButton)
            duckAIChromeTitleButton.sendAction(on: .leftMouseDown)
            duckAIChromeTitleButton.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
        duckAIChromeTitleButton.backgroundColor = .clear
        duckAIChromeTitleButton.mouseOverColor = colorsProvider.buttonMouseDownColor
        duckAIChromeTitleButton.mouseDownColor = colorsProvider.buttonMouseDownPressedColor
        duckAIChromeTitleButton.setCornerRadius(cornerRadius)
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

        // Always deactivate the outgoing constraint before activating the incoming one so that
        // both height constraints on the divider are never simultaneously active.
        if showFullHeight {
            duckAIChromeDividerInsetConstraint?.setActive(false)
            duckAIChromeDividerFullConstraint?.setActive(true)
        } else {
            duckAIChromeDividerFullConstraint?.setActive(false)
            duckAIChromeDividerInsetConstraint?.setActive(true)
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
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyChromeSidebarFeatureFlagState(isEnabled: isEnabled)
            }
    }

    /// Re-applies the layout on any feature-flag change so toggling `aiChatChromeMenuButton` switches
    /// between the pill and the split button live.
    private func subscribeToDuckAIChromeLayoutChanges() {
        duckAIChromeLayoutCancellable = featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyDuckAIChromeLayoutIfNeeded()
            }
    }

    private func applyDuckAIChromeLayoutIfNeeded() {
        guard duckAIChromeControlContainer != nil else { return }
        updateDuckAIChromeSegmentedControlAppearance()
        applyDuckAIChromeButtonVisibility()
        updateDuckAIChromeSegmentedControlState()
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
        } else if aiChatMenuConfig.shouldOpenAIChatInSidebar, case .onboarding = tab.content,
                  NonBlockingOnboarding(featureFlagger: featureFlagger).isNonBlocking {
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
        return tab.content != .onboarding || NonBlockingOnboarding(featureFlagger: featureFlagger).isNonBlocking
    }

    private func updateDuckAIChromeSegmentedControlState() {
        guard let duckAIChromeTitleButton, let duckAIChromeSidebarButton else { return }

        // Menu-button layout: the pill is a plain menu trigger with no sidebar-state styling.
        if isMenuButtonLayout {
            duckAIChromeTitleButton.isEnabled = isDuckAIChromeButtonsEnabled
            return
        }

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
        // Menu-button layout: left-click opens the dropdown; middle-click and ⌘-click skip it and start a
        // new chat right away, preserving the one-click access the split button used to offer.
        if isMenuButtonLayout {
            if let gesture = AIChatMenuButtonPixelFirer.NewChatGesture(clickEventType: NSApp.currentEvent?.type,
                                                                       isCommandPressed: NSApp.isCommandPressed) {
                openNewDuckAIChatTabFromMenuButton(via: gesture)
            } else {
                presentDuckAIMenuButtonMenu(from: sender)
            }
            return
        }

        if let mainViewController = parent as? MainViewController {
            PixelKit.fire(AIChatPixel.aiChatTabbarButtonClicked, frequency: .dailyAndStandard)
            mainViewController.openNewDuckAIChatTab()
            return
        }

        Logger.general.error("TabBarViewController: Failed to find MainViewController to open Duck.ai")
    }

    // MARK: - Duck.ai menu button (single-pill layout)

    private func presentDuckAIMenuButtonMenu(from sender: NSButton) {
        let sidebarEntry = AIChatMenuButtonSidebarEntry(isChatPresented: isDuckAIChatPresented,
                                                        isPageAttachable: isCurrentPageAttachableForAIChat)
        duckAIMenuSidebarEntry = sidebarEntry
        let menu = makeDuckAIMenuButtonMenu(sidebarEntry: sidebarEntry)
        // Right-align: anchor the menu's top-right corner to the button's bottom-right.
        let origin = NSPoint(x: sender.bounds.width - menu.size.width, y: sender.bounds.height + 4)
        duckAIMenuButtonPixelFirer.fireMenuShown(sidebarEntry: sidebarEntry)
        menu.popUp(positioning: nil, at: origin, in: sender)
    }

    private func subscribeToNativeChats() {
        guard !isFireWindow else { return }
        (nativeStorageHandler as? DuckAiNativeChatsObserving)?.chatsPublisher()
            .map { !$0.isEmpty }
            .replaceError(with: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasChats in
                self?.isChatsMenuItemEnabled = hasChats
            }
            .store(in: &cancellables)
    }

    /// The pill's dropdown, rebuilt per press so the sidebar item's title/icon reflect the current
    /// tab and chat state.
    private func makeDuckAIMenuButtonMenu(sidebarEntry: AIChatMenuButtonSidebarEntry) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let newChatItem = NSMenuItem(title: UserText.aiChatMenuNewChat, action: #selector(duckAIMenuNewChatAction), keyEquivalent: "")
        newChatItem.target = self
        newChatItem.withImage(DesignSystemImages.Glyphs.Size12.compose, visibleOnMacOS27: true)
        // Display-only: mirror the main menu's ⌥⌘N (handling lives on the main-menu item).
        newChatItem.keyEquivalent = "n"
        newChatItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(newChatItem)

        let sidebarItem = NSMenuItem(title: "", action: #selector(duckAIMenuSidebarAction), keyEquivalent: "")
        sidebarItem.target = self
        switch sidebarEntry {
        case .askAboutPage:
            sidebarItem.title = UserText.aiChatMenuAskAboutPage
            sidebarItem.withImage(Self.openSidebarMenuIcon(), visibleOnMacOS27: true)
        case .openSidebar:
            sidebarItem.title = UserText.aiChatMenuOpenSidebar
            sidebarItem.withImage(Self.openSidebarMenuIcon(), visibleOnMacOS27: true)
        case .closeSidebar:
            sidebarItem.title = UserText.aiChatMenuCloseSidebar
            sidebarItem.withImage(Self.closeSidebarMenuIcon(), visibleOnMacOS27: true)
        }
        // Display-only: mirror the main menu's ⌥⌘L. This transient popup doesn't register the shortcut
        // globally (the main-menu item owns handling); it just shows the glyph for discoverability.
        sidebarItem.keyEquivalent = "l"
        sidebarItem.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(sidebarItem)

        if featureFlagger.isFeatureOn(.aiChatChromeMenuChats) {
            menu.addItem(.separator())

            let chatsItem = NSMenuItem(title: UserText.actionChats, action: #selector(duckAIMenuChatsAction), keyEquivalent: "")
            chatsItem.target = self
            chatsItem.isEnabled = Self.chatsMenuItemIsEnabled(
                inFireWindow: isFireWindow,
                nativeStorageHandler: nativeStorageHandler,
                observedRegularWindowValue: isChatsMenuItemEnabled
            )
            chatsItem.withImage(Self.contextMenuIcon(DesignSystemImages.Glyphs.Size24.chats), visibleOnMacOS27: true)
            menu.addItem(chatsItem)
        }

        return menu
    }

    static func chatsMenuItemIsEnabled(
        inFireWindow isFireWindow: Bool,
        nativeStorageHandler: DuckAiNativeStorageHandling?,
        observedRegularWindowValue: Bool
    ) -> Bool {
        guard isFireWindow else { return observedRegularWindowValue }
        // Only a confirmed empty store disables Chats; unavailable storage must not block navigation.
        guard let nativeStorageHandler,
              let chats = try? nativeStorageHandler.getAllChats() else { return true }
        return !chats.isEmpty
    }

    /// The two-part control's "open sidebar" icon, copied and sized for a menu item. Copying avoids
    /// mutating the shared asset instance still used by the split button when the menu-button flag is off.
    static func openSidebarMenuIcon() -> NSImage {
        menuIcon(named: Constants.duckAISidebarOpenImageName)
    }

    /// The two-part control's "close sidebar" icon, copied and sized for a menu item.
    static func closeSidebarMenuIcon() -> NSImage {
        menuIcon(named: Constants.duckAISidebarCloseImageName)
    }

    private static func menuIcon(named name: NSImage.Name) -> NSImage {
        let named = NSImage(named: name)
        guard let icon = named?.copy() as? NSImage else { return named ?? NSImage() }
        icon.size = NSSize(width: 12, height: 12)
        return icon
    }

    /// Copies a glyph (avoids mutating the shared asset) and sizes it for the context menu. Both items
    /// use their 24pt variants resized to 16 so they share the same design grid and render at a
    /// consistent visual size.
    static func contextMenuIcon(_ image: NSImage) -> NSImage {
        guard let icon = image.copy() as? NSImage else { return image }
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    /// Whether a Duck.ai chat is currently presented for the selected tab (docked sidebar or floating).
    var isDuckAIChatPresented: Bool {
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab else { return false }
        return aiChatCoordinator?.isSidebarOpen(for: tab.uuid) == true || aiChatCoordinator?.isChatFloating(for: tab.uuid) == true
    }

    @objc private func duckAIMenuNewChatAction() {
        openNewDuckAIChatTabFromMenuButton(via: .menuItem)
    }

    private func openNewDuckAIChatTabFromMenuButton(via gesture: AIChatMenuButtonPixelFirer.NewChatGesture) {
        duckAIMenuButtonPixelFirer.fireNewChat(via: gesture)
        guard let mainViewController = parent as? MainViewController else {
            Logger.general.error("TabBarViewController: Failed to find MainViewController to open Duck.ai")
            return
        }
        mainViewController.openNewDuckAIChatTab()
    }

    @objc private func duckAIMenuChatsAction() {
        PixelKit.fire(AIChatPixel.aiChatChatsTitleBarMenu, frequency: .dailyAndStandard)
        guard let mainViewController = parent as? MainViewController else {
            Logger.general.error("TabBarViewController: Failed to find MainViewController to open Duck.ai")
            return
        }
        mainViewController.openDuckAIChatHistory()
    }

    /// Closes an open chat (sidebar or floating), otherwise opens the sidebar with the current page
    /// attached. Takes no sender: UI tests find the item by this selector's name.
    @objc private func duckAIMenuSidebarAction() {
        guard let duckAIMenuSidebarEntry else {
            assertionFailure("The Duck.ai menu's sidebar item was picked before the menu resolved its entry")
            return
        }
        switch duckAIMenuSidebarEntry.action {
        case .close:
            closeDuckAIChat()
        case .open(let sidebarOpenSource):
            openDuckAISidebarWithPageAttachment(sidebarOpenSource: sidebarOpenSource)
        }
    }

    /// Closes the current tab's Duck.ai chat, whether docked in the sidebar or in a floating window.
    func closeDuckAIChat() {
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab else { return }
        let tabID = tab.uuid
        // Mirror the split button and the open path: report the docked-sidebar close. Floating-window
        // closes are reported separately by the coordinator (aiChatSidebarFloatingClosed).
        if aiChatCoordinator?.isSidebarOpen(for: tabID) == true {
            PixelKit.fire(AIChatPixel.aiChatSidebarClosed(source: .tabbarButton), frequency: .dailyAndStandard)
        }
        aiChatCoordinator?.closeChat(for: tabID, withAnimation: true)
        updateDuckAIChromeSegmentedControlState()
    }

    /// Opens the sidebar and force-attaches the current page regardless of the auto-send preference.
    func openDuckAISidebarWithPageAttachment(conversationSource: AIChatConversationSource = .askAboutPage,
                                             sidebarOpenSource: AIChatSidebarOpenSource = .askAboutPage) {
        guard let tab = tabCollectionViewModel.selectedTabViewModel?.tab else { return }
        let tabID = tab.uuid

        if aiChatCoordinator?.isChatFloating(for: tabID) == true {
            aiChatCoordinator?.focusFloatingWindow(for: tabID)
        } else {
            if aiChatCoordinator?.isSidebarOpen(for: tabID) == false {
                PixelKit.fire(
                    AIChatPixel.aiChatSidebarOpened(
                        source: sidebarOpenSource,
                        shouldAutomaticallySendPageContext: aiChatMenuConfig.shouldAutomaticallySendPageContextTelemetryValue,
                        minutesSinceSidebarHidden: aiChatCoordinator?.sidebarHiddenAt(for: tabID)?.minutesSinceNow()
                    ),
                    frequency: .dailyAndStandard
                )
                NSApp.delegateTyped.aiChatConversationSourceHandler.setData(conversationSource)
            }
            aiChatCoordinator?.revealChat()
        }

        tab.pageContext?.requestPageContextAttachment()
        updateDuckAIChromeSegmentedControlState()
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
                NSApp.delegateTyped.aiChatConversationSourceHandler.setData(.tabBarSidebar)
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

    private func setupScrollInsets() {
        collectionView.horizontalScrollInset = theme.tabStyleProvider.shouldShowSShapedTab ? TabBarViewItem.horizontalInset : 0
    }

    private func setupTabsContainersHeight() {
        scrollViewHeightConstraint.constant = theme.tabStyleProvider.tabsScrollViewHeight
        pinnedTabsContainerHeightConstraint.constant = theme.tabStyleProvider.pinnedTabsContainerViewHeight
    }

    private func setupAsBurnerWindowIfNeeded() {
        guard tabCollectionViewModel.isBurner,
              !tabCollectionViewModel.isPopup else { return }

        fireButton.isAnimationEnabled = false
        fireButton.backgroundColor = NSColor(designSystemColor: .accentFireGlowPrimary)
        fireButton.mouseOverColor = NSColor(designSystemColor: .accentFireGlowSecondary)
        fireButton.mouseDownColor = NSColor(designSystemColor: .accentFireGlowSecondary)
        fireButton.normalTintColor = NSColor(designSystemColor: .accentFirePrimary)
        fireButton.mouseDownTintColor = NSColor(designSystemColor: .accentFireSecondary)
        fireButton.mouseOverTintColor = NSColor(designSystemColor: .accentFireSecondary)
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
        cookiePopupsBlockedPromoDelegate?.dismissDueToNewTabBeingShown()
        tabCollectionViewModel.insertOrAppendNewTab()
    }

    @objc func rightScrollButtonAction(_ sender: NSButton) {
        collectionView.scrollToEnd()
    }

    @objc func leftScrollButtonAction(_ sender: NSButton) {
        collectionView.scrollToBeginning()
    }

    /// Group changes reload the collection view on the next run loop pass; a selection change in between
    /// would scroll with a stale item count and crash, so reload first when the counts differ.
    private func reloadIfItemCountIsStale() {
        if collectionView.numberOfItems(inSection: 0) != displayItems.count {
            reloadDataAndLayout()
        }
    }

    /// An animated scroll right after `reloadData`, before layout, can keep showing the old cells,
    /// e.g. a tab where a group header now belongs. Lay out first.
    private func reloadDataAndLayout() {
        collectionView.reloadData()
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
    }

    private func reloadSelection() {
        reloadIfItemCountIsStale()
        let isPinnedTab = tabCollectionViewModel.selectionIndex?.isPinnedTab == true

        let collectionView: TabBarCollectionView? = isPinnedTab ? pinnedTabsCollectionView : self.collectionView

        bringSelectedTabCollectionToFront()

        guard let collectionView else {
            return
        }

        defer {
            refreshPinnedTabsLastSeparator()
        }

        guard let selectionIndex = tabCollectionViewModel.selectionIndex else {
            Logger.general.error("TabBarViewController: Selection index is nil")
            return
        }

        // For pinned tabs, index maps directly
        // For unpinned tabs, convert from tab index to displayItems index
        let displayIndex: Int
        if isPinnedTab {
            displayIndex = selectionIndex.item
        } else {
            guard let tab = tabCollectionViewModel.tabCollection.tabs[safe: selectionIndex.item],
                  let index = displayItemIndex(for: tab) else {
                return
            }
            displayIndex = index
        }

        guard collectionView.selectionIndexPaths.first?.item != displayIndex else {
            collectionView.updateItemsLeftToSelectedItems()
            return
        }

        clearSelection()

        let newSelectionIndexPath = IndexPath(item: displayIndex)
        if tabMode == .divided {
            invalidateLayoutIfNeeded(for: collectionView)
            collectionView.animator().selectItems(at: [newSelectionIndexPath], scrollPosition: .centeredHorizontally)
        } else {
            collectionView.selectItems(at: [newSelectionIndexPath], scrollPosition: .centeredHorizontally)
            collectionView.scrollToSelected()
        }
    }

    private func invalidateLayoutIfNeeded(for collectionView: TabBarCollectionView) {
        guard selectionNeedsLayoutInvalidation else {
            return
        }

        collectionView.invalidateLayout()
        selectionNeedsLayoutInvalidation = false
    }

    /// With groups, collection view items include headers, so incremental updates by tab index are replaced by a reload.
    private var hasTabGroups: Bool {
        !tabCollectionViewModel.tabGroupManager.tabToGroup.isEmpty
    }

    private func displayIndex(forUnpinnedTabIndex tabIndex: Int) -> Int {
        guard hasTabGroups, let tab = tabCollectionViewModel.tabCollection.tabs[safe: tabIndex] else { return tabIndex }
        return displayItemIndex(for: tab) ?? tabIndex
    }

    /// Finds the displayItems index for a given tab
    private func displayItemIndex(for tab: some TabGroupMember) -> Int? {
        displayItems.firstIndex { $0.tab?.uuid == tab.uuid }
    }

    /// Selects the next available (visible) tab when the current selection becomes hidden
    private func selectNextAvailableTab() {
        let tabGroupManager = tabCollectionViewModel.tabGroupManager

        // Find the first visible unpinned tab (not in a collapsed group)
        for (index, tab) in tabCollectionViewModel.tabCollection.tabs.enumerated() {
            if let group = tabGroupManager.group(for: tab) {
                // Tab is in a group - check if group is collapsed
                if !tabGroupManager.isCollapsed(group) {
                    tabCollectionViewModel.select(at: .unpinned(index))
                    return
                }
            } else {
                // Tab is not in any group - it's visible
                tabCollectionViewModel.select(at: .unpinned(index))
                return
            }
        }

        // If no unpinned tabs available, try pinned tabs
        if !tabCollectionViewModel.pinnedTabs.isEmpty {
            tabCollectionViewModel.select(at: .pinned(0))
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

        // For unpinned tabs, convert displayItems index to tab index
        if let indexPath = collectionView.indexPathForItemAtMouseLocation(locationInWindow) {
            let items = displayItems
            if indexPath.item < items.count,
               let tab = items[indexPath.item].tab,
               let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) {
                tabCollectionViewModel.select(at: .unpinned(tabIndex))
            }
            return
        }

        // For pinned tabs, indexPath maps directly
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

        // Constrain drag & drop to within the same group (like pinned/unpinned constraint)
        let tabGroupManager = tabCollectionViewModel.tabGroupManager
        let sourceTab = tabCollection.tabs[safe: oldIndex.item]
        let targetTab = tabCollection.tabs[safe: newIndex.item]

        let sourceGroupID = sourceTab.flatMap { tabGroupManager.groupID(for: $0) }
        let targetGroupID = targetTab.flatMap { tabGroupManager.groupID(for: $0) }

        // Only allow move if both tabs are in the same group (or both ungrouped)
        guard sourceGroupID == targetGroupID else { return }

        tabCollectionViewModel.moveTab(at: oldIndex, to: newIndex)
        tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: newIndex)
    }

    private func moveToNewWindow(unpinnedIndex: Int, droppingPoint: NSPoint? = nil, burner: Bool) {
        let sourceTab: TabIndex = .unpinned(unpinnedIndex)
        guard tabCollectionViewModel.canMoveTabToNewWindow(tabIndex: sourceTab) else {
            return
        }

        guard let tab = tabCollectionViewModel.materialize(at: sourceTab) else {
            assertionFailure("TabBarViewController: Failed to get tab")
            return
        }

        guard let oldWebExtensionIndex = tabCollectionViewModel.webExtensionIndex(for: sourceTab) else { return }

        // The tab moves to a new window; it isn't closed and reopened.
        TabCollectionViewModel.withWebExtensionTabLifecycleEventsSuppressed {
            tabCollectionViewModel.remove(at: sourceTab, published: false)
            WindowsManager.openNewWindow(with: tab, droppingPoint: droppingPoint)
        }
        tabCollectionViewModel.notifyWebExtensionTabMoved(tab, from: oldWebExtensionIndex)
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
    /// Selection an in-flight insert is about to apply. `sizeForItemAt` runs synchronously
    /// from `insertItems(at:)`, before the view model publishes the new `selectionIndex`, so
    /// it consults this to size the inserted tab as selected and the outgoing one as not.
    private var incomingSelectionIndex: TabIndex?
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
        refreshScrollShadowsVisibility()
    }

    private func displayScrollButtons() {
        let scrollViewsAreHidden = tabMode == .divided
        rightScrollButton.isHidden = scrollViewsAreHidden
        leftScrollButton.isHidden = scrollViewsAreHidden
        addTabButton.isHidden = scrollViewsAreHidden

        refreshScrollShadowsVisibility()
        adjustStandardTabPosition()
    }

    private func refreshScrollShadowsVisibility() {
        let isOverflowing = tabMode == .overflow
        leftShadowImageView.isHidden = !isOverflowing || collectionView.isAtStartScrollPosition
        rightShadowImageView.isHidden = !isOverflowing || collectionView.isAtEndScrollPosition
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
              let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem)
        else {
            Logger.general.error("TabBarViewController: Showing tab preview window failed - cannot determine index path for tab")
            return
        }

        guard let previewable = tabCollectionViewModel.tabBarViewModel(at: tabIndex) as? Previewable else {
            Logger.general.error("TabBarViewController: Showing tab preview window failed - previewable not found for index \(String(reflecting: tabIndex))")
            return
        }

        let isSelected: Bool
        if let loadedVM = previewable as? TabViewModel {
            isSelected = tabCollectionViewModel.selectedTabViewModel === loadedVM
        } else {
            isSelected = false
        }

        if isPinned {
            let position = pinnedTabsContainerView.frame.minX + tabBarViewItem.view.frame.minX
            showTabPreview(for: previewable, isSelected: isSelected, from: position)
        } else {
            guard let clipView = collectionView.clipView else {
                Logger.general.error("TabBarViewController: Showing tab preview window failed - clip view not found")
                return
            }
            let position = scrollView.frame.minX + tabBarViewItem.view.frame.minX - clipView.bounds.origin.x
            showTabPreview(for: previewable, isSelected: isSelected, from: position)
        }
    }

    private func showTabPreview(for previewable: Previewable, isSelected: Bool, from xPosition: CGFloat) {
        guard shouldDisplayTabPreviews else {
            Logger.tabPreview.error("Not showing tab preview: shouldDisplayTabPreviews == false")
            hideTabPreview(allowQuickRedisplay: true)
            return
        }

        tabPreviewWindowController.tabPreviewViewController.display(tabViewModel: previewable,
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
        setupAsBurnerWindowIfNeeded()

        let colorsProvider = theme.colorsProvider
        let isFireWindow = tabCollectionViewModel.isBurner

        backgroundColorView.backgroundColor = colorsProvider.baseBackgroundColor

        let fireWindowHoverColor = NSColor(designSystemColor: .accentFireGlowSecondary)
        fireButton.normalTintColor = isFireWindow ? NSColor(designSystemColor: .accentFirePrimary) : colorsProvider.iconsColor
        fireButton.mouseOverColor = isFireWindow ? fireWindowHoverColor : colorsProvider.buttonMouseOverColor

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

    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel,
                                didMoveTab tab: Tab,
                                fromWebExtensionIndex oldIndex: Int) {
        guard #available(macOS 15.4, *),
              let oldWindow = Application.appDelegate.windowControllersManager.windowController(for: tabCollectionViewModel),
              let webExtensionManager = NSApp.delegateTyped.webExtensionManager else { return }
        webExtensionManager.eventsListener.didMoveTab(tab, from: oldIndex, in: oldWindow)
    }

    func tabCollectionViewModelDidAppend(_ tabCollectionViewModel: TabCollectionViewModel, selected: Bool) {
        if hasTabGroups {
            tabCollectionViewModelDidMultipleChanges(tabCollectionViewModel)
            return
        }
        appendToCollectionView(selected: selected)
    }

    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didReplaceTabAt index: TabIndex) {
        if hasTabGroups, index.isUnpinnedTab {
            tabCollectionViewModelDidMultipleChanges(tabCollectionViewModel)
            return
        }
        let collectionView = index.isPinnedTab ? pinnedTabsCollectionView : self.collectionView
        guard let collectionView else {
            Logger.general.error("collection view is nil")
            return
        }
        let indexPathSet = Set(arrayLiteral: IndexPath(item: index.item))
        collectionView.reloadItems(at: indexPathSet)
    }

    func tabCollectionViewModelDidInsert(_ tabCollectionViewModel: TabCollectionViewModel, at index: TabIndex, selected: Bool) {
        if hasTabGroups, index.isUnpinnedTab {
            tabCollectionViewModelDidMultipleChanges(tabCollectionViewModel)
            return
        }
        let collectionView = index.isPinnedTab ? pinnedTabsCollectionView : self.collectionView
        guard let collectionView else {
            Logger.general.error("collection view is nil")
            return
        }
        let indexPathSet = Set(arrayLiteral: IndexPath(item: index.item))
        if selected {
            clearSelection(animated: true)
            incomingSelectionIndex = index
        }
        defer { incomingSelectionIndex = nil }

        // A mutation re-entering between the model update and this callback leaves the
        // collection view's item count stale; an incremental insert would then raise
        // NSInternalInconsistencyException, so reconcile with a full reload instead.
        let modelCount = index.isPinnedTab
            ? (tabCollectionViewModel.pinnedTabsCollection?.tabs.count ?? 0)
            : tabCollectionViewModel.tabCollection.tabs.count
        if collectionView.numberOfItems(inSection: 0) == modelCount - 1 {
            collectionView.animator().insertItems(at: indexPathSet)
        } else {
            Logger.general.error("TabBarViewController: item count out of sync on insert, reloading")
            collectionView.reloadData()
        }
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
        // Simplified: reload and update selection
        // Index translation between tabs array and displayItems is complex for animations
        collectionView.reloadData()

        self.updateTabMode(for: collectionView.numberOfItems(inSection: 0), updateLayout: false)

        if let selectionIndex,
           let tab = tabCollectionViewModel.tabCollection.tabs[safe: selectionIndex],
           let displayIndex = displayItemIndex(for: tab) {
            let selectionIndexPathSet = Set(arrayLiteral: IndexPath(item: displayIndex))
            collectionView.selectItems(at: selectionIndexPathSet, scrollPosition: .centeredHorizontally)
        }

        frozenLayout = isMouseLocationInsideBounds
        if !frozenLayout {
            updateLayout()
        }
        updateEmptyTabArea()
        enableScrollButtons()
        hideTabPreview()
    }

    /// index and newIndex are guaranteed to be from the same collection (pinned or unpinned)
    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didMoveTabAt index: TabIndex, to newIndex: TabIndex) {
        // For pinned tabs, animate normally
        if index.isPinnedTab {
            let indexPath = IndexPath(item: index.item)
            let newIndexPath = IndexPath(item: newIndex.item)
            pinnedTabsCollectionView?.animator().moveItem(at: indexPath, to: newIndexPath)
            return
        }

        // For unpinned tabs, reload to avoid displayItems index translation issues
        collectionView.reloadData()
        updateTabMode()
        hideTabPreview()

        // Re-select the moved tab
        if let tab = tabCollectionViewModel.tabCollection.tabs[safe: newIndex.item],
           let displayIndex = displayItemIndex(for: tab) {
            collectionView.selectItems(at: [IndexPath(item: displayIndex)], scrollPosition: .centeredHorizontally)
        }
    }

    func tabCollectionViewModel(_ tabCollectionViewModel: TabCollectionViewModel, didSelectAt selectionIndex: Int?) {
        reloadIfItemCountIsStale()
        clearSelection(animated: true)
        if let selectionIndex = selectionIndex,
           let tab = tabCollectionViewModel.tabCollection.tabs[safe: selectionIndex],
           let displayIndex = displayItemIndex(for: tab) {
            let selectionIndexPathSet = Set(arrayLiteral: IndexPath(item: displayIndex))
            collectionView.animator().selectItems(at: selectionIndexPathSet, scrollPosition: .centeredHorizontally)
            collectionView.scrollToSelected()
        }
    }

    func tabCollectionViewModelDidMultipleChanges(_ tabCollectionViewModel: TabCollectionViewModel) {
        reloadDataAndLayout()
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
        // Simplified: reload and select the newly added tab
        if frozenLayout {
            updateLayout()
        }

        collectionView.reloadData()
        updateTabMode(for: collectionView.numberOfItems(inSection: 0))

        if selected {
            clearSelection()
            // New tab is at the end of tabs array - find its displayItems index
            if let lastTab = tabCollectionViewModel.tabCollection.tabs.last,
               let displayIndex = displayItemIndex(for: lastTab) {
                let indexPathSet = Set(arrayLiteral: IndexPath(item: displayIndex))
                collectionView.selectItems(at: indexPathSet, scrollPosition: .centeredHorizontally)
            }
        }
        defer { incomingSelectionIndex = nil }

        let collectionViewItemCount = collectionView.numberOfItems(inSection: 0)
        let modelItemCount = tabCollectionViewModel.tabCollection.tabs.count

        // See `tabCollectionViewModelDidInsert(_:at:selected:)` on the count check.
        guard collectionViewItemCount == modelItemCount - 1 else {
            Logger.general.error("TabBarViewController: item count out of sync on append, reloading")
            collectionView.reloadData()
            updateTabMode(for: modelItemCount)
            if selected {
                collectionView.selectItems(at: lastIndexPathSet, scrollPosition: .centeredHorizontally)
            } else {
                collectionView.scroll(to: IndexPath(item: lastIndex))
            }
            updateEmptyTabArea()
            hideTabPreview()
            return
        }

        updateTabMode(for: collectionViewItemCount + 1)

        if tabMode != .divided {
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

    private func fireproof(url: URL) {
        guard let host = url.host else {
            Logger.general.error("TabBarViewController: Failed to get host from url")
            return
        }

        fireproofDomains.add(domain: host)
    }

    private func removeFireproofing(url: URL) {
        guard let host = url.host else {
            Logger.general.error("TabBarViewController: Failed to get host from url")
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

        // Group headers are only as wide as their pill
        let items = displayItems
        if indexPath.item < items.count, let group = items[indexPath.item].groupHeader {
            let groupTabs = tabCollectionViewModel.tabGroupManager.tabs(in: group, from: tabCollectionViewModel.tabCollection.tabs)
            let width = TabGroupHeaderPill.width(name: group.name,
                                                 tabCount: groupTabs.count,
                                                 isCollapsed: tabCollectionViewModel.tabGroupManager.isCollapsed(group))
            return NSSize(width: width, height: standardTabHeight)
        }

        // Check if this displayItem corresponds to the selected tab
        var isItemSelected = false
        if indexPath.item < items.count,
           let tab = items[indexPath.item].tab,
           let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) {
            isItemSelected = tabCollectionViewModel.selectionIndex == .unpinned(tabIndex)
        }

        return NSSize(width: self.currentTabWidth(selected: isItemSelected), height: standardTabHeight)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets {
        let isPinnedTabs = collectionView == pinnedTabsCollectionView
        if isPinnedTabs {
            return NSEdgeInsetsZero
        }
        if theme.tabStyleProvider.shouldShowSShapedTab {
            // With no right scroll button, the trailing ramp bleeds under the footer instead.
            let inset = TabBarViewItem.horizontalInset
            return NSEdgeInsets(top: 0, left: inset, bottom: 0, right: rightScrollButton.isHidden ? -inset : inset)

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
        return displayItems.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: TabBarViewItem.identifier, for: indexPath)
        guard let tabBarViewItem = item as? TabBarViewItem else {
            assertionFailure("TabBarViewController: Failed to get reusable TabBarViewItem instance")
            return item
        }

        // Handle pinned tabs collection (unchanged)
        if collectionView == pinnedTabsCollectionView {
            let tabIndex: TabIndex = .pinned(indexPath.item)
            guard let tabViewModel = tabCollectionViewModel.tabBarViewModel(at: tabIndex) else {
                tabBarViewItem.clear()
                return tabBarViewItem
            }

            tabBarViewItem.fireproofDomains = fireproofDomains
            tabBarViewItem.delegate = self
            tabBarViewItem.isBurner = tabCollectionViewModel.isBurner
            tabBarViewItem.subscribe(to: tabViewModel)
            tabBarViewItem.isLeftToSelected = pinnedTabsCollectionView?.isLastItemInSection(indexPath: indexPath) == true && shouldHideLastPinnedSeparator
            return tabBarViewItem
        }

        // Handle unpinned tabs collection with displayItems
        let items = displayItems
        guard indexPath.item < items.count else {
            tabBarViewItem.clear()
            return tabBarViewItem
        }

        let displayItem = items[indexPath.item]

        switch displayItem {
        case .groupHeader(let group):
            let groupTabs = tabCollectionViewModel.tabGroupManager.tabs(in: group, from: tabCollectionViewModel.tabCollection.tabs)
            tabBarViewItem.configureAsGroupHeader(group,
                                                  tabCount: groupTabs.count,
                                                  isCollapsed: tabCollectionViewModel.tabGroupManager.isCollapsed(group),
                                                  favicons: groupTabs.compactMap(\.favicon))
            tabBarViewItem.delegate = self

        case .tab(let tab):
            // Reset header state if cell was previously used as a header
            if tabBarViewItem.currentHeaderGroup != nil {
                tabBarViewItem.resetFromGroupHeader()
            }

            guard let index = tabCollectionViewModel.tabCollection.tabs.firstIndex(where: { $0.uuid == tab.uuid }),
                  let tabViewModel = tabCollectionViewModel.tabBarViewModel(at: .unpinned(index)) else {
                tabBarViewItem.clear()
                return tabBarViewItem
            }

            tabBarViewItem.fireproofDomains = fireproofDomains
            tabBarViewItem.delegate = self
            tabBarViewItem.isBurner = tabCollectionViewModel.isBurner
            tabBarViewItem.subscribe(to: tabViewModel)
            tabBarViewItem.updateGroupBackground()
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

            // For pinned tabs, indexPath maps directly
            if collectionView == pinnedTabsCollectionView {
                tabCollectionViewModel.select(at: .pinned(indexPath.item))
            } else {
                // For unpinned tabs, convert displayItems index to tab index
                let items = displayItems
                if indexPath.item < items.count,
                   let tab = items[indexPath.item].tab,
                   let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) {
                    tabCollectionViewModel.select(at: .unpinned(tabIndex))
                }
            }

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

        // For pinned tabs, indexPath maps directly
        if collectionView == pinnedTabsCollectionView {
            tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: .pinned(indexPath.item))
        } else {
            // For unpinned tabs, convert displayItems index to tab index
            let items = displayItems
            if indexPath.item < items.count,
               let tab = items[indexPath.item].tab,
               let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) {
                tabDragAndDropManager.setSource(tabCollectionViewModel: tabCollectionViewModel, index: .unpinned(tabIndex))
            }
        }

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

        // move tab within one window if needed: bail out if we're outside the CollectionView Bounds!
        let locationInView = collectionView.convert(draggingInfo.draggingLocation, from: nil)

        guard collectionView.frame.contains(locationInView) else {
            return .none
        }

        // For pinned tabs, indexPath maps directly to tabs
        if collectionView == pinnedTabsCollectionView {
            moveItemIfNeeded(to: .pinned(proposedDropIndexPath.pointee.item))
            return .private
        }

        // For unpinned tabs, convert displayItems index to tab index
        let displayIndex = proposedDropIndexPath.pointee.item
        let items = displayItems
        guard displayIndex < items.count,
              let tab = items[displayIndex].tab,
              let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) else {
            return .none
        }

        moveItemIfNeeded(to: .unpinned(tabIndex))

        return .private
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        // For pinned tabs, indexPath maps directly to tabs
        if collectionView == pinnedTabsCollectionView {
            guard let tabCollection = tabCollectionViewModel.pinnedTabsCollection else { return false }

            let newIndex = min(indexPath.item + 1, tabCollection.tabs.count)
            let tabIndex: TabIndex = .pinned(newIndex)

            if let url = draggingInfo.draggingPasteboard.url {
                tabCollectionViewModel.insert(Tab(content: .url(url, source: .appOpenUrl), burnerMode: tabCollectionViewModel.burnerMode),
                                              at: tabIndex,
                                              selected: true)
                return true
            }

            guard case .private = draggingInfo.draggingSourceOperationMask,
                  draggingInfo.draggingPasteboard.types == [TabBarViewItemPasteboardWriter.utiInternalType] else { return false }

            tabDragAndDropManager.setDestination(tabCollectionViewModel: tabCollectionViewModel, index: tabIndex)
            return true
        }

        // For unpinned tabs, convert displayItems index to tab index
        let items = displayItems
        let displayIndex = indexPath.item

        // Find the tab index for insertion
        var tabIndex: TabIndex
        if displayIndex < items.count, let tab = items[displayIndex].tab,
           let existingTabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) {
            tabIndex = .unpinned(existingTabIndex + 1)
        } else {
            // Insert at end
            tabIndex = .unpinned(tabCollectionViewModel.tabCollection.tabs.count)
        }

        if let url = draggingInfo.draggingPasteboard.url {
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
        // Handle group header click - toggle collapsed state
        if let group = tabBarViewItem.currentHeaderGroup {
            let tabGroupManager = tabCollectionViewModel.tabGroupManager
            let wasCollapsed = tabGroupManager.isCollapsed(group)
            tabGroupManager.toggleCollapsed(group)

            // If we're collapsing and the selected tab is in this group, select next available
            if !wasCollapsed, let selectedTab = tabCollectionViewModel.selectedTabViewModel?.tab {
                if tabGroupManager.group(for: selectedTab)?.id == group.id {
                    selectNextAvailableTab()
                }
            }
            return
        }

        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true

        // For pinned tabs, indexPath maps directly to tabs
        if isPinned {
            guard let indexPath = pinnedTabsCollectionView?.indexPath(for: tabBarViewItem) else {
                assertionFailure("TabBarViewController: Failed to get index path of pinned tab bar view item")
                return
            }
            tabCollectionViewModel.select(at: .pinned(indexPath.item))
            return
        }

        // For unpinned tabs, get the tab from displayItems and find its actual index
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        let items = displayItems
        guard indexPath.item < items.count,
              let tab = items[indexPath.item].tab,
              let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(of: tab) else {
            return
        }

        tabCollectionViewModel.select(at: .unpinned(tabIndex))
    }

    func tabBarViewItemCrashAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }
        tabCollectionViewModel.tabViewModel(at: tabIndex)?.tab.killWebContentProcess()
    }

    func tabBarViewItemCrashMultipleTimesAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tab = (tabBarViewItem.tabViewModel as? TabViewModel)?.tab else {
            assertionFailure("TabBarViewController: Failed to get tab for tab bar view item")
            return
        }
        tab.killWebContentProcessMultipleTimes()
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
        } else {
            if !shouldDisplayTabPreviews {
                hideTabPreview(withDelay: true, allowQuickRedisplay: true)
            }
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
        guard let tabViewModel = tabBarViewItem.tabViewModel else {
            assertionFailure("TabBarViewController: Failed to get tab view model for tab bar view item")
            return false
        }
        return tabViewModel.tabContent.canBeDuplicated
    }

    func tabBarViewItemNewToTheRightAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        insertNewTab(nextTo: tabIndex)
    }

    func tabBarViewItemDuplicateAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }
        duplicateTab(at: tabIndex)
    }

    func tabBarViewItemCanBePinned(_ tabBarViewItem: TabBarViewItem) -> Bool {
        guard let tabViewModel = tabBarViewItem.tabViewModel else {
            assertionFailure("TabBarViewController: Failed to get tab view model for tab bar view item")
            return false
        }
        return !tabViewModel.isPinned && tabViewModel.tabContent.canBePinned
    }

    func tabBarViewItemPinAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        clearSelection()

        switch tabIndex {
        case .pinned(let index):
            tabCollectionViewModel.unpinTab(at: index)
        case .unpinned(let index):
            tabCollectionViewModel.pinTab(at: index)
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
        guard let item = collectionView.item(at: IndexPath(item: displayIndex(forUnpinnedTabIndex: index), section: 0)) as? TabBarViewItem else {
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
        guard let tabViewModel = tabBarViewItem.tabViewModel else {
            assertionFailure("TabBarViewController: Failed to get tab view model for tab bar view item")
            return false
        }
        return tabViewModel.tabContent.canBeBookmarked
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
        let websitesInfo = tabCollectionViewModel.tabCollection.tabs.compactMap(WebsiteInfo.init)
        BookmarksDialogViewFactory.makeBookmarkAllOpenTabsView(
            websitesInfo: websitesInfo,
            bookmarkManager: bookmarkManager
        ).show()
    }

    func tabBarViewItemWillOpenContextMenu(_: TabBarViewItem) {
        hideTabPreview()
    }

    func tabBarViewItemCloseAction(_ tabBarViewItem: TabBarViewItem) {
        // Headers don't have close action
        guard tabBarViewItem.currentHeaderGroup == nil else { return }

        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        if tryPresentWarnBeforeCloseForFloatingAIChatIfNeeded(for: tabIndex) {
            return
        }

        if let tabID = tabCollectionViewModel.tabBarViewModel(at: tabIndex)?.uuid {
            aiChatCoordinator?.closeFloatingWindow(for: tabID)
        }
        tabCollectionViewModel.close(at: tabIndex)
    }

    private func shouldWarnBeforeClosingFloatingAIChat(tabID: String) -> Bool {
        aiChatCoordinator?.isChatFloating(for: tabID) == true
    }

    @discardableResult
    func tryPresentWarnBeforeCloseForFloatingAIChatIfNeeded(for tabIndex: TabIndex) -> Bool {
        guard let tabID = tabCollectionViewModel.tabBarViewModel(at: tabIndex)?.uuid,
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
            return collectionView.item(at: IndexPath(item: displayIndex(forUnpinnedTabIndex: index), section: 0)) as? TabBarViewItem
        }
    }

    private func closeTab(for tabID: String) {
        aiChatCoordinator?.closeFloatingWindow(for: tabID)
        guard let tabIndex = tabCollectionViewModel.indexInAllTabs(where: { $0.uuid == tabID }) else { return }
        tabCollectionViewModel.close(at: tabIndex)
    }

    func tabBarViewItemCloseOtherAction(_ tabBarViewItem: TabBarViewItem) {
        guard let tab = tab(for: tabBarViewItem),
              let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(where: { $0.uuid == tab.uuid }) else {
            return
        }

        tabCollectionViewModel.removeAllTabs(except: tabIndex)
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
        guard let url = (tabBarViewItem.tabViewModel as? TabViewModel)?.tab.url else {
            assertionFailure("TabBarViewController: Failed to get URL for tab bar view item")
            return
        }
        fireproof(url: url)
    }

    func tabBarViewItemMuteUnmuteSite(_ tabBarViewItem: TabBarViewItem) {
        guard let tab = (tabBarViewItem.tabViewModel as? TabViewModel)?.tab else {
            assertionFailure("TabBarViewController: Failed to get tab for tab bar view item")
            return
        }
        tab.muteUnmuteTab()
    }

    func tabBarViewItemRemoveFireproofing(_ tabBarViewItem: TabBarViewItem) {
        guard let url = (tabBarViewItem.tabViewModel as? TabViewModel)?.tab.url else {
            assertionFailure("TabBarViewController: Failed to get URL for tab bar view item")
            return
        }
        removeFireproofing(url: url)
    }

    func tabBarViewItemSuspendAction(_ tabBarViewItem: TabBarViewItem) {
        guard featureFlagger.isFeatureOn(.tabSuspension), featureFlagger.isFeatureOn(.tabSuspensionDebugging) else { return }

        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem) else {
            assertionFailure("TabBarViewController: Failed to get index path of tab bar view item")
            return
        }

        if tabBarViewItem.tabViewModel is UnloadedTabViewModel {
            tabCollectionViewModel.resumeTab(at: tabIndex)
        } else {
            tabCollectionViewModel.suspendTab(at: tabIndex)
        }
    }

    func tabBarViewItem(_ tabBarViewItem: TabBarViewItem, replaceContentWithDroppedStringValue stringValue: String) {
        guard let tabIndex = tabIndex(forTabBarViewItem: tabBarViewItem),
              let tab = tabCollectionViewModel.materialize(at: tabIndex) else { return }

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

    // MARK: - Tab Groups

    private func tab(for tabBarViewItem: TabBarViewItem) -> AnyTab? {
        let isPinned = tabBarViewItem.tabViewModel?.isPinned == true

        // For pinned tabs, indexPath maps directly to tabs array
        if isPinned {
            guard let indexPath = pinnedTabsCollectionView?.indexPath(for: tabBarViewItem),
                  let tab = tabCollectionViewModel.pinnedTabsCollection?.tabs[safe: indexPath.item] else {
                return nil
            }
            return tab
        }

        // For unpinned tabs, indexPath maps to displayItems, so look up the tab from there
        guard let indexPath = collectionView.indexPath(for: tabBarViewItem) else {
            return nil
        }

        let items = displayItems
        guard indexPath.item < items.count else { return nil }

        return items[indexPath.item].tab
    }

    func tabBarViewItemCurrentTabGroup(_ tabBarViewItem: TabBarViewItem) -> TabGroup? {
        // For headers, return the header's group directly
        if let headerGroup = tabBarViewItem.currentHeaderGroup {
            return headerGroup
        }
        guard let tab = tab(for: tabBarViewItem) else { return nil }
        return tabCollectionViewModel.tabGroupManager.group(for: tab)
    }

    func tabBarViewItem(_ tabBarViewItem: TabBarViewItem, perform operation: TabGroupOperations.Operation) {
        guard let group = tabBarViewItem.currentHeaderGroup else { return }
        TabGroupOperations(tabCollectionViewModel: tabCollectionViewModel).perform(operation, on: group)
    }

    func tabBarViewItemIsGroupCollapsed(_ tabBarViewItem: TabBarViewItem) -> Bool {
        tabBarViewItem.currentHeaderGroup.map(tabCollectionViewModel.tabGroupManager.isCollapsed) ?? false
    }

    func tabBarViewItemManageTabGroups(_ tabBarViewItem: TabBarViewItem) {
        guard let tab = tab(for: tabBarViewItem),
              let window = view.window else { return }

        let tabGroupManager = tabCollectionViewModel.tabGroupManager

        var hostingController: NSHostingController<TabGroupsManagementView>?

        let onAddToGroup: (TabGroup) -> Void = { [weak tabGroupManager] group in
            // The tab bar puts the tab next to its group once the change settles.
            tabGroupManager?.setGroup(group.id, for: tab)
        }

        let onRemoveFromGroup: () -> Void = { [weak tabGroupManager] in
            tabGroupManager?.setGroup(nil, for: tab)
        }

        let tabGroupsView = TabGroupsManagementView(
            tabGroupManager: tabGroupManager,
            currentTabUUID: tab.uuid,
            onAddToGroup: onAddToGroup,
            onRemoveFromGroup: onRemoveFromGroup,
            onDismiss: {
                hostingController?.dismiss(nil)
            }
        )

        hostingController = NSHostingController(rootView: tabGroupsView)
        window.contentViewController?.presentAsSheet(hostingController!)
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

        if isPinned {
            return .pinned(indexPath.item)
        }
        // Group headers are extra items, so map the item through the display list.
        let items = displayItems
        guard indexPath.item < items.count, let tab = items[indexPath.item].tab,
              let tabIndex = tabCollectionViewModel.tabCollection.tabs.firstIndex(where: { $0.uuid == tab.uuid }) else {
            return nil
        }
        return .unpinned(tabIndex)
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

        // Menu-button layout: single "Ask Duck.ai" pill, so the hide item uses the "Ask Duck.ai"
        // wording and there's no separate sidebar-button toggle.
        let duckAIItem = NSMenuItem(
            title: isMenuButtonLayout
                ? (duckAIHidden ? UserText.aiChatChromeShowAskDuckAIButton : UserText.aiChatChromeHideAskDuckAIButton)
                : (duckAIHidden ? UserText.aiChatChromeShowDuckAIButton : UserText.aiChatChromeHideDuckAIButton),
            action: duckAIHidden ? #selector(showDuckAITitleButtonAction) : #selector(hideDuckAITitleButtonAction),
            keyEquivalent: "Y"
        )
        duckAIItem.target = self
        duckAIItem.withImage(Self.contextMenuIcon(DesignSystemImages.Glyphs.Size24.aiChat), visibleOnMacOS27: true)
        menu.addItem(duckAIItem)

        if !isMenuButtonLayout {
            let sidebarHidden = duckAIChromeButtonsVisibilityManager.isHidden(.sidebar)
            let sidebarItem = NSMenuItem(
                title: sidebarHidden ? UserText.aiChatChromeShowSidebarButton : UserText.aiChatChromeHideSidebarButton,
                action: sidebarHidden ? #selector(showDuckAISidebarButtonAction) : #selector(hideDuckAISidebarButtonAction),
                keyEquivalent: "U"
            )
            sidebarItem.target = self
            menu.addItem(sidebarItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: UserText.aiChatChromeOpenAISettings,
            action: #selector(openAISettingsAction),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.withImage(Self.contextMenuIcon(DesignSystemImages.Glyphs.Size24.settingsAiChat), visibleOnMacOS27: true)
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
