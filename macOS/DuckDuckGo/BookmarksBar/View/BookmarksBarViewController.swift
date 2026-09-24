//
//  BookmarksBarViewController.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import Common
import ConcurrencyExtensions
import DesignResourcesKitIcons
import FeatureFlags_macOS
import Foundation
import FoundationExtensions
import os.log
import PrivacyConfig

final class BookmarksBarViewController: NSViewController {

    private enum Constants {
        static let contentSize = CGSize(width: 676, height: 28)
        static let barHeight: CGFloat = 24
        static let separatorHeight: CGFloat = 1
        static let horizontalInset: CGFloat = 8
        static let iconSize: CGFloat = 16
        static let iconLeadingInset: CGFloat = 4
        static let syncIconLeadingInset: CGFloat = 6
        static let labelSpacing: CGFloat = 4
        static let labelTrailingInset: CGFloat = 8
        static let clippedItemsIndicatorSize = CGSize(width: 28, height: 24)
        static let promptAnchorSize: CGFloat = 20
        static let mouseOverCornerRadius: CGFloat = 4
    }

    private(set) var importBookmarksButton: NSView!
    private(set) var importBookmarksMouseOverView: MouseOverView!
    private(set) var importBookmarksLabel: NSTextField!
    private(set) var importBookmarksIcon: NSImageView!
    private var bookmarksBarCollectionView: BookmarksBarCollectionView!
    private var clippedItemsIndicator: MouseOverButton!
    private var promptAnchor: NSView!
    private(set) var backgroundColorView: ColorView!

    private(set) var backseparatorColorView: ColorView!
    private(set) var separatorColorView: ColorView!

    private(set) var syncButton: NSView!
    private(set) var syncMouseOverView: MouseOverView!
    private(set) var syncButtonIcon: NSImageView!
    private(set) var syncButtonLabel: NSTextField!
    private(set) var bookmarksBarScrollView: NSScrollView!

    private var bookmarkMenuPopover: (any BookmarksBarMenuPopoverPresenting)?

    /// Monitor + saved state used while a bookmarks bar menu is open so cursor moves
    /// over the bar (now the parent of a key NSPanel popover) still trigger menu
    /// switching. The hover tracking areas in the bar items use `.activeInKeyWindow`,
    /// which stops firing when our popover takes key focus.
    private var bookmarksBarHoverMonitor: Any?
    private var savedAcceptsMouseMovedEvents: Bool?

    private let bookmarkManager: BookmarkManager
    private let dragDropManager: BookmarkDragDropManager
    private let pinningManager: PinningManager
    private let viewModel: BookmarksBarViewModel
    private let tabCollectionViewModel: TabCollectionViewModel
    private let appereancePreferences: AppearancePreferencesPersistor
    private let featureFlagger: FeatureFlagger

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    let syncButtonModel: DismissableSyncDeviceButtonModel = .init(source: .bookmarksBar, keyValueStore: UserDefaults.standard)

    private var cancellables = Set<AnyCancellable>()

    private static let maxDragDistanceToExpandHoveredFolder: CGFloat = 4
    private static let dragOverFolderExpandDelay: TimeInterval = 0.3
    private var dragDestination: (folder: BookmarkFolder, mouseLocation: NSPoint, hoverStarted: Date)?

    fileprivate var clipThreshold: CGFloat {
        let indicatorFrameInCollectionView = bookmarksBarCollectionView.convert(clippedItemsIndicator.frame, from: clippedItemsIndicator.superview)
        return indicatorFrameInCollectionView.minX - 3
    }

    static func create(
        tabCollectionViewModel: TabCollectionViewModel,
        bookmarkManager: BookmarkManager,
        dragDropManager: BookmarkDragDropManager,
        pinningManager: PinningManager,
        featureFlagger: FeatureFlagger
    ) -> BookmarksBarViewController {
        self.init(
            tabCollectionViewModel: tabCollectionViewModel,
            bookmarkManager: bookmarkManager,
            dragDropManager: dragDropManager,
            pinningManager: pinningManager,
            featureFlagger: featureFlagger
        )
    }

    init(tabCollectionViewModel: TabCollectionViewModel,
         bookmarkManager: BookmarkManager,
         dragDropManager: BookmarkDragDropManager,
         pinningManager: PinningManager,
         featureFlagger: FeatureFlagger,
         appereancePreferences: AppearancePreferencesPersistor = AppearancePreferencesUserDefaultsPersistor(keyValueStore: NSApp.delegateTyped.keyValueStore),
         themeManager: ThemeManaging = NSApp.delegateTyped.themeManager,
    ) {
        self.bookmarkManager = bookmarkManager
        self.dragDropManager = dragDropManager
        self.pinningManager = pinningManager
        self.appereancePreferences = appereancePreferences
        self.themeManager = themeManager
        self.featureFlagger = featureFlagger

        self.tabCollectionViewModel = tabCollectionViewModel
        self.viewModel = BookmarksBarViewModel(bookmarkManager: bookmarkManager,
                                               dragDropManager: dragDropManager,
                                               tabCollectionViewModel: tabCollectionViewModel,
                                               themeManager: themeManager)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("BookmarksBarViewController: Bad initializer")
    }

    // MARK: - View setup

    /// Icon + label laid out side by side with a `MouseOverView` on top: the overlay draws the hover
    /// and pressed fills and is the click target, so the whole pill reacts, not just the label.
    private func makeBarButton(action: Selector,
                               iconLeadingInset: CGFloat,
                               priority: NSLayoutConstraint.Priority) -> (container: NSView, icon: NSImageView, label: NSTextField, mouseOverView: MouseOverView) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setContentHuggingPriority(.init(750), for: .vertical)

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.imageAlignment = .alignLeft
        icon.refusesFirstResponder = true

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byClipping
        label.setContentHuggingPriority(.init(251), for: .horizontal)
        label.setContentHuggingPriority(.init(750), for: .vertical)

        let mouseOverView = MouseOverView(frame: .zero)
        mouseOverView.translatesAutoresizingMaskIntoConstraints = false
        mouseOverView.mouseOverColor = .buttonMouseOver
        mouseOverView.mouseDownColor = .buttonMouseDown
        mouseOverView.cornerRadius = Constants.mouseOverCornerRadius
        mouseOverView.target = self
        mouseOverView.action = action

        container.addSubview(icon)
        container.addSubview(label)
        container.addSubview(mouseOverView)

        let constraints = [
            container.heightAnchor.constraint(equalToConstant: Constants.barHeight),

            icon.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            icon.heightAnchor.constraint(equalToConstant: Constants.iconSize),
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: iconLeadingInset),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Constants.labelSpacing),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            mouseOverView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: mouseOverView.trailingAnchor),
            mouseOverView.topAnchor.constraint(equalTo: container.topAnchor),
            container.bottomAnchor.constraint(equalTo: mouseOverView.bottomAnchor),
        ]
        constraints.forEach { $0.priority = priority }

        // Required, unlike the rest: the label must never run into the container's trailing edge,
        // even when the caller lets the surrounding constraints break to collapse the button.
        let labelTrailing = container.trailingAnchor.constraint(equalTo: label.trailingAnchor, constant: Constants.labelTrailingInset)

        NSLayoutConstraint.activate(constraints + [labelTrailing])

        return (container, icon, label, mouseOverView)
    }

    override func loadView() {
        backgroundColorView = ColorView(frame: NSRect(origin: .zero, size: Constants.contentSize),
                                        backgroundColor: .bookmarkBarBackground)
        backgroundColorView.wantsLayer = true

        backseparatorColorView = ColorView(frame: .zero)
        backseparatorColorView.translatesAutoresizingMaskIntoConstraints = false

        separatorColorView = ColorView(frame: .zero)
        separatorColorView.translatesAutoresizingMaskIntoConstraints = false

        promptAnchor = NSView()
        promptAnchor.translatesAutoresizingMaskIntoConstraints = false

        bookmarksBarCollectionView = BookmarksBarCollectionView(frame: .zero)
        bookmarksBarCollectionView.isSelectable = true
        bookmarksBarCollectionView.collectionViewLayout = NSCollectionViewLayout()
        bookmarksBarCollectionView.backgroundColors = [.navigationBarBackground]
        bookmarksBarCollectionView.autoresizingMask = [.width]

        let clipView = NSClipView()
        clipView.documentView = bookmarksBarCollectionView
        clipView.autoresizingMask = [.width, .height]
        clipView.drawsBackground = false
        clipView.backgroundColor = .clear

        bookmarksBarScrollView = NSScrollView()
        bookmarksBarScrollView.translatesAutoresizingMaskIntoConstraints = false
        bookmarksBarScrollView.wantsLayer = true
        bookmarksBarScrollView.borderType = .noBorder
        bookmarksBarScrollView.autohidesScrollers = true
        bookmarksBarScrollView.hasHorizontalScroller = false
        bookmarksBarScrollView.hasVerticalScroller = false
        bookmarksBarScrollView.usesPredominantAxisScrolling = false
        bookmarksBarScrollView.horizontalScrollElasticity = .none
        bookmarksBarScrollView.verticalScrollElasticity = .none
        bookmarksBarScrollView.contentView = clipView

        clippedItemsIndicator = MouseOverButton(frame: .zero)
        clippedItemsIndicator.translatesAutoresizingMaskIntoConstraints = false
        clippedItemsIndicator.setButtonType(.momentaryChange)
        clippedItemsIndicator.bezelStyle = .rounded
        clippedItemsIndicator.isBordered = false
        clippedItemsIndicator.image = .chevronDoubleRight16
        clippedItemsIndicator.imagePosition = .imageOverlaps
        clippedItemsIndicator.title = ""
        clippedItemsIndicator.imageScaling = .scaleProportionallyDown
        clippedItemsIndicator.alignment = .center
        clippedItemsIndicator.mouseOverColor = .buttonMouseOver
        clippedItemsIndicator.mouseDownColor = .buttonMouseDown
        clippedItemsIndicator.cornerRadius = Constants.mouseOverCornerRadius
        clippedItemsIndicator.target = self
        clippedItemsIndicator.action = #selector(clippedItemsIndicatorClicked(_:))
        clippedItemsIndicator.setContentHuggingPriority(.init(750), for: .vertical)

        let importBookmarks = makeBarButton(action: #selector(importBookmarksClicked(_:)),
                                            iconLeadingInset: Constants.iconLeadingInset,
                                            priority: .required)
        importBookmarksButton = importBookmarks.container
        importBookmarksIcon = importBookmarks.icon
        importBookmarksLabel = importBookmarks.label
        importBookmarksMouseOverView = importBookmarks.mouseOverView

        let sync = makeBarButton(action: #selector(syncClicked(_:)),
                                 iconLeadingInset: Constants.syncIconLeadingInset,
                                 priority: .init(750))
        syncButton = sync.container
        syncButtonIcon = sync.icon
        syncButtonLabel = sync.label
        syncMouseOverView = sync.mouseOverView

        backgroundColorView.addSubview(backseparatorColorView)
        backgroundColorView.addSubview(separatorColorView)
        backgroundColorView.addSubview(promptAnchor)
        backgroundColorView.addSubview(bookmarksBarScrollView)
        backgroundColorView.addSubview(clippedItemsIndicator)
        backgroundColorView.addSubview(importBookmarksButton)
        backgroundColorView.addSubview(syncButton)

        syncButtonZeroWidthConstraint = syncButton.widthAnchor.constraint(equalToConstant: 0)
        syncButtonZeroWidthConstraint.priority = .init(250)

        NSLayoutConstraint.activate([
            backseparatorColorView.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),
            backseparatorColorView.leadingAnchor.constraint(equalTo: backgroundColorView.leadingAnchor),
            backgroundColorView.trailingAnchor.constraint(equalTo: backseparatorColorView.trailingAnchor),
            backgroundColorView.bottomAnchor.constraint(equalTo: backseparatorColorView.bottomAnchor),

            separatorColorView.leadingAnchor.constraint(equalTo: backseparatorColorView.leadingAnchor),
            separatorColorView.trailingAnchor.constraint(equalTo: backseparatorColorView.trailingAnchor),
            separatorColorView.topAnchor.constraint(equalTo: backseparatorColorView.topAnchor),
            separatorColorView.bottomAnchor.constraint(equalTo: backseparatorColorView.bottomAnchor),

            promptAnchor.widthAnchor.constraint(equalToConstant: Constants.promptAnchorSize),
            promptAnchor.heightAnchor.constraint(equalToConstant: Constants.promptAnchorSize),
            promptAnchor.centerXAnchor.constraint(equalTo: backgroundColorView.centerXAnchor),
            promptAnchor.centerYAnchor.constraint(equalTo: backgroundColorView.centerYAnchor),

            bookmarksBarScrollView.heightAnchor.constraint(equalToConstant: Constants.barHeight),
            bookmarksBarScrollView.topAnchor.constraint(equalTo: backgroundColorView.topAnchor),
            backgroundColorView.trailingAnchor.constraint(equalTo: bookmarksBarScrollView.trailingAnchor),
            bookmarksBarScrollView.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor),

            clippedItemsIndicator.widthAnchor.constraint(equalToConstant: Constants.clippedItemsIndicatorSize.width),
            clippedItemsIndicator.heightAnchor.constraint(equalToConstant: Constants.clippedItemsIndicatorSize.height),
            clippedItemsIndicator.topAnchor.constraint(equalTo: backgroundColorView.topAnchor),
            backgroundColorView.trailingAnchor.constraint(equalTo: clippedItemsIndicator.trailingAnchor,
                                                          constant: Constants.horizontalInset),

            importBookmarksButton.topAnchor.constraint(equalTo: bookmarksBarCollectionView.topAnchor),
            importBookmarksButton.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 2),

            syncButton.leadingAnchor.constraint(equalTo: backgroundColorView.leadingAnchor,
                                                constant: Constants.horizontalInset),
            syncButton.centerYAnchor.constraint(equalTo: bookmarksBarScrollView.centerYAnchor),
            syncButtonZeroWidthConstraint,
        ])

        self.view = backgroundColorView
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        setUpImportBookmarksButton()

        addContextMenu()

        viewModel.delegate = self

        let nib = NSNib(nibNamed: "BookmarksBarCollectionViewItem", bundle: .main)
        bookmarksBarCollectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        bookmarksBarCollectionView.register(nib, forItemWithIdentifier: BookmarksBarCollectionViewItem.identifier)
        bookmarksBarCollectionView.allowsMultipleSelection = false

        bookmarksBarCollectionView.registerForDraggedTypes(BookmarkDragDropManager.draggedTypes)
        bookmarksBarCollectionView.setAccessibilityIdentifier("BookmarksBarViewController.bookmarksBarCollectionView")

        clippedItemsIndicator.registerForDraggedTypes(BookmarkDragDropManager.draggedTypes)
        clippedItemsIndicator.delegate = self
        clippedItemsIndicator.sendAction(on: .leftMouseDown)

        importBookmarksLabel.stringValue = UserText.importBookmarks
        importBookmarksLabel.font = .systemFont(ofSize: 11, weight: .regular)

        bookmarksBarCollectionView.delegate = viewModel
        bookmarksBarCollectionView.dataSource = viewModel

        view.postsFrameChangedNotifications = true

        setUpSyncButton()
        subscribeToThemeChanges()
        applyThemeStyle()
    }

    private func setUpSyncButton() {
        if appereancePreferences.showBookmarksBar {
            syncButtonModel.viewDidLoad()
        }
        syncButton.layer?.cornerRadius = theme.toolbarButtonsCornerRadius
        syncMouseOverView.cornerRadius = theme.toolbarButtonsCornerRadius
        syncButton.isHidden = !syncButtonModel.shouldShowSyncButton
        syncButtonIcon.image = DesignSystemImages.Glyphs.Size16.sync
        syncButtonIcon.contentTintColor = .textPrimary
        syncButtonLabel.stringValue = UserText.bookmarksEmptyStateSyncButtonTitle
        syncButtonLabel.font = .systemFont(ofSize: 11, weight: .regular)
    }

    private func setUpImportBookmarksButton() {
        importBookmarksIcon.image = NSImage(named: "Import-16D")
        importBookmarksIcon.contentTintColor = .textPrimary
        importBookmarksButton.isHidden = true
        importBookmarksButton.layer?.cornerRadius = theme.toolbarButtonsCornerRadius
        importBookmarksMouseOverView.cornerRadius = theme.toolbarButtonsCornerRadius
    }

    private func addContextMenu() {
        let menu = NSMenu()
        menu.delegate = self
        self.view.menu = menu
    }

    override func viewWillAppear() {
        super.viewWillAppear()

        subscribeToEvents()
        refreshFavicons()
        bookmarksBarCollectionView.collectionViewLayout = createCenterAlignedCollectionViewLayout(centered: appereancePreferences.centerAlignedBookmarksBar)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        frameDidChangeNotification()
    }

    private var bookmarksBarPrompt: BookmarksBarPromptPopover?

    func showBookmarksBarPrompt(onDismiss: @escaping (PromoResult) -> Void) {
        let popover = BookmarksBarPromptPopover()
        popover.viewController.rootView.model.onDismiss = { [weak self] result in
            self?.bookmarksBarPrompt = nil
            onDismiss(result)
        }
        bookmarksBarPrompt = popover
        popover.show(relativeTo: promptAnchor.bounds, of: promptAnchor, preferredEdge: .minY)
    }

    func retractBookmarksBarPromptIfNeeded() {
        bookmarksBarPrompt?.retract()
        bookmarksBarPrompt = nil
    }

    func userInteraction(prevented: Bool) {
        bookmarksBarCollectionView.isSelectable = !prevented
        clippedItemsIndicator.isEnabled = !prevented
        viewModel.isInteractionPrevented = prevented
        bookmarksBarCollectionView.reloadData()
    }

    private func frameDidChangeNotification() {
        self.viewModel.clipOrRestoreBookmarksBarItems()
        self.refreshClippedIndicator()
    }

    override func removeFromParent() {
        super.removeFromParent()
        unsubscribeFromEvents()
        stopBookmarksBarHoverTracking()
    }

    deinit {
        if let monitor = bookmarksBarHoverMonitor {
            NSEvent.removeMonitor(monitor)
        }
#if DEBUG
        (bookmarkMenuPopover as? NSObject)?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    private func subscribeToEvents() {
        guard cancellables.isEmpty else { return }

        NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: view)
            // Wait until the frame change has taken effect for subviews before calculating changes to the list of items.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.frameDidChangeNotification()
            }
            .store(in: &cancellables)

        // Favicon images are decoded lazily and `.faviconCacheUpdated` fires for every favicon that
        // becomes available anywhere in the app. Reloading the bar on each post rebuilds every item and
        // makes the bar's favicons flicker during the decode cascade. Reload only when an updated host
        // belongs to a bookmark, using the notification payload (matches `BookmarksBarMenuViewController`).
        NotificationCenter.default.publisher(for: .faviconCacheUpdated)
            .sink { [weak self] notification in
                guard let self else { return }
                if let update = notification.faviconsCacheUpdate,
                   update.hosts.isDisjoint(with: self.bookmarkManager.allHosts()) {
                    return
                }
                self.refreshFavicons()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AppearancePreferences.Notifications.bookmarksBarAlignmentChanged)
            .compactMap { $0.userInfo?[AppearancePreferences.Constants.bookmarksBarAlignmentChangedIsCenterAlignedParameter] as? Bool }
            .sink { [weak self] isCenterAligned in
                self?.bookmarksBarCollectionView.collectionViewLayout = self?.createCenterAlignedCollectionViewLayout(centered: isCenterAligned)
            }
            .store(in: &cancellables)

        viewModel.$clippedItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshClippedIndicator()
            }
            .store(in: &cancellables)

        viewModel.$bookmarksBarItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                if self?.bookmarkManager.list != nil {
                    self?.importBookmarksButton.isHidden = !items.isEmpty
                }
            }
            .store(in: &cancellables)

        clippedItemsIndicator.publisher(for: \.isMouseOver)
            .sink { [weak self] isMouseOver in
                guard isMouseOver, let self, let clippedItemsIndicator else { return }
                mouseDidHover(over: clippedItemsIndicator)
            }
            .store(in: &cancellables)

        syncButtonModel.$shouldShowSyncButton.sink { [weak self] in
            self?.syncButton.isHidden = !$0
            self?.syncButtonZeroWidthConstraint.priority = $0 ? .defaultLow : .required
        }
        .store(in: &cancellables)
    }

    private func unsubscribeFromEvents() {
        cancellables.removeAll()
    }

    /// Open bookmarks submenu after delay when dragging an item over a Folder (or cancel when dragging out of it)
    /// - Returns: was submenu shown?
    @discardableResult
    private func dragging(over view: NSView?, representing folder: BookmarkFolder?, updatedWith info: NSDraggingInfo?) -> Bool {
        guard let view, let folder, let cursorPosition = info?.draggingLocation else {
            dragDestination = nil
            // close all Bookmarks popovers including the Bookmarks Button popover
            BookmarksBarMenuCustomPopover.closeBookmarkListPopovers(shownIn: self.view.window)
            return false
        }
        if let bookmarkMenuPopover, bookmarkMenuPopover.isShown,
           bookmarkMenuPopover.rootFolder?.id == folder.id {
            // folder menu already shown
            return true
        }

        // show folder bookmarks menu after delay
        if let dragDestination,
           dragDestination.folder.id == folder.id,
           dragDestination.mouseLocation.distance(to: cursorPosition) < Self.maxDragDistanceToExpandHoveredFolder {

            if Date().timeIntervalSince(dragDestination.hoverStarted) >= Self.dragOverFolderExpandDelay {
                showSubmenu(for: folder, from: view)
                return true
            }
        } else {
            self.dragDestination = (folder: folder, mouseLocation: cursorPosition, hoverStarted: Date())
        }
        return false
    }

    // MARK: - Layout

    private func createAlignedLayout(centered: Bool) -> NSCollectionLayoutSection {
        let group = NSCollectionLayoutGroup.align(cellSizes: viewModel.cellSizes, interItemSpacing: BookmarksBarViewModel.Constants.buttonSpacing, centered: centered)
        return NSCollectionLayoutSection(group: group)
    }

    private func createCenterAlignedCollectionViewLayout(centered: Bool) -> NSCollectionViewLayout {
        return BookmarksBarCenterAlignedLayout { [unowned self] _, _ in
            return createAlignedLayout(centered: centered && viewModel.clippedItems.isEmpty)
        }
    }

    private func refreshClippedIndicator() {
        self.clippedItemsIndicator.isHidden = viewModel.clippedItems.isEmpty
    }

    private func refreshFavicons() {
        dispatchPrecondition(condition: .onQueue(.main))
        // Update favicons in place on the existing cells rather than `reloadData()`. Rebuilding every
        // cell on each favicon-cache update would cause favicons flickering. In-place refresh only
        // upgrades placeholder → image and never "downgrades" to a placeholder image.
        for case let item as BookmarksBarCollectionViewItem in bookmarksBarCollectionView.visibleItems() {
            item.refreshDisplayedFavicon()
        }
    }

    @objc func importBookmarksClicked(_ sender: Any) {
        DataImportFlowLauncher(pinningManager: pinningManager).launchDataImport(isDataTypePickerExpanded: true, in: view.window)
    }

    private(set) var syncButtonZeroWidthConstraint: NSLayoutConstraint!

    @objc func syncClicked(_ sender: Any) {
        syncButtonModel.syncButtonAction()
    }

    @objc private func clippedItemsIndicatorClicked(_ sender: NSButton) {
        showSubmenu(for: clippedItemsBookmarkFolder(), from: sender)
    }

    private func clippedItemsBookmarkFolder() -> BookmarkFolder {
        BookmarkFolder(id: PseudoFolder.bookmarks.id, title: PseudoFolder.bookmarks.name, children: viewModel.clippedItems.map(\.entity))
    }

}
// MARK: - BookmarksBarViewModelDelegate
extension BookmarksBarViewController: BookmarksBarViewModelDelegate {

    func didClick(_ item: BookmarksBarCollectionViewItem) {
        guard let indexPath = bookmarksBarCollectionView.indexPath(for: item) else {
            assertionFailure("Failed to look up index path for clicked item")
            return
        }

        guard let entity = bookmarkManager.list?.topLevelEntities[indexPath.item] else {
            assertionFailure("Failed to get entity for clicked item")
            return
        }

        switch entity {
        case let bookmark as Bookmark:
            Application.appDelegate.windowControllersManager.open(bookmark, with: NSApp.currentEvent)
        case let folder as BookmarkFolder:
            showSubmenu(for: folder, from: item.view)
        default:
            assertionFailure("Failed to cast entity for clicked item")
        }
    }

    func bookmarksBarViewModelWidthForContainer() -> CGFloat {
        return clipThreshold
    }

    func bookmarksBarViewModelReloadedData() {
        bookmarksBarCollectionView.reloadData()

        if let bookmarkMenuPopover, bookmarkMenuPopover.isShown,
           bookmarkMenuPopover.rootFolder?.id == PseudoFolder.bookmarks.id /* clipped items folder has id of the root */ {
            bookmarkMenuPopover.reloadData(withRootFolder: clippedItemsBookmarkFolder())
        }
    }

    func mouseDidHover(over sender: Any) {
        guard let bookmarkMenuPopover, bookmarkMenuPopover.isShown,
              NSApp.currentEvent.map({ NSPoint(x: $0.deltaX, y: $0.deltaY) }) != .zero else { return }
        var bookmarkFolder: (() -> BookmarkFolder?)?
        var bookmarkFolderId: String?
        var view: NSView?
        if let item = sender as? BookmarksBarCollectionViewItem {
            let folder = item.representedObject as? BookmarkFolder
            bookmarkFolder = { folder }
            bookmarkFolderId = folder?.id
            view = item.view
        } else if let button = sender as? NSButton, button === clippedItemsIndicator {
            bookmarkFolder = { self.clippedItemsBookmarkFolder() }
            bookmarkFolderId = PseudoFolder.bookmarks.id
            view = button
        }
        if let bookmarkFolderId, let view {
            // already shown?
            guard bookmarkMenuPopover.rootFolder?.id != bookmarkFolderId, let bookmarkFolder = bookmarkFolder?() else { return }
            showSubmenu(for: bookmarkFolder, from: view)
        } else {
            bookmarkMenuPopover.close()
        }
    }

    func dragging(over item: BookmarksBarCollectionViewItem?, updatedWith info: (any NSDraggingInfo)?) {
        guard let info, let item = item,
              let folder = item.representedObject as? BookmarkFolder else {
            info?.draggingInfoUpdatedTimerCancellable = nil

            self.dragging(over: nil, representing: nil, updatedWith: info)
            return
        }

        let submenuShown = self.dragging(over: item.view, representing: folder, updatedWith: info)
        if !submenuShown {
            let draggingLocation = info.draggingLocation
            // NSCollectionView doesn‘t send extra `draggingUpdated` events when cursor stays at the same point
            // here we simulate the standard `NSView.draggingUpdated` behavior sent continuously while dragging
            // to open the Folder submenu after a delay while dragging over it.
            Task { @MainActor [weak self, weak info] in
                while let self, let info, info.draggingLocation == draggingLocation {
                    if self.dragging(over: item.view, representing: folder, updatedWith: info) == true {
                        return
                    }
                    try await Task.sleep(interval: 0.05)
                }
            }
        }
    }

    func showDialog(_ dialog: any ModalView) {
        dialog.show(in: view.window)
    }
}

// MARK: - ThemeUpdateListening
extension BookmarksBarViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        let navigationBackgroundColor = theme.colorsProvider.navigationBackgroundColor

        backgroundColorView.backgroundColor = navigationBackgroundColor
        bookmarksBarCollectionView.backgroundColors = [navigationBackgroundColor]
        separatorColorView.backgroundColor = theme.palette.unifiedInputFieldFillSecondary
        backseparatorColorView.backgroundColor = theme.palette.surfaceBackdrop
    }
}

private let draggingInfoUpdatedTimerKey = UnsafeRawPointer(bitPattern: "draggingInfoUpdatedTimerKey".hashValue)!
extension NSDraggingInfo {
    var draggingInfoUpdatedTimerCancellable: AnyCancellable? {
        get {
            objc_getAssociatedObject(self, draggingInfoUpdatedTimerKey) as? AnyCancellable
        }
        set {
            objc_setAssociatedObject(self, draggingInfoUpdatedTimerKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

}

// MARK: - Drag&Drop over Clipped Items indicator
extension BookmarksBarViewController: MouseOverButtonDelegate {

    func mouseOverButton(_ sender: MouseOverButton, draggingEntered info: any NSDraggingInfo, isMouseOver: UnsafeMutablePointer<Bool>) -> NSDragOperation {
        guard sender === clippedItemsIndicator else { return .none }
        let operation = dragDropManager.validateDrop(info, to: clippedItemsBookmarkFolder())
        isMouseOver.pointee = (operation != .none)
        return operation
    }

    func mouseOverButton(_ sender: MouseOverButton, draggingUpdatedWith info: any NSDraggingInfo, isMouseOver: UnsafeMutablePointer<Bool>) -> NSDragOperation {
        guard sender === clippedItemsIndicator else { return .none }
        let clippedItemsBookmarkFolder = clippedItemsBookmarkFolder()
        self.dragging(over: sender, representing: clippedItemsBookmarkFolder, updatedWith: info)
        let operation = dragDropManager.validateDrop(info, to: clippedItemsBookmarkFolder)
        isMouseOver.pointee = (operation != .none)
        return operation
    }

    func mouseOverButton(_ sender: MouseOverButton, performDragOperation info: any NSDraggingInfo) -> Bool {
        guard sender === clippedItemsIndicator else { return false }
        return dragDropManager.acceptDrop(info, to: clippedItemsBookmarkFolder(), at: -1)
    }

}
// MARK: - Private
private extension BookmarksBarViewController {

    func bookmarkFolderMenu(items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.items = items.isEmpty ? [NSMenuItem.empty] : items
        menu.autoenablesItems = false
        return menu
    }

    func showSubmenu(for folder: BookmarkFolder, from view: NSView) {
        let bookmarkMenuPopover: any BookmarksBarMenuPopoverPresenting
        if let popover = self.bookmarkMenuPopover {
            bookmarkMenuPopover = popover
            if bookmarkMenuPopover.isShown {
                bookmarkMenuPopover.close()
                if bookmarkMenuPopover.rootFolder?.id == folder.id {
                    return // close popover on 2nd click on the same folder
                }
            }
            bookmarkMenuPopover.reloadData(withRootFolder: folder)
        } else {
            bookmarkMenuPopover = BookmarksBarMenuCustomPopover(bookmarkManager: bookmarkManager, dragDropManager: dragDropManager, rootFolder: folder)
            bookmarkMenuPopover.bookmarksBarMenuDelegate = self
            self.bookmarkMenuPopover = bookmarkMenuPopover
        }

        view.window?.makeKeyAndOrderFront(nil)
        bookmarkMenuPopover.show(positionedBelow: view)
        startBookmarksBarHoverTracking()

        if view === clippedItemsIndicator {
            // display pressed state
            clippedItemsIndicator.backgroundColor = .buttonMouseDown
            clippedItemsIndicator.mouseOverColor = .buttonMouseDown
        } else if let collectionViewItem = view.nextResponder as? BookmarksBarCollectionViewItem {
            collectionViewItem.isDisplayingMouseDownState = true
        }
    }

    @objc func manageBookmarks() {
        Application.appDelegate.windowControllersManager.showBookmarksTab()
    }

    @objc func addFolder(sender: NSMenuItem) {
        showDialog(BookmarksDialogViewFactory.makeAddBookmarkFolderView(parentFolder: nil, bookmarkManager: bookmarkManager))
    }

    @objc func reorderBookmarksBarByName(_ sender: NSMenuItem) {
        bookmarkManager.reorderByName(
            bookmarkManager.list?.topLevelEntities ?? [],
            withinParentFolder: .root,
            undoManager: undoManager
        )
    }

}
// MARK: - NSMenuDelegate
extension BookmarksBarViewController: NSMenuDelegate {

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        BookmarksBarMenuFactory.addToMenuWithManageBookmarksSection(
            menu,
            target: self,
            addFolderSelector: #selector(addFolder(sender:)),
            reorderByNameSelector: featureFlagger.isFeatureOn(.bookmarksReorderByName) ? #selector(reorderBookmarksBarByName(_:)) : nil,
            manageBookmarksSelector: #selector(manageBookmarks),
            prefs: NSApp.delegateTyped.appearancePreferences
        )
    }

}
// MARK: - BookmarksBarMenuPopoverDelegate
extension BookmarksBarViewController: BookmarksBarMenuPopoverDelegate {

    func bookmarksBarMenuPopoverShouldClose(_ popover: any BookmarksBarMenuPopoverPresenting) -> Bool {
        if NSApp.currentEvent?.type == .leftMouseUp {
           if let point = bookmarksBarCollectionView.mouseLocationInsideBounds(),
              let indexPath = bookmarksBarCollectionView.indexPathForItem(at: point),
              bookmarkManager.list?.topLevelEntities[safe: indexPath.item] is BookmarkFolder {
               // we‘ll close the popover inside the click handler calling `showSubmenu`
               return false
           } else if clippedItemsIndicator.mouseLocationInsideBounds() != nil {
               // same
               return false
           }
        }
        return true
    }

    func bookmarksBarMenuPopoverDidClose(_ popover: any BookmarksBarMenuPopoverPresenting) {
        stopBookmarksBarHoverTracking()

        guard let positioningView = popover.positioningView else { return }

        if positioningView === clippedItemsIndicator {
            clippedItemsIndicator.backgroundColor = .clear
            clippedItemsIndicator.mouseOverColor = .buttonMouseOver
        } else if let collectionViewItem = positioningView.nextResponder as? BookmarksBarCollectionViewItem {
            collectionViewItem.isDisplayingMouseDownState = false
        }
    }

    private func startBookmarksBarHoverTracking() {
        if savedAcceptsMouseMovedEvents == nil, let mainWindow = view.window {
            savedAcceptsMouseMovedEvents = mainWindow.acceptsMouseMovedEvents
            mainWindow.acceptsMouseMovedEvents = true
        }
        if bookmarksBarHoverMonitor == nil {
            bookmarksBarHoverMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                self?.dispatchBookmarksBarHover()
                return event
            }
        }
    }

    private func stopBookmarksBarHoverTracking() {
        if let monitor = bookmarksBarHoverMonitor {
            NSEvent.removeMonitor(monitor)
            bookmarksBarHoverMonitor = nil
        }
        if let saved = savedAcceptsMouseMovedEvents, let mainWindow = view.window {
            mainWindow.acceptsMouseMovedEvents = saved
        }
        savedAcceptsMouseMovedEvents = nil
    }

    private func dispatchBookmarksBarHover() {
        guard let mainWindow = view.window else { return }
        let mouseLocation = NSEvent.mouseLocation
        // In a short window a folder menu can cover the Bookmarks Bar. The local
        // mouse-moved monitor also receives events sent to the menu window, so ignore
        // the hover when a menu is displayed above the point: without this the
        // Bookmarks Bar selection changes and the menu closes while the user moves
        // the cursor over the menu items.
        guard !isBookmarksBarMenuDisplayed(at: mouseLocation) else { return }
        let windowPoint = mainWindow.convertPoint(fromScreen: mouseLocation)
        let cvPoint = bookmarksBarCollectionView.convert(windowPoint, from: nil)
        if bookmarksBarCollectionView.bounds.contains(cvPoint),
           let indexPath = bookmarksBarCollectionView.indexPathForItem(at: cvPoint),
           let item = bookmarksBarCollectionView.item(at: indexPath) as? BookmarksBarCollectionViewItem {
            mouseDidHover(over: item)
            return
        }
        if let indicatorSuper = clippedItemsIndicator.superview {
            let indicatorPoint = indicatorSuper.convert(windowPoint, from: nil)
            if clippedItemsIndicator.frame.contains(indicatorPoint), !clippedItemsIndicator.isHidden {
                mouseDidHover(over: clippedItemsIndicator as Any)
            }
        }
    }

    /// Is a bookmarks menu window the frontmost window at the given screen point?
    private func isBookmarksBarMenuDisplayed(at screenPoint: NSPoint) -> Bool {
        let windowNumber = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
        return NSApp.window(withWindowNumber: windowNumber) is BookmarksBarMenuWindow
    }

    func openNextBookmarksMenu(_ sender: any BookmarksBarMenuPopoverPresenting) {
        guard let folder = sender.rootFolder else {
            assertionFailure("No root folder set in BookmarkListPopover")
            return
        }
        let folderIdx: Int?
        if folder.id == PseudoFolder.bookmarks.id {
            // clipped items folder has id of the root
            folderIdx = nil
        } else if let idx = viewModel.bookmarksBarItems.firstIndex(where: { $0.entity.id == folder.id }) {
            folderIdx = idx
        } else {
            assertionFailure("Could not find currently open folder in the Bookmarks Bar")
            return
        }
        if let folderIdx, folderIdx + 1 < viewModel.bookmarksBarItems.count {
            // switch to next folder in the Bookmarks Bar on Right arrow press
            for idx in viewModel.bookmarksBarItems.indices[(folderIdx + 1)...] {
                guard let folder = viewModel.bookmarksBarItems[idx].entity as? BookmarkFolder,
                      let cell = bookmarksBarCollectionView.item(at: idx)?.view else { continue }
                showSubmenu(for: folder, from: cell)
                return
            }
        }
        // next folder not found: open clipped items menu (if not switching from it: folderIdx != nil)
        if folderIdx != nil, !viewModel.clippedItems.isEmpty {
            showSubmenu(for: clippedItemsBookmarkFolder(), from: clippedItemsIndicator)
            return
        }
        // switch to 1st folder in the Bookmarks Bar after the Clipped Items menu or after last folder if no clipped items
        for (idx, item) in viewModel.bookmarksBarItems.enumerated() {
            guard let folder = item.entity as? BookmarkFolder, let cell = bookmarksBarCollectionView.item(at: idx)?.view else { continue }
            showSubmenu(for: folder, from: cell)
            return
        }
    }

    func openPreviousBookmarksMenu(_ sender: any BookmarksBarMenuPopoverPresenting) {
        guard let folder = sender.rootFolder else {
            assertionFailure("No root folder set in BookmarkListPopover")
            return
        }
        let folderIdx: Int
        if folder.id == PseudoFolder.bookmarks.id {
            // clipped items folder has id of the root
            folderIdx = viewModel.bookmarksBarItems.count
        } else if let idx = viewModel.bookmarksBarItems.firstIndex(where: { $0.entity.id == folder.id }) {
            folderIdx = idx
        } else {
            assertionFailure("Could not find currently open folder in the Bookmarks Bar")
            return
        }
        if folderIdx > 0, !viewModel.bookmarksBarItems.isEmpty {
            // switch to previous folder in the Bookmarks Bar on Left arrow press
            for idx in viewModel.bookmarksBarItems.indices[..<folderIdx].reversed() {
                guard let folder = viewModel.bookmarksBarItems[idx].entity as? BookmarkFolder,
                      let cell = bookmarksBarCollectionView.item(at: idx)?.view else { continue }
                showSubmenu(for: folder, from: cell)
                return
            }
        }
        // previous folder not found: open clipped items menu (if not switching from it: folderIdx != nil)
        if !viewModel.clippedItems.isEmpty {
            guard folderIdx != viewModel.bookmarksBarItems.count else { return } // if already in the clipped items menu
            showSubmenu(for: clippedItemsBookmarkFolder(), from: clippedItemsIndicator)
            return
        }
        // switch to last folder in the Bookmarks Bar before the Clipped Items menu or after last folder if no clipped items
        for (idx, item) in viewModel.bookmarksBarItems.enumerated().reversed() {
            guard let folder = item.entity as? BookmarkFolder, let cell = bookmarksBarCollectionView.item(at: idx)?.view else { continue }
            showSubmenu(for: folder, from: cell)
            return
        }
    }

}
