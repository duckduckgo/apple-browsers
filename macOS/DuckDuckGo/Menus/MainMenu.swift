//
//  MainMenu.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Cocoa
import Combine
import Common
import ConcurrencyExtensions
import Configuration
import DesignResourcesKitIcons
import FeatureFlags
import FoundationExtensions
import History
import OSLog
import PixelKit
import PrivacyConfig
import Subscription
import SubscriptionUI
import SwiftUI
import Utilities
import VPN
import WebKit

// MARK: - LazyBookmarkFolderMenuDelegate

@MainActor
final class LazyBookmarkFolderMenuDelegate: NSObject, NSMenuDelegate {
    private let children: [BookmarkViewModel]
    private var isPopulated = false
    private var childDelegates: [LazyBookmarkFolderMenuDelegate] = []

    init(children: [BookmarkViewModel]) {
        self.children = children
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        menu.removeAllItems() // removes the placeholder
        buildItems(in: menu)
    }

    private func buildItems(in menu: NSMenu) {
        let bookmarks = children.compactMap { $0.entity as? Bookmark }
        if bookmarks.count > 1 {
            menu.addItem(NSMenuItem(bookmarkViewModels: children))
            menu.addItem(.separator())
        }
        for viewModel in children {
            let item = NSMenuItem(bookmarkViewModel: viewModel)
            if let folder = viewModel.entity as? BookmarkFolder, !folder.children.isEmpty {
                let subMenu = NSMenu(title: folder.title)
                subMenu.addItem(NSMenuItem()) // placeholder
                let childViewModels = folder.children.map(BookmarkViewModel.init)
                let delegate = LazyBookmarkFolderMenuDelegate(children: childViewModels)
                childDelegates.append(delegate) // retain delegate (NSMenu.delegate is weak)
                subMenu.delegate = delegate
                item.submenu = subMenu
            }
            menu.addItem(item)
        }
    }
}

final class MainMenu: NSMenu {

    enum Constants {
        static let maxTitleLength = 55
    }

    // MARK: DuckDuckGo
    let servicesMenu = NSMenu(title: UserText.mainMenuAppServices)
    let preferencesMenuItem = NSMenuItem(title: UserText.mainMenuAppPreferences, action: #selector(AppDelegate.openPreferences), keyEquivalent: ",").withAccessibilityIdentifier("MainMenu.preferencesMenuItem")
        .withImage(DesignSystemImages.Glyphs.Size12.settings)

    // MARK: File
    let newWindowMenuItem = NSMenuItem(title: UserText.newWindowMenuItem, action: #selector(AppDelegate.newWindow), keyEquivalent: "")
        .withImage(DesignSystemImages.Glyphs.Size12.windowNew)
    let newBurnerWindowMenuItem = NSMenuItem(title: UserText.newBurnerWindowMenuItem, action: #selector(AppDelegate.newBurnerWindow), keyEquivalent: "")
        .withImage(DesignSystemImages.Glyphs.Size12.fireWindow)
    let newTabMenuItem = NSMenuItem(title: UserText.mainMenuFileNewTab, action: #selector(AppDelegate.newTab), keyEquivalent: "t")
        .withImage(DesignSystemImages.Glyphs.Size12.tabNew)
    let openLocationMenuItem = NSMenuItem(title: UserText.mainMenuFileOpenLocation, action: #selector(AppDelegate.openLocation), keyEquivalent: "l")
        .withImage(DesignSystemImages.Glyphs.Size12.arrowUpRight)
    let openFileMenuItem = NSMenuItem(title: UserText.mainMenuFileOpenFile, action: #selector(AppDelegate.openFile), keyEquivalent: "o")
        .withImage(DesignSystemImages.Glyphs.Size12.folder)
    let closeWindowMenuItem = NSMenuItem(title: UserText.mainMenuFileCloseWindow, action: #selector(NSWindow.performClose), keyEquivalent: "W")
        .withImage(DesignSystemImages.Glyphs.Size12.close)
    let closeAllWindowsMenuItem = NSMenuItem(title: UserText.mainMenuFileCloseAllWindows, action: #selector(AppDelegate.closeAllWindows), keyEquivalent: [.option, .command, "W"])
    let closeTabMenuItem = NSMenuItem(title: UserText.closeTab, action: #selector(MainViewController.closeTab), keyEquivalent: "w")
    let importBrowserDataMenuItem = NSMenuItem(title: UserText.mainMenuFileImportBookmarksandPasswords, action: #selector(AppDelegate.openImportBrowserDataWindow))
        .withImage(DesignSystemImages.Glyphs.Size12.import)
    let newAIChatFileMenuItem = NSMenuItem(title: UserText.newAIChatMenuItem, action: #selector(AppDelegate.newAIChat), keyEquivalent: "")

    @MainActor
    lazy var sharingMenu = SharingMenu(title: UserText.shareMenuItem, location: .mainMenu, delegate: self)

    // MARK: View
    let stopMenuItem = NSMenuItem(title: UserText.mainMenuViewStop, action: #selector(MainViewController.stopLoadingPage), keyEquivalent: ".")
        .withImage(DesignSystemImages.Glyphs.Size12.close)
    let reloadMenuItem = NSMenuItem(title: UserText.mainMenuViewReloadPage, action: #selector(MainViewController.reloadPage), keyEquivalent: "r")
        .withImage(DesignSystemImages.Glyphs.Size12.reloadSmall)

    let toggleFullscreenMenuItem = NSMenuItem(title: UserText.mainMenuViewEnterFullScreen, action: #selector(NSWindow.toggleFullScreen), keyEquivalent: [.control, .command, "f"])
    let actualSizeMenuItem = NSMenuItem(title: UserText.mainMenuViewActualSize, action: #selector(MainViewController.actualSize), keyEquivalent: "0")
        .withImage(DesignSystemImages.Glyphs.Size12.zoomActualSize)
    let zoomInMenuItem = NSMenuItem(title: UserText.mainMenuViewZoomIn, action: #selector(MainViewController.zoomIn), keyEquivalent: "+")
        .withImage(DesignSystemImages.Glyphs.Size12.zoomIn)
    let zoomOutMenuItem = NSMenuItem(title: UserText.mainMenuViewZoomOut, action: #selector(MainViewController.zoomOut), keyEquivalent: "-")
        .withImage(DesignSystemImages.Glyphs.Size12.zoomOut)

    // MARK: History
    @MainActor
    let historyMenu: HistoryMenu

    @MainActor
    var backMenuItem: NSMenuItem { historyMenu.backMenuItem }
    @MainActor
    var forwardMenuItem: NSMenuItem { historyMenu.forwardMenuItem }

    // MARK: Bookmarks
    let manageBookmarksMenuItem = NSMenuItem(title: UserText.mainMenuHistoryManageBookmarks, action: #selector(MainViewController.showManageBookmarks), keyEquivalent: [.command, .option, "b"])
        .withAccessibilityIdentifier("MainMenu.manageBookmarksMenuItem")
        .withImage(DesignSystemImages.Glyphs.Size12.bookmarks)
    var bookmarksMenuToggleBookmarksBarMenuItem = NSMenuItem(title: "BookmarksBarMenuPlaceholder", action: #selector(MainViewController.toggleBookmarksBarFromMenu), keyEquivalent: "B")
    let importBookmarksMenuItem = NSMenuItem(title: UserText.importBookmarks, action: #selector(AppDelegate.openImportBookmarksWindow))
        .withImage(DesignSystemImages.Glyphs.Size12.import)
    let bookmarksMenu = NSMenu(title: UserText.bookmarks)
    let favoritesMenu = NSMenu(title: UserText.favorites)

    private var toggleBookmarksBarMenuItem = NSMenuItem(title: "BookmarksBarMenuPlaceholder", action: #selector(MainViewController.toggleBookmarksBarFromMenu), keyEquivalent: "B")
    private let duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging
    private let duckAIChromeButtonsSeparatorMenuItem = NSMenuItem.separator()
    private let toggleDuckAIChromeButtonMenuItem = NSMenuItem(
        title: UserText.aiChatChromeHideDuckAIButton,
        action: #selector(MainViewController.toggleDuckAIChromeButtonVisibility(_:)),
        keyEquivalent: "Y"
    )
    private let toggleDuckAIChromeSidebarButtonMenuItem = NSMenuItem(
        title: UserText.aiChatChromeHideSidebarButton,
        action: #selector(MainViewController.toggleDuckAIChromeSidebarButtonVisibility(_:)),
        keyEquivalent: "U"
    )
    private let toggleDuckAISidebarMenuItem = NSMenuItem(
        title: UserText.aiChatShowSidebar,
        action: #selector(MainViewController.toggleDuckAISidebar(_:)),
        keyEquivalent: [.option, .command, "l"]
    )
    private let toggleDuckAISidebarSeparatorMenuItem = NSMenuItem.separator()

    var homeButtonMenuItem = NSMenuItem(title: "HomeButtonPlaceholder")
    var showTabsAndBookmarksBarOnFullScreenMenuItem = NSMenuItem(title: "ShowTabsAndBookmarksBarOnFullScreenMenuItem")
    let toggleShareShortcutMenuItem = NSMenuItem(title: UserText.shareMenuItem, action: #selector(MainViewController.toggleShareShortcut), keyEquivalent: "")
        .withImage(DesignSystemImages.Glyphs.Size12.shareApple)
    let toggleDownloadsShortcutMenuItem = NSMenuItem(title: UserText.mainMenuViewShowDownloadsShortcut, action: #selector(MainViewController.toggleDownloadsShortcut), keyEquivalent: "J")
        .withImage(DesignSystemImages.Glyphs.Size12.download)
    let toggleAutofillShortcutMenuItem = NSMenuItem(title: UserText.mainMenuViewShowAutofillShortcut, action: #selector(MainViewController.toggleAutofillShortcut), keyEquivalent: "A")
        .withImage(DesignSystemImages.Glyphs.Size12.keyLogin)
    let toggleBookmarksShortcutMenuItem = NSMenuItem(title: UserText.mainMenuViewShowBookmarksShortcut, action: #selector(MainViewController.toggleBookmarksShortcut), keyEquivalent: "K")
        .withImage(DesignSystemImages.Glyphs.Size12.bookmarks)
    private(set) lazy var aiChatMenu: NSMenuItem = MainActor.assumeMainThread {
        let container = NSMenuItem(title: "Duck.ai")
        container.submenu = makeAIChatMenu()
        return container
    }
    let toggleNetworkProtectionShortcutMenuItem = NSMenuItem(title: UserText.showNetworkProtectionShortcut, action: #selector(MainViewController.toggleNetworkProtectionShortcut), keyEquivalent: "")
        .withImage(DesignSystemImages.Glyphs.Size12.vpnUnlock)

    // MARK: Window
    let windowsMenu = NSMenu(title: UserText.mainMenuWindow)

    // MARK: Debug

    private var loggingMenu: NSMenu?
    let customConfigurationUrlMenuItem = NSMenuItem(title: "Last Update Time", action: nil)
    let configurationDateAndTimeMenuItem = NSMenuItem(title: "Configuration URL", action: nil)
    let autofillDebugScriptMenuItem = NSMenuItem(title: "Autofill Debug Script", action: #selector(MainMenu.toggleAutofillScriptDebugSettingsAction))
    let contentScopeDebugStateMenuItem = NSMenuItem(title: "Content Scope Scripts Debug State", action: #selector(MainMenu.toggleContentScopeStateDebugSettingsAction))
    let toggleWatchdogMenuItem = NSMenuItem(title: "Toggle Hang Watchdog", action: #selector(MainViewController.toggleWatchdog))
    let alwaysShowFirstTimeQuitSurvey = NSMenuItem(title: "Always Show First-Time Quit Survey", action: #selector(MainViewController.alwaysShowFirstTimeQuitSurvey))
    let shiftNextStepsDaysMenuItem = NSMenuItem(title: "Shift maximum Next Steps demonstration days", action: #selector(MainViewController.debugShiftNewTabOpeningDateNtimes))

    // MARK: Help

    let helpMenu = NSMenu(title: UserText.mainMenuHelp)
    let aboutMenuItem = NSMenuItem(title: UserText.about, action: #selector(AppDelegate.showAbout))
        .withImage(DesignSystemImages.Glyphs.Size12.info)
    let addToDockMenuItem = NSMenuItem(title: UserText.addDuckDuckGoToDock, action: #selector(AppDelegate.addToDock))
        .withImage(DesignSystemImages.Glyphs.Size12.addToTaskbar)
    let setAsDefaultMenuItem = NSMenuItem(title: UserText.setAsDefaultBrowser + "…", action: #selector(AppDelegate.setAsDefault))
        .withImage(DesignSystemImages.Glyphs.Size12.browserDefault)
    let releaseNotesMenuItem = NSMenuItem(title: UserText.releaseNotesMenuItem, action: #selector(AppDelegate.showReleaseNotes))
        .withImage(DesignSystemImages.Glyphs.Size12.note)
    let whatIsNewMenuItem = NSMenuItem(title: UserText.whatsNewMenuItem, action: #selector(AppDelegate.showWhatIsNew))
        .withImage(DesignSystemImages.Glyphs.Size12.news)

    let sendFeedbackMenuItem = NSMenuItem(title: UserText.sendFeedback, action: #selector(AppDelegate.openFeedback))
        .withImage(DesignSystemImages.Glyphs.Size12.feedback)

    let appAboutDDGMenuItem = NSMenuItem(title: UserText.aboutDuckDuckGo, action: #selector(AppDelegate.openAbout))
        .withImage(DesignSystemImages.Glyphs.Size12.info)

    private let featureFlagger: FeatureFlagger
    private let isLazyMenuRebuild: Bool
    private let dockCustomizer: DockCustomization
    private let defaultBrowserPreferences: DefaultBrowserPreferences
    private let aiChatMenuConfig: AIChatMenuVisibilityConfigurable
    private let aiChatSuggestionsReader: AIChatSuggestionsReading
    private let aiChatHistoryCleaner: AIChatHistoryCleaning
    private let internalUserDecider: InternalUserDecider
    private let appearancePreferences: AppearancePreferences
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let appVersion: AppVersion
    private let configurationURLProvider: CustomConfigurationURLProviding
    private let contentScopePreferences: ContentScopePreferences
    private let quitSurveyPersistor: QuitSurveyPersistor
    private let pinningManager: PinningManager
    private let subscriptionManager: any SubscriptionManager

    private var webExtensionsMenuItem: NSMenuItem?

    // MARK: - Initialization

    @MainActor
    init(featureFlagger: FeatureFlagger,
         bookmarkManager: BookmarkManager,
         historyCoordinator: HistoryCoordinating & HistoryGroupingDataSource,
         recentlyClosedCoordinator: RecentlyClosedCoordinating,
         faviconManager: FaviconManagement,
         dockCustomizer: DockCustomization,
         defaultBrowserPreferences: DefaultBrowserPreferences,
         aiChatMenuConfig: AIChatMenuVisibilityConfigurable,
         aiChatSuggestionsReader: AIChatSuggestionsReading,
         aiChatHistoryCleaner: AIChatHistoryCleaning,
         internalUserDecider: InternalUserDecider,
         appearancePreferences: AppearancePreferences,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         appVersion: AppVersion = .shared,
         isFireWindowDefault: Bool,
         configurationURLProvider: CustomConfigurationURLProviding,
         contentScopePreferences: ContentScopePreferences,
         quitSurveyPersistor: QuitSurveyPersistor,
         pinningManager: PinningManager,
         subscriptionManager: any SubscriptionManager,
         duckAIChromeButtonsVisibilityManager: DuckAIChromeButtonsVisibilityManaging = LocalDuckAIChromeButtonsVisibilityManager()) {

        self.featureFlagger = featureFlagger
        self.isLazyMenuRebuild = featureFlagger.isFeatureOn(.lazyMenuRebuild)
        self.internalUserDecider = internalUserDecider
        self.appearancePreferences = appearancePreferences
        self.privacyConfigurationManager = privacyConfigurationManager
        self.appVersion = appVersion
        self.dockCustomizer = dockCustomizer
        self.defaultBrowserPreferences = defaultBrowserPreferences
        self.aiChatMenuConfig = aiChatMenuConfig
        self.aiChatSuggestionsReader = aiChatSuggestionsReader
        self.aiChatHistoryCleaner = aiChatHistoryCleaner
        self.historyMenu = HistoryMenu(historyGroupingDataSource: historyCoordinator, recentlyClosedCoordinator: recentlyClosedCoordinator, featureFlagger: featureFlagger)
        self.configurationURLProvider = configurationURLProvider
        self.contentScopePreferences = contentScopePreferences
        self.quitSurveyPersistor = quitSurveyPersistor
        self.pinningManager = pinningManager
        self.subscriptionManager = subscriptionManager
        self.duckAIChromeButtonsVisibilityManager = duckAIChromeButtonsVisibilityManager
        super.init(title: UserText.duckDuckGo)

        buildItems {
            buildDuckDuckGoMenu()
            buildFileMenu(isFireWindowDefault: isFireWindowDefault)
            buildEditMenu()
            buildViewMenu()
            buildHistoryMenu()
            aiChatMenu
            buildBookmarksMenu()
            buildWindowMenu()
            buildDebugMenu(featureFlagger: featureFlagger, historyCoordinator: historyCoordinator)
            buildHelpMenu()
        }

        subscribeToBookmarkList(bookmarkManager: bookmarkManager)
        subscribeToFavicons(faviconManager: faviconManager)

        if isLazyMenuRebuild {
            bookmarksMenu.delegate = self
            favoritesMenu.delegate = self
        }

        setupAIChatMenu()
        subscribeToAIChatPreferences(aiChatMenuConfig: aiChatMenuConfig)
    }

    func buildDuckDuckGoMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.duckDuckGo) {
            appAboutDDGMenuItem

            NSMenuItem.separator()

            preferencesMenuItem
            addToDockMenuItem
            setAsDefaultMenuItem

            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuAppServices)
                .submenu(servicesMenu)
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuAppCheckforUpdates, action: #selector(AppDelegate.checkForUpdates))
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuAppHideDuckDuckGo, action: #selector(NSApplication.hide), keyEquivalent: "h")
            NSMenuItem(title: UserText.mainMenuAppHideOthers, action: #selector(NSApplication.hideOtherApplications), keyEquivalent: [.option, .command, "h"])
            NSMenuItem(title: UserText.mainMenuAppShowAll, action: #selector(NSApplication.unhideAllApplications))
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuAppQuitDuckDuckGo, action: #selector(NSApplication.terminate), keyEquivalent: "q")
        }
    }

    @MainActor
    func buildFileMenu(isFireWindowDefault: Bool) -> NSMenuItem {
        updateMenuShortcutsFor(isFireWindowDefault)

        return NSMenuItem(title: UserText.mainMenuFile) {
            newTabMenuItem

            if isFireWindowDefault {
                newBurnerWindowMenuItem
                newWindowMenuItem
            } else {
                newWindowMenuItem
                newBurnerWindowMenuItem
            }

            newAIChatFileMenuItem
            NSMenuItem.separator()

            openFileMenuItem
            openLocationMenuItem
            NSMenuItem.separator()

            closeWindowMenuItem
            closeAllWindowsMenuItem
            closeTabMenuItem
            NSMenuItem(title: UserText.mainMenuFileSaveAs, action: #selector(MainViewController.saveAs), keyEquivalent: "s")
                .withImage(DesignSystemImages.Glyphs.Size12.save)
            NSMenuItem.separator()

            importBrowserDataMenuItem
            NSMenuItem(title: UserText.mainMenuFileExport) {
                NSMenuItem(title: UserText.mainMenuFileExportPasswords, action: #selector(AppDelegate.openExportLogins))
                NSMenuItem(title: UserText.mainMenuFileExportBookmarks, action: #selector(AppDelegate.openExportBookmarks))
            }
            .withImage(DesignSystemImages.Glyphs.Size12.export)
            NSMenuItem.separator()

            NSMenuItem(title: UserText.shareMenuItem)
                .submenu(sharingMenu)
                .withImage(DesignSystemImages.Glyphs.Size12.shareApple)
            NSMenuItem.separator()

            NSMenuItem(title: UserText.printMenuItem, action: #selector(MainViewController.printWebView), keyEquivalent: "p")
                .withImage(DesignSystemImages.Glyphs.Size12.print)
        }
    }

    func buildEditMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.mainMenuEdit) {
            NSMenuItem(title: UserText.mainMenuEditUndo, action: Selector(("undo:")), keyEquivalent: "z")
            NSMenuItem(title: UserText.mainMenuEditRedo, action: Selector(("redo:")), keyEquivalent: "Z")
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuEditCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            NSMenuItem(title: UserText.mainMenuEditCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            NSMenuItem(title: UserText.mainMenuEditPaste, action: #selector(NSText.paste), keyEquivalent: "v")
            NSMenuItem(title: UserText.mainMenuEditPasteAndMatchStyle, action: #selector(NSTextView.pasteAsPlainText), keyEquivalent: [.option, .command, .shift, "v"])
            NSMenuItem(title: UserText.mainMenuEditPasteAndMatchStyle, action: #selector(NSTextView.pasteAsPlainText), keyEquivalent: [.command, .shift, "v"])
                .alternate()

            NSMenuItem(title: UserText.mainMenuEditDelete, action: #selector(NSText.delete))
            NSMenuItem(title: UserText.mainMenuEditSelectAll, action: #selector(NSText.selectAll), keyEquivalent: "a")

            NSMenuItem(title: "", action: #selector(MainViewController.summarize), keyEquivalent: [.command, .shift, "\r"])
                .hidden()
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuEditFind) {
                NSMenuItem(title: UserText.findInPageMenuItem, action: #selector(MainViewController.findInPage), keyEquivalent: "f").withAccessibilityIdentifier("MainMenu.findInPage")
                NSMenuItem(title: UserText.mainMenuEditFindFindNext, action: #selector(MainViewController.findInPageNext), keyEquivalent: "g").withAccessibilityIdentifier("MainMenu.findNext")
                NSMenuItem(title: UserText.mainMenuEditFindFindPrevious, action: #selector(MainViewController.findInPagePrevious), keyEquivalent: "G").withAccessibilityIdentifier("MainMenu.findPrevious")
                NSMenuItem.separator()

                NSMenuItem(title: UserText.mainMenuEditFindHideFind, action: #selector(MainViewController.findInPageDone), keyEquivalent: "F").withAccessibilityIdentifier("MainMenu.findInPageDone")
            }

            NSMenuItem(title: UserText.mainMenuEditSpellingandGrammar) {
                NSMenuItem(title: UserText.mainMenuEditSpellingandShowSpellingandGrammar, action: #selector(NSText.showGuessPanel), keyEquivalent: ":")
                NSMenuItem(title: UserText.mainMenuEditSpellingandCheckDocumentNow, action: #selector(NSText.checkSpelling), keyEquivalent: ";")
                NSMenuItem.separator()

                NSMenuItem(title: UserText.mainMenuEditSpellingandCheckSpellingWhileTyping, action: #selector(NSTextView.toggleContinuousSpellChecking))
                NSMenuItem(title: UserText.mainMenuEditSpellingandCheckGrammarWithSpelling, action: #selector(NSTextView.toggleGrammarChecking))
                NSMenuItem(title: UserText.mainMenuEditSpellingandCorrectSpellingAutomatically, action: #selector(NSTextView.toggleAutomaticSpellingCorrection))
                    .hidden()
            }

            NSMenuItem(title: UserText.mainMenuEditSubstitutions) {
                NSMenuItem(title: UserText.mainMenuEditSubstitutionsShowSubstitutions, action: #selector(NSTextView.orderFrontSubstitutionsPanel))
                NSMenuItem.separator()

                NSMenuItem(title: UserText.mainMenuEditSubstitutionsSmartCopyPaste, action: #selector(NSTextView.toggleSmartInsertDelete))
                NSMenuItem(title: UserText.mainMenuEditSubstitutionsSmartQuotes, action: #selector(NSTextView.toggleAutomaticQuoteSubstitution))
                NSMenuItem(title: UserText.mainMenuEditSubstitutionsSmartDashes, action: #selector(NSTextView.toggleAutomaticDashSubstitution))
                NSMenuItem(title: UserText.mainMenuEditSubstitutionsSmartLinks, action: #selector(NSTextView.toggleAutomaticLinkDetection))
                NSMenuItem(title: UserText.mainMenuEditSubstitutionsDataDetectors, action: #selector(NSTextView.toggleAutomaticDataDetection))
                NSMenuItem(title: UserText.mainMenuEditSubstitutionsTextReplacement, action: #selector(NSTextView.toggleAutomaticTextReplacement))
            }

            NSMenuItem(title: UserText.mainMenuEditTransformations) {
                NSMenuItem(title: UserText.mainMenuEditTransformationsMakeUpperCase, action: #selector(NSResponder.uppercaseWord))
                NSMenuItem(title: UserText.mainMenuEditTransformationsMakeLowerCase, action: #selector(NSResponder.lowercaseWord))
                NSMenuItem(title: UserText.mainMenuEditTransformationsCapitalize, action: #selector(NSResponder.capitalizeWord))
            }

            NSMenuItem(title: UserText.mainMenuEditSpeech) {
                NSMenuItem(title: UserText.mainMenuEditSpeechStartSpeaking, action: #selector(NSTextView.startSpeaking))
                NSMenuItem(title: UserText.mainMenuEditSpeechStopSpeaking, action: #selector(NSTextView.stopSpeaking))
            }
        }
    }

    func buildViewMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.mainMenuView) {
            stopMenuItem
            reloadMenuItem
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuViewHome, action: #selector(MainViewController.home), keyEquivalent: "H")
                .withImage(DesignSystemImages.Glyphs.Size12.home)
            NSMenuItem.separator()

            toggleDuckAISidebarMenuItem
            toggleDuckAISidebarSeparatorMenuItem
            toggleDuckAIChromeButtonMenuItem
            toggleDuckAIChromeSidebarButtonMenuItem
            duckAIChromeButtonsSeparatorMenuItem

            showTabsAndBookmarksBarOnFullScreenMenuItem

            toggleBookmarksBarMenuItem

            NSMenuItem(title: UserText.openDownloads, action: #selector(MainViewController.toggleDownloads), keyEquivalent: "j")
                .withImage(DesignSystemImages.Glyphs.Size12.download)
            NSMenuItem.separator()

            homeButtonMenuItem
            toggleShareShortcutMenuItem
            toggleDownloadsShortcutMenuItem
            toggleAutofillShortcutMenuItem
            toggleBookmarksShortcutMenuItem

            toggleNetworkProtectionShortcutMenuItem

            NSMenuItem.separator()

            toggleFullscreenMenuItem
            NSMenuItem.separator()

            zoomInMenuItem
            zoomOutMenuItem
            actualSizeMenuItem
            NSMenuItem.separator()

            NSMenuItem(title: UserText.mainMenuDeveloper) {
                NSMenuItem(title: UserText.openDeveloperTools, action: #selector(MainViewController.toggleDeveloperTools), keyEquivalent: [.option, .command, "i"])
                NSMenuItem(title: UserText.mainMenuViewDeveloperJavaScriptConsole, action: #selector(MainViewController.openJavaScriptConsole), keyEquivalent: [.option, .command, "c"])
                NSMenuItem(title: UserText.mainMenuViewDeveloperShowPageSource, action: #selector(MainViewController.showPageSource), keyEquivalent: [.option, .command, "u"])
                NSMenuItem(title: UserText.mainMenuViewDeveloperShowResources, action: #selector(MainViewController.showPageResources), keyEquivalent: [.option, .command, "a"])
            }
        }
    }

    @MainActor
    func buildHistoryMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.mainMenuHistory)
            .submenu(historyMenu)
    }

    func buildBookmarksMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.bookmarks)
            .withAccessibilityIdentifier("MainMenu.bookmarks")
            .submenu(bookmarksMenu.buildItems {
                NSMenuItem(title: UserText.bookmarkThisPage, action: #selector(MainViewController.bookmarkThisPage), keyEquivalent: "d")
                    .withAccessibilityIdentifier("MainMenu.addBookmark")
                    .withImage(DesignSystemImages.Glyphs.Size12.bookmarkAdd)
                NSMenuItem(title: UserText.bookmarkAllTabs, action: #selector(MainViewController.bookmarkAllOpenTabs), keyEquivalent: [.command, .shift, "d"])
                manageBookmarksMenuItem
                bookmarksMenuToggleBookmarksBarMenuItem
                NSMenuItem.separator()

                importBookmarksMenuItem
                NSMenuItem(title: UserText.exportBookmarks, action: #selector(AppDelegate.openExportBookmarks))
                    .withImage(DesignSystemImages.Glyphs.Size12.export)
                NSMenuItem.separator()

                NSMenuItem(title: UserText.favorites)
                    .submenu(favoritesMenu.buildItems {
                        NSMenuItem(title: UserText.mainMenuHistoryFavoriteThisPage, action: #selector(MainViewController.favoriteThisPage))
                            .withImage(DesignSystemImages.Glyphs.Size12.favorite)
                            .withAccessibilityIdentifier("MainMenu.favoriteThisPage")
                        NSMenuItem.separator()
                    })
                    .withImage(DesignSystemImages.Glyphs.Size12.favorite)

                NSMenuItem.separator()
            })
    }

    func buildWindowMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.mainMenuWindow)
            .submenu(windowsMenu.buildItems {
                NSMenuItem(title: UserText.mainMenuWindowMinimize, action: #selector(NSWindow.performMiniaturize), keyEquivalent: "m")
                NSMenuItem(title: UserText.zoom, action: #selector(NSWindow.performZoom))
                NSMenuItem.separator()

                NSMenuItem(title: UserText.newTabToTheRight, action: #selector(MainViewController.newTabNextToActive))
                    .withImage(DesignSystemImages.Glyphs.Size12.tabNew)
                NSMenuItem(title: UserText.duplicateTab, action: #selector(MainViewController.duplicateTab))
                    .withImage(DesignSystemImages.Glyphs.Size12.windowDuplicate)
                NSMenuItem(title: UserText.pinTab, action: #selector(MainViewController.pinOrUnpinTab))
                    .withImage(DesignSystemImages.Glyphs.Size12.pin)
                NSMenuItem(title: UserText.moveTabToNewWindow, action: #selector(MainViewController.moveTabToNewWindow))
                NSMenuItem(title: UserText.mainMenuWindowMergeAllWindows, action: #selector(NSWindow.mergeAllWindows))
                NSMenuItem.separator()

                NSMenuItem(title: UserText.mainMenuWindowShowPreviousTab, action: #selector(MainViewController.showPreviousTab), keyEquivalent: [.control, .shift, .tab])
                NSMenuItem(title: "Show Previous Tab (Hidden)", action: #selector(MainViewController.showPreviousTab), keyEquivalent: [.command, .shift, "["])
                    .hidden()
                NSMenuItem(title: "Show Previous Tab (Hidden)", action: #selector(MainViewController.showPreviousTab), keyEquivalent: [.option, .command, .left])
                    .hidden()

                NSMenuItem(title: UserText.mainMenuWindowShowNextTab, action: #selector(MainViewController.showNextTab), keyEquivalent: [.control, .tab])
                NSMenuItem(title: "Show Next Tab (Hidden)", action: #selector(MainViewController.showNextTab), keyEquivalent: [.command, .shift, "]"])
                    .hidden()
                NSMenuItem(title: "Show Next Tab (Hidden)", action: #selector(MainViewController.showNextTab), keyEquivalent: [.option, .command, .right])
                    .hidden()

                NSMenuItem(title: "Show First Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "1")
                    .hidden()
                NSMenuItem(title: "Show Second Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "2")
                    .hidden()
                NSMenuItem(title: "Show Third Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "3")
                    .hidden()
                NSMenuItem(title: "Show Fourth Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "4")
                    .hidden()
                NSMenuItem(title: "Show Fifth Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "5")
                    .hidden()
                NSMenuItem(title: "Show Sixth Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "6")
                    .hidden()
                NSMenuItem(title: "Show Seventh Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "7")
                    .hidden()
                NSMenuItem(title: "Show Eighth Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "8")
                    .hidden()
                NSMenuItem(title: "Show Ninth Tab (Hidden)", action: #selector(MainViewController.showTab), keyEquivalent: "9")
                    .hidden()
                NSMenuItem.separator()

                NSMenuItem(title: UserText.mainMenuWindowBringAllToFront, action: #selector(NSApplication.arrangeInFront))
            })
    }

    @MainActor
    func buildDebugMenu(featureFlagger: FeatureFlagger, historyCoordinator: HistoryCoordinating) -> NSMenuItem? {
        let buildType = StandardApplicationBuildType()
        guard buildType.isDebugBuild || buildType.isReviewBuild || buildType.isAlphaBuild || internalUserDecider.isInternalUser else { return nil }
        return NSMenuItem(title: "Debug")
            .withAccessibilityIdentifier(AccessibilityIdentifiers.debugMenu)
            .submenu(setupDebugMenu(featureFlagger: featureFlagger, historyCoordinator: historyCoordinator))
    }

    func buildHelpMenu() -> NSMenuItem {
        NSMenuItem(title: UserText.mainMenuHelp)
            .submenu(helpMenu.buildItems {
                NSMenuItem(title: UserText.mainMenuHelpDuckDuckGoHelp, action: #selector(NSApplication.showHelp), keyEquivalent: "?")
                    .hidden()

                NSMenuItem.separator()

                aboutMenuItem
                if StandardApplicationBuildType().isSparkleBuild {
                    releaseNotesMenuItem
                    whatIsNewMenuItem
                }
                sendFeedbackMenuItem
            })
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    @MainActor
    override func update() {
        super.update()

        addToDockMenuItem.isHidden = !dockCustomizer.supportsAddingToDock || dockCustomizer.isAddedToDock
        setAsDefaultMenuItem.isHidden = defaultBrowserPreferences.isDefault

        // To be safe, hide the NetP shortcut menu item by default.
        toggleNetworkProtectionShortcutMenuItem.isHidden = true

        updateAppAboutDDGMenuItem()
        updateHomeButtonMenuItem()
        updateBookmarksBarMenuItem()
        updateShortcutMenuItems()
        updateInternalUserItem()
        updateRemoteConfigurationInfo()
        updateAutofillDebugScriptMenuItem()
        updateContentScopeDebugStateMenuItem()
        updateShiftNextStepsDaysMenuItem()
        updateShowToolbarsOnFullScreenMenuItem()
        updateWatchdogMenuItems()
        updateWebExtensionsMenuItem()
        updateAlwaysShowFirstTimeQuitSurvey()
        updateDuckAIChromeButtonMenuItems()

        alignItemTextWithIconsRecursively()
    }

    private func updateAlwaysShowFirstTimeQuitSurvey() {
        alwaysShowFirstTimeQuitSurvey.state = quitSurveyPersistor.alwaysShowQuitSurvey ? .on : .off
    }

    private func updateWebExtensionsMenuItem() {
        guard let debugMenuItem = items.first(where: { item in item.title == Self.debugMenuTitle }),
              let debugSubmenu = debugMenuItem.submenu else {
            return
        }

        if #available(macOS 15.4, *) {
            if let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
                if webExtensionsMenuItem == nil {
                    webExtensionsMenuItem = NSMenuItem(title: "Web Extensions")
                        .submenu(WebExtensionsDebugMenu(webExtensionManager: webExtensionManager))
                }
                if let webExtensionsMenuItem, webExtensionsMenuItem.parent == nil {
                    debugSubmenu.insertItem(webExtensionsMenuItem, at: max(0, debugSubmenu.items.count - 3))
                }
            } else {
                if let webExtensionsMenuItem {
                    debugSubmenu.removeItem(webExtensionsMenuItem)
                    self.webExtensionsMenuItem = nil
                }
            }
        }
    }

    private func updateAppAboutDDGMenuItem() {
        if internalUserDecider.isInternalUser {
            appAboutDDGMenuItem.title = "\(UserText.aboutDuckDuckGo) (version: \(AppVersionModel().versionLabelShort))"
        } else {
            appAboutDDGMenuItem.title = UserText.aboutDuckDuckGo
        }
    }

    // MARK: - Bookmarks

    private(set) var pendingFavoriteViewModels: [BookmarkViewModel] = []
    private(set) var pendingTopLevelViewModels: [BookmarkViewModel] = []
    private(set) var bookmarksMenuNeedsRebuild = false
    private(set) var bookmarkFaviconsNeedUpdate = false
    private var folderDelegates: [LazyBookmarkFolderMenuDelegate] = []

    var faviconsCancellable: AnyCancellable?
    var faviconsCacheUpdateCancellable: AnyCancellable?
    @MainActor
    private func subscribeToFavicons(faviconManager: FaviconManagement) {
        faviconsCancellable = faviconManager.faviconsLoadedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loaded in
                guard let self, loaded else { return }
                self.bookmarkFaviconsNeedUpdate = true
            }

        // `faviconsLoadedPublisher` fires when favicon metadata loads, before the
        // images are decoded. Favicon images become available lazily and post
        // `.faviconCacheUpdated`, so also refresh the menus on that notification.
        faviconsCacheUpdateCancellable = NotificationCenter.default.publisher(for: .faviconCacheUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.bookmarkFaviconsNeedUpdate = true
            }
    }

    @MainActor
    private func updateFavicons(in menu: NSMenu) {
        for menuItem in menu.items {
            if let bookmark = menuItem.representedObject as? Bookmark {
                menuItem.image = BookmarkViewModel(entity: bookmark).menuFavicon
            }
            if let submenu = menuItem.submenu {
                updateFavicons(in: submenu)
            }
        }
    }

    var bookmarkListCancellable: AnyCancellable?
    private func subscribeToBookmarkList(bookmarkManager: BookmarkManager) {
        bookmarkListCancellable = bookmarkManager.listPublisher
            .compactMap {
                let favorites = $0?.favoriteBookmarks.compactMap(BookmarkViewModel.init(entity:)) ?? []
                let topLevelEntities = $0?.topLevelEntities.compactMap(BookmarkViewModel.init(entity:)) ?? []

                return (favorites, topLevelEntities)
            }
            .sink { [weak self] favorites, topLevel in
                guard let self else { return }
                if self.isLazyMenuRebuild {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.pendingFavoriteViewModels = favorites
                        self.pendingTopLevelViewModels = topLevel
                        self.bookmarksMenuNeedsRebuild = true
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.updateBookmarksMenu(favoriteViewModels: favorites,
                                                  topLevelBookmarkViewModels: topLevel)
                    }
                }
            }
    }

    var aiChatCancellable: AnyCancellable?
    private func subscribeToAIChatPreferences(aiChatMenuConfig: AIChatMenuVisibilityConfigurable) {
        aiChatCancellable = aiChatMenuConfig.valuesChangedPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] in
                self?.setupAIChatMenu()
            })
    }

    // Nested recursing functions cause body length
    @MainActor
    func updateBookmarksMenu(favoriteViewModels: [BookmarkViewModel], topLevelBookmarkViewModels: [BookmarkViewModel]) {
        let isLazy = isLazyMenuRebuild
        if isLazy {
            folderDelegates.removeAll()
        }

        func bookmarkMenuItems(from bookmarkViewModels: [BookmarkViewModel], topLevel: Bool = true, isLazy: Bool, folderDelegates: inout [LazyBookmarkFolderMenuDelegate]) -> [NSMenuItem] {
            var menuItems = [NSMenuItem]()

            if !topLevel {
                let showOpenInTabsItem = bookmarkViewModels.compactMap { $0.entity as? Bookmark }.count > 1
                if showOpenInTabsItem {
                    menuItems.append(NSMenuItem(bookmarkViewModels: bookmarkViewModels))
                    menuItems.append(.separator())
                }
            }

            for viewModel in bookmarkViewModels {
                let menuItem = NSMenuItem(bookmarkViewModel: viewModel)

                if let folder = viewModel.entity as? BookmarkFolder {
                    let childViewModels = folder.children.map(BookmarkViewModel.init)
                    if isLazy {
                        if !childViewModels.isEmpty {
                            let subMenu = NSMenu(title: folder.title)
                            subMenu.addItem(NSMenuItem()) // placeholder
                            let delegate = LazyBookmarkFolderMenuDelegate(children: childViewModels)
                            subMenu.delegate = delegate
                            folderDelegates.append(delegate)
                            menuItem.submenu = subMenu
                        }
                    } else {
                        let subMenu = NSMenu(title: folder.title)
                        let childMenuItems = bookmarkMenuItems(from: childViewModels, topLevel: false, isLazy: false, folderDelegates: &folderDelegates)
                        subMenu.items = childMenuItems

                        if !subMenu.items.isEmpty {
                            menuItem.submenu = subMenu
                        }
                    }
                }

                menuItems.append(menuItem)
            }

            return menuItems
        }

        func favoriteMenuItems(from bookmarkViewModels: [BookmarkViewModel]) -> [NSMenuItem] {
            bookmarkViewModels
                .filter { ($0.entity as? Bookmark)?.isFavorite ?? false }
                .enumerated()
                .map { index, bookmarkViewModel in
                    let item = NSMenuItem(bookmarkViewModel: bookmarkViewModel)
                    if index < 9 {
                        item.keyEquivalentModifierMask = [.option, .command]
                        item.keyEquivalent = String(index + 1)
                    }
                    return item
                }
        }

        guard let favoritesSeparatorIndex = bookmarksMenu.items.lastIndex(where: { $0.isSeparatorItem }),
              let favoriteThisPageSeparatorIndex = favoritesMenu.items.lastIndex(where: { $0.isSeparatorItem }) else {
            assertionFailure("MainMenuManager: Failed to reference bookmarks menu items")
            return
        }

        let cleanedBookmarkItems = bookmarksMenu.items.dropLast(bookmarksMenu.items.count - (favoritesSeparatorIndex + 1))
        let bookmarkItems = bookmarkMenuItems(from: topLevelBookmarkViewModels, isLazy: isLazy, folderDelegates: &folderDelegates)
        bookmarksMenu.items = Array(cleanedBookmarkItems) + bookmarkItems

        let cleanedFavoriteItems = favoritesMenu.items.dropLast(favoritesMenu.items.count - (favoriteThisPageSeparatorIndex + 1))
        let favoriteItems = favoriteMenuItems(from: favoriteViewModels)
        favoritesMenu.items = Array(cleanedFavoriteItems) + favoriteItems
    }

    private func updateBookmarksBarMenuItem() {
        guard let toggleBookmarksBarMenuItem = BookmarksBarMenuFactory.replace(toggleBookmarksBarMenuItem, prefs: appearancePreferences),
              let bookmarksMenuToggleBookmarksBarMenuItem = BookmarksBarMenuFactory.replace(bookmarksMenuToggleBookmarksBarMenuItem, prefs: appearancePreferences) else {
            assertionFailure("Could not replace toggleBookmarksBarMenuItem")
            return
        }
        self.toggleBookmarksBarMenuItem = toggleBookmarksBarMenuItem
        toggleBookmarksBarMenuItem.action = #selector(MainViewController.toggleBookmarksBarFromMenu)
        toggleBookmarksBarMenuItem.setAccessibilityIdentifier("MainMenu.toggleBookmarksBar")

        self.bookmarksMenuToggleBookmarksBarMenuItem = bookmarksMenuToggleBookmarksBarMenuItem
        bookmarksMenuToggleBookmarksBarMenuItem.action = #selector(MainViewController.toggleBookmarksBarFromMenu)
    }

    private func updateHomeButtonMenuItem() {
        guard let homeButtonMenuItem = HomeButtonMenuFactory.replace(homeButtonMenuItem, prefs: appearancePreferences, pinningManager: pinningManager) else {
            assertionFailure("Could not replace HomeButtonMenuItem")
            return
        }
        self.homeButtonMenuItem = homeButtonMenuItem
    }

    private func updateShowToolbarsOnFullScreenMenuItem() {
        guard let showTabsAndBookmarksBarOnFullScreenMenuItem = ShowToolbarsOnFullScreenMenuCoordinator.replace(showTabsAndBookmarksBarOnFullScreenMenuItem, prefs: appearancePreferences) else {
            assertionFailure("Could not replace ShowTabsAndBookmarksBarOnFullScreenMenuItem")
            return
        }
        self.showTabsAndBookmarksBarOnFullScreenMenuItem = showTabsAndBookmarksBarOnFullScreenMenuItem
    }

    private func updateShortcutMenuItems() {
        Task { @MainActor in
            toggleAutofillShortcutMenuItem.title = pinningManager.shortcutTitle(for: .autofill)
            toggleBookmarksShortcutMenuItem.title = pinningManager.shortcutTitle(for: .bookmarks)
            toggleDownloadsShortcutMenuItem.title = pinningManager.shortcutTitle(for: .downloads)
            toggleShareShortcutMenuItem.title = pinningManager.shortcutTitle(for: .share)

            if DefaultVPNFeatureGatekeeper(vpnUninstaller: VPNUninstaller(pinningManager: pinningManager), subscriptionManager: subscriptionManager).isVPNVisible() {
                toggleNetworkProtectionShortcutMenuItem.isHidden = false
                toggleNetworkProtectionShortcutMenuItem.title = pinningManager.shortcutTitle(for: .networkProtection)
            } else {
                toggleNetworkProtectionShortcutMenuItem.isHidden = true
            }
        }
    }

    private func updateDuckAIChromeButtonMenuItems() {
        let shouldShowDuckAIChromeItems = featureFlagger.isFeatureOn(.aiChatChromeSidebar)
            && aiChatMenuConfig.shouldDisplayAnyAIChatFeature
        toggleDuckAISidebarMenuItem.isHidden = !shouldShowDuckAIChromeItems
        toggleDuckAISidebarSeparatorMenuItem.isHidden = !shouldShowDuckAIChromeItems
        toggleDuckAIChromeButtonMenuItem.isHidden = !shouldShowDuckAIChromeItems
        toggleDuckAIChromeSidebarButtonMenuItem.isHidden = !shouldShowDuckAIChromeItems
        duckAIChromeButtonsSeparatorMenuItem.isHidden = !shouldShowDuckAIChromeItems

        let isDuckAIButtonHidden = duckAIChromeButtonsVisibilityManager.isHidden(.duckAI)
        let isSidebarButtonHidden = duckAIChromeButtonsVisibilityManager.isHidden(.sidebar)
        toggleDuckAIChromeButtonMenuItem.title = isDuckAIButtonHidden ? UserText.aiChatChromeShowDuckAIButton : UserText.aiChatChromeHideDuckAIButton
        toggleDuckAIChromeSidebarButtonMenuItem.title = isSidebarButtonHidden ? UserText.aiChatChromeShowSidebarButton : UserText.aiChatChromeHideSidebarButton
    }

    // MARK: - Debug

    let internalUserItem = NSMenuItem(title: "Set Internal User State", action: #selector(AppDelegate.internalUserState))

    static let debugMenuTitle = "Debug"

    @MainActor
    private func setupDebugMenu(featureFlagger: FeatureFlagger, historyCoordinator: HistoryCoordinating) -> NSMenu {
        let debugMenu = NSMenu(title: Self.debugMenuTitle) {
            // Keep Feature Flag Overrides at top - will not be sorted
            NSMenuItem(title: "Feature Flag Overrides")
                .submenu(FeatureFlagOverridesMenu(featureFlagOverrides: featureFlagger))

            NSMenuItem.separator()

            // All items below will be automatically sorted alphabetically
            NSMenuItem(title: "Clear WebKit Cache", action: #selector(AppDelegate.debugClearWebViewCache)).withAccessibilityIdentifier("MainMenu.clearWebKitCache")
            NSMenuItem(title: "Inspect Favicons", action: #selector(MainViewController.inspectFavicons(_:))).withAccessibilityIdentifier("MainMenu.inspectFavicons")
            NSMenuItem(title: "Open Vanilla Browser", action: #selector(MainViewController.openVanillaBrowser)).withAccessibilityIdentifier("MainMenu.openVanillaBrowser")
            NSMenuItem(title: "Skip Onboarding", action: #selector(AppDelegate.skipOnboarding)).withAccessibilityIdentifier("MainMenu.skipOnboarding")
            NSMenuItem(title: "Performance Debugging") {
                NSMenuItem(title: "Export Allocation Stats", action: #selector(AppDelegate.exportMemoryAllocationStats), keyEquivalent: [.control, .command, .shift, .option, "m"])
                NSMenuItem(title: "Export Startup Stats", action: #selector(AppDelegate.exportStartupStats), keyEquivalent: [.control, .command, .shift, .option, "s"])
            }
            NSMenuItem(title: "New Tab Page") {
                NSMenuItem(title: "Reset Next Steps", action: #selector(AppDelegate.debugResetContinueSetup))
                    .withAccessibilityIdentifier(AccessibilityIdentifiers.NewTabPage.resetNextStepsMenuItem)
                NSMenuItem(title: "Shift top card by 10 impressions", action: #selector(MainViewController.debugShiftCardImpression))
                NSMenuItem(title: "Shift New Tab daily impression", action: #selector(MainViewController.debugShiftNewTabOpeningDate))
                shiftNextStepsDaysMenuItem
                    .withAccessibilityIdentifier(AccessibilityIdentifiers.NewTabPage.shiftMaxDaysMenuItem)
            }.withAccessibilityIdentifier(AccessibilityIdentifiers.NewTabPage.newTabPageDebugMenu)
            NSMenuItem(title: "CPM") {
                NSMenuItem(title: "Show feature awareness dialog for NTP widget", action: #selector(AppDelegate.debugShowFeatureAwarenessDialogForNTPWidget))
                NSMenuItem(title: "Increment Autoconsent Stats", action: #selector(AppDelegate.debugIncrementAutoconsentStats))
                NSMenuItem(title: "Clear blockedCookiesPopoverSeen flag", action: #selector(AppDelegate.debugClearBlockedCookiesPopoverSeenFlag))
                NSMenuItem(title: "Reset widgetNewLabelFirstShownDate", action: #selector(AppDelegate.debugResetWidgetNewLabelFirstShownDateKey))
                NSMenuItem(title: "Set widgetNewLabelFirstShownDate to 10 days ago", action: #selector(AppDelegate.debugSetWidgetNewLabelFirstShownDateTo10DaysAgo))
            }
            NSMenuItem(title: "History")
                .submenu(HistoryDebugMenu(historyCoordinator: historyCoordinator, featureFlagger: featureFlagger))
            NSMenuItem(title: "Performance Tests") {
                NSMenuItem(title: "Test Network Quality", action: #selector(MainViewController.testNetworkQuality))
                    .withAccessibilityIdentifier("MainMenu.testNetworkQuality")
                NSMenuItem(title: "Test Site Performance (DDG vs Safari)", action: #selector(MainViewController.testCurrentSitePerformance))
                    .withAccessibilityIdentifier("MainMenu.testCurrentSitePerformance")
            }
            NSMenuItem(title: "Content Scope Experiments")
                .submenu(ContentScopeExperimentsMenu())
            NSMenuItem(title: "Reset Data") {
                NSMenuItem(title: "Reset Default Grammar Checks", action: #selector(AppDelegate.resetDefaultGrammarChecks))
                NSMenuItem(title: "Reset Autofill Data", action: #selector(AppDelegate.resetSecureVaultData)).withAccessibilityIdentifier("MainMenu.resetSecureVaultData")
                NSMenuItem(title: "Reset Bookmarks", action: #selector(AppDelegate.resetBookmarks)).withAccessibilityIdentifier("MainMenu.resetBookmarks")
                NSMenuItem(title: "Reset Fireproof Sites", action: #selector(AppDelegate.resetFireproofSites))
                NSMenuItem(title: "Reset Pinned Tabs", action: #selector(AppDelegate.resetPinnedTabs))
                NSMenuItem(title: "Reset New Tab Page Customizations", action: #selector(AppDelegate.resetNewTabPageCustomization))
                NSMenuItem(title: "Reset YouTube Overlay Interactions", action: #selector(AppDelegate.resetDuckPlayerOverlayInteractions))
                NSMenuItem(title: "Reset MakeDuckDuckYours user settings", action: #selector(AppDelegate.resetMakeDuckDuckGoYoursUserSettings))
                NSMenuItem(title: "Experiment Install Date more than 5 days ago", action: #selector(AppDelegate.changePixelExperimentInstalledDateToLessMoreThan5DayAgo(_:)))
                NSMenuItem(title: "Change Activation Date") {
                    NSMenuItem(title: "Today", action: #selector(AppDelegate.changeInstallDateToToday))
                    NSMenuItem(title: "Less Than a 5 days Ago", action: #selector(AppDelegate.changeInstallDateToLessThan5DayAgo(_:)))
                    NSMenuItem(title: "More Than 5 Days Ago", action: #selector(AppDelegate.changeInstallDateToMoreThan5DayAgoButLessThan9(_:)))
                    NSMenuItem(title: "More Than 9 Days Ago", action: #selector(AppDelegate.changeInstallDateToMoreThan9DaysAgo(_:)))
                }
                NSMenuItem(title: "Reset Email Protection InContext Signup Prompt", action: #selector(AppDelegate.resetEmailProtectionInContextPrompt))
                NSMenuItem(title: "Reset Pixels Storage", action: #selector(AppDelegate.resetDailyPixels))
                NSMenuItem(title: "Reset Remote Messages", action: #selector(AppDelegate.resetRemoteMessages))
                NSMenuItem(title: "Reset Duck Player Preferences", action: #selector(AppDelegate.resetDuckPlayerPreferences))
                NSMenuItem(title: "Reset Onboarding", action: #selector(AppDelegate.resetOnboarding(_:)))
                NSMenuItem(title: "Reset Home Page Settings Onboarding", action: #selector(AppDelegate.resetHomePageSettingsOnboarding(_:)))
                NSMenuItem(title: "Reset Contextual Onboarding", action: #selector(AppDelegate.resetContextualOnboarding(_:)))
                NSMenuItem(title: "Reset Sync Promo prompts", action: #selector(AppDelegate.resetSyncPromoPrompts))
                NSMenuItem(title: "Reset Add To Dock more options menu notification", action: #selector(AppDelegate.resetAddToDockFeatureNotification))
                NSMenuItem(title: "Reset Launch Date To Today", action: #selector(AppDelegate.resetLaunchDateToToday))
                NSMenuItem(title: "Set Launch Date A Week In the Past", action: #selector(AppDelegate.setLaunchDayAWeekInThePast))
                NSMenuItem(title: "Set Launch Date 10 Days In the Past", action: #selector(AppDelegate.setLaunchDay10DaysInThePast))
                NSMenuItem(title: "Set Launch Date A Month In the Past", action: #selector(AppDelegate.setLaunchDayAMonthInThePast))
                NSMenuItem(title: "Reset Quit Survey Was Shown", action: #selector(AppDelegate.resetQuitSurveyWasShown))

            }.withAccessibilityIdentifier("MainMenu.resetData")
            NSMenuItem(title: "UI Triggers") {
                NSMenuItem(title: "Append Tabs") {
                    NSMenuItem(title: "10 Tabs", action: #selector(MainViewController.addDebugTabs(_:)), representedObject: 10)
                    NSMenuItem(title: "50 Tabs", action: #selector(MainViewController.addDebugTabs(_:)), representedObject: 50)
                    NSMenuItem(title: "100 Tabs", action: #selector(MainViewController.addDebugTabs(_:)), representedObject: 100)
                    NSMenuItem(title: "150 Tabs", action: #selector(MainViewController.addDebugTabs(_:)), representedObject: 150)
                    NSMenuItem(title: "500 Tabs", action: #selector(MainViewController.addDebugTabs(_:)), representedObject: 500)
                    NSMenuItem(title: "1000 Tabs", action: #selector(MainViewController.addDebugTabs(_:)), representedObject: 1000)
                }
                NSMenuItem(title: "Show Save Credentials Popover", action: #selector(MainViewController.showSaveCredentialsPopover))
                NSMenuItem(title: "Show Credentials Saved Popover", action: #selector(MainViewController.showCredentialsSavedPopover))
                NSMenuItem(title: "Show Pop Up Window", action: #selector(MainViewController.showPopUpWindow))
                alwaysShowFirstTimeQuitSurvey
            }
            NSMenuItem(title: "Remote Configuration") {
                customConfigurationUrlMenuItem
                configurationDateAndTimeMenuItem
                NSMenuItem.separator()
                NSMenuItem(title: "Reload Configuration Now", action: #selector(AppDelegate.reloadConfigurationNow), keyEquivalent: [.command, .shift, .option, "r"])
                NSMenuItem(title: "Set custom configuration URL…", action: #selector(AppDelegate.setCustomPrivacyConfigurationURL))
                NSMenuItem(title: "Reset configuration to default", action: #selector(AppDelegate.resetPrivacyConfigurationToDefault))
            }
            NSMenuItem(title: "Remote Messaging Framework")
                .submenu(RemoteMessagingDebugMenu(configurationURLProvider: configurationURLProvider))
            NSMenuItem(title: "OS Support")
                .submenu(OSSupportDebugMenu())
            NSMenuItem(title: "User Scripts") {
                NSMenuItem(title: "Remove user scripts from selected tab", action: #selector(MainViewController.removeUserScripts))
            }
            NSMenuItem(title: "Sync & Backup")
                .submenu(SyncDebugMenu())
                .withAccessibilityIdentifier("MainMenu.syncAndBackup")

            NSMenuItem(title: "Personal Information Removal")
                .submenu(DataBrokerProtectionDebugMenu())

            FreemiumDebugMenu()
            SubscriptionPromoDebugMenu()
            AdBlockingDebugMenu()

            if case .normal = AppVersion.runType {
                NSMenuItem(title: "VPN")
                    .submenu(NetworkProtectionDebugMenu(pinningManager: pinningManager))
            }

            NSMenuItem(title: "Attributed Metrics")
                .submenu(AttributedMetricDebugMenu())

            NSMenuItem(title: "Reinstall Detection")
                .submenu(ReinstallUserDetectionDebugMenu())

            NSMenuItem(title: "AppStore Updates")
                .submenu(AppStoreUpdatesDebugMenu())

            if #available(macOS 13.5, *) {
                NSMenuItem(title: "Autofill") {
                    NSMenuItem(title: "View all Credentials", action: #selector(MainViewController.showAllCredentials)).withAccessibilityIdentifier("MainMenu.showAllCredentials")
                }
            }

            NSMenuItem(title: "Simulate crash") {
                NSMenuItem(title: "fatalError", action: #selector(AppDelegate.triggerFatalError))
                NSMenuItem(title: "NSException", action: #selector(MainViewController.crashOnException))
                NSMenuItem(title: "_NSCoreDataException", action: #selector(AppDelegate.crashOnCoreDataException))
                NSMenuItem(title: "C++ exception", action: #selector(AppDelegate.crashOnCxxException))
                if featureFlagger.isFeatureOn(.tabCrashDebugging) {
                    NSMenuItem(title: "Crash All Tabs", action: #selector(MainViewController.crashAllTabs))
                }
            }

            NSMenuItem(title: "Tab Suspension")
                .submenu(TabSuspensionDebugMenu(title: "Tab Suspension"))

            NSMenuItem(title: "Memory Usage Reporting") {
                NSMenuItem(title: "Simulate Memory Report...", action: #selector(AppDelegate.simulateMemoryUsageReport))
                NSMenuItem(title: "Clear Simulated Memory", action: #selector(AppDelegate.clearSimulatedMemory))
                NSMenuItem(title: "Start Reporter Immediately (Skip 5min Delay)", action: #selector(AppDelegate.startMemoryReporterImmediately))
                NSMenuItem.separator()
                NSMenuItem(title: "Fire Interval Pixel Now...", action: #selector(AppDelegate.fireIntervalPixelNow))
                NSMenuItem.separator()
                NSMenuItem(title: "Simulate Memory Pressure (Critical)", action: #selector(AppDelegate.simulateMemoryPressureCritical))
            }

            NSMenuItem(title: "Hang Debugging") {
                toggleWatchdogMenuItem
                NSMenuItem(title: "Simulate hang") {
                    NSMenuItem(title: "0.5 seconds", action: #selector(MainViewController.simulateUIHang), representedObject: 0.5)
                    NSMenuItem(title: "2 seconds", action: #selector(MainViewController.simulateUIHang), representedObject: 2.0)
                    NSMenuItem(title: "3.5 seconds", action: #selector(MainViewController.simulateUIHang), representedObject: 3.5)
                    NSMenuItem(title: "5 seconds", action: #selector(MainViewController.simulateUIHang), representedObject: 5.0)
                    NSMenuItem(title: "10 seconds", action: #selector(MainViewController.simulateUIHang), representedObject: 10.0)
                    NSMenuItem(title: "15 seconds", action: #selector(MainViewController.simulateUIHang), representedObject: 15.0)
                }
            }

            let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
            let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!

            var currentEnvironment = DefaultSubscriptionManager.getSavedOrDefaultEnvironment(userDefaults: subscriptionUserDefaults)
            let updateServiceEnvironment: (SubscriptionEnvironment.ServiceEnvironment) -> Void = { env in
                currentEnvironment.serviceEnvironment = env
                DefaultSubscriptionManager.save(subscriptionEnvironment: currentEnvironment, userDefaults: subscriptionUserDefaults)
            }
            let updatePurchasingPlatform: (SubscriptionEnvironment.PurchasePlatform) -> Void = { platform in
                currentEnvironment.purchasePlatform = platform
                DefaultSubscriptionManager.save(subscriptionEnvironment: currentEnvironment, userDefaults: subscriptionUserDefaults)
            }

            let updateCustomBaseSubscriptionURL: (URL?) -> Void = { url in
                currentEnvironment.customBaseSubscriptionURL = url
                DefaultSubscriptionManager.save(subscriptionEnvironment: currentEnvironment, userDefaults: subscriptionUserDefaults)
            }

            // Closure to handle subscription selection via the user script handler
            let subscriptionSelectionHandler: SubscriptionSelectionHandler = { @MainActor (productId: String, changeType: String?) async in
                let subscriptionManager = Application.appDelegate.subscriptionManager
                let stripePurchaseFlow = DefaultStripePurchaseFlow(subscriptionManager: subscriptionManager)
                let subscriptionAppGroup = Bundle.main.appGroup(bundle: .subs)
                let subscriptionUserDefaults = UserDefaults(suiteName: subscriptionAppGroup)!
                let pixelHandler = SubscriptionPixelHandler(source: .mainApp, pixelKit: nil)
                let pendingTransactionHandler = DefaultPendingTransactionHandler(userDefaults: subscriptionUserDefaults, pixelHandler: pixelHandler)

                let flowPerformer = DefaultSubscriptionFlowsExecuter(
                    subscriptionManager: subscriptionManager,
                    uiHandler: Application.appDelegate.subscriptionUIHandler,
                    wideEvent: Application.appDelegate.wideEvent,
                    subscriptionEventReporter: DefaultSubscriptionEventReporter(),
                    pendingTransactionHandler: pendingTransactionHandler
                )

                let feature = SubscriptionPagesUseSubscriptionFeature(
                    subscriptionManager: subscriptionManager,
                    stripePurchaseFlow: stripePurchaseFlow,
                    uiHandler: Application.appDelegate.subscriptionUIHandler,
                    aiChatURL: AIChatRemoteSettings().aiChatURL,
                    wideEvent: Application.appDelegate.wideEvent,
                    pendingTransactionHandler: pendingTransactionHandler, flowPerformer: flowPerformer, requestValidator: DefaultScriptRequestValidator(subscriptionManager: subscriptionManager)
                )

                // Create params matching what the web would send
                var params: [String: Any] = ["id": productId]
                if let changeType = changeType {
                    params["change"] = changeType
                }

                // Call the appropriate handler based on whether it's a tier change or new purchase
                if changeType != nil {
                    _ = try? await feature.subscriptionChangeSelected(params: params, original: WKScriptMessage())
                } else {
                    _ = try? await feature.subscriptionSelected(params: params, original: WKScriptMessage())
                }
            }

            SubscriptionDebugMenu(currentEnvironment: currentEnvironment,
                                  updateServiceEnvironment: updateServiceEnvironment,
                                  updatePurchasingPlatform: updatePurchasingPlatform,
                                  updateCustomBaseSubscriptionURL: updateCustomBaseSubscriptionURL,
                                  currentViewController: { Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController },
                                  openSubscriptionTab: { Application.appDelegate.windowControllersManager.showTab(with: .subscription($0)) },
                                  subscriptionManager: Application.appDelegate.subscriptionManager,
                                  subscriptionUserDefaults: subscriptionUserDefaults,
                                  wideEvent: Application.appDelegate.wideEvent,
                                  subscriptionSelectionHandler: subscriptionSelectionHandler)

            NSMenuItem(title: "TipKit") {
                NSMenuItem(title: "Reset", action: #selector(AppDelegate.resetTipKit))
                NSMenuItem(title: "⚠️ App restart required.", action: nil, target: nil)
            }

            NSMenuItem(title: "Logging").submenu(setupLoggingMenu())
            NSMenuItem(title: "AI Chat").submenu(AIChatDebugMenu())
            NSMenuItem(title: "Base URL Configuration").submenu(BaseURLDebugMenu())
            if StandardApplicationBuildType().isSparkleBuild {
                NSMenuItem(title: "Updates").submenu(UpdatesDebugMenu(keyValueStore: UserDefaults.standard, internalUserDecider: internalUserDecider))
            }
            if AppVersion.runType.requiresEnvironment {
                NSMenuItem(title: "Promo Queue")
                    .submenu(PromoDebugMenu())
                    .withAccessibilityIdentifier(AccessibilityIdentifiers.PromoQueue.promoQueueDebugMenu)
                NSMenuItem(title: "SAD/ATT Prompts (Default Browser/Add to Dock)")
                    .withAccessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.promptsDebugMenu)
                    .submenu(DefaultBrowserAndDockPromptDebugMenu())
                WinBackOfferDebugMenu(winbackOfferStore: Application.appDelegate.winbackOfferStore,
                                      keyValueStore: Application.appDelegate.keyValueStore)
            }
        }

        // Sort menu items alphabetically (keep Feature Flag Overrides at top)
        sortDebugMenuItems(debugMenu)

        // Add search field at the top
        let searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = "Search debug menu..."
        searchField.focusRingType = .none

        // Create delegate to handle real-time text changes
        let searchDelegate = DebugMenuSearchDelegate(menu: debugMenu)
        searchField.delegate = searchDelegate

        let searchContainer = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        searchContainer.addSubview(searchField)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 22)
        ])

        let searchMenuItem = NSMenuItem()
        searchMenuItem.view = searchContainer
        searchMenuItem.tag = -1
        // Store delegate to keep it alive
        objc_setAssociatedObject(searchMenuItem, "searchDelegate", searchDelegate, .OBJC_ASSOCIATION_RETAIN)
        debugMenu.insertItem(searchMenuItem, at: 0)

        let separatorItem = NSMenuItem.separator()
        separatorItem.tag = -1
        debugMenu.insertItem(separatorItem, at: 1)

        debugMenu.addItem(internalUserItem)
        debugMenu.addItem(.separator())
        debugMenu.addItem(NSMenuItem(title: "Download DuckDuckGo Alpha Build", action: #selector(downloadAlphaBuild), target: self))

        debugMenu.autoenablesItems = false
        return debugMenu
    }

    private func sortDebugMenuItems(_ menu: NSMenu) {
        // Get all items except the first two (Feature Flag Overrides and its separator)
        let featureFlagItem = menu.items.count > 0 ? menu.items[0] : nil
        let firstSeparator = menu.items.count > 1 ? menu.items[1] : nil

        // Get items to sort (everything after the first separator)
        let itemsToSort = menu.items.dropFirst(2)

        // Separate regular items from separators
        var regularItems: [NSMenuItem] = []
        var separatorIndices: [Int] = []

        for (index, item) in itemsToSort.enumerated() {
            if item.isSeparatorItem {
                separatorIndices.append(index)
            } else {
                regularItems.append(item)
            }
        }

        // Sort regular items alphabetically by title
        regularItems.sort { item1, item2 in
            // Handle items without titles (like custom views)
            let title1 = item1.title.isEmpty ? "zzz" : item1.title
            let title2 = item2.title.isEmpty ? "zzz" : item2.title
            return title1.localizedCaseInsensitiveCompare(title2) == .orderedAscending
        }

        menu.removeAllItems()

        // Add Feature Flag Overrides back at the top
        if let featureFlagItem = featureFlagItem {
            menu.addItem(featureFlagItem)
        }
        if let firstSeparator = firstSeparator {
            menu.addItem(firstSeparator)
        }

        // Add sorted items (separators are removed since they'll be managed by filtering)
        for item in regularItems {
            menu.addItem(item)
        }
    }

    private func setupLoggingMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.addItem(autofillDebugScriptMenuItem
            .targetting(self))
        menu.addItem(contentScopeDebugStateMenuItem
            .targetting(self))
        menu.addItem(.separator())
        let exportLogsMenuItem = NSMenuItem(title: "Export Logs…", action: #selector(MainViewController.exportLogs))
        menu.addItem(exportLogsMenuItem)
        let logMonitorMenuItem = NSMenuItem(title: "Log Monitor…", action: #selector(MainViewController.openLogMonitor))
        menu.addItem(logMonitorMenuItem)

        self.loggingMenu = menu
        return menu
    }

    @MainActor private func makeAIChatMenu() -> AIChatMenu {
        let actions = AIChatMenu.Actions.makeDefault(
            remoteSettings: AIChatRemoteSettings(),
            tabOpener: NSApp.delegateTyped.aiChatTabOpener,
            historyCleaner: aiChatHistoryCleaner,
            windowControllersManager: Application.appDelegate.windowControllersManager,
            aiChatSyncCleaner: { Application.appDelegate.aiChatSyncCleaner }
        )
        return AIChatMenu(suggestionsReader: aiChatSuggestionsReader, actions: actions, maxChatItems: 8)
    }

    private func setupAIChatMenu() {
        let showTopLevelMenu = aiChatMenuConfig.shouldDisplayApplicationMenuShortcut
        aiChatMenu.isHidden = !showTopLevelMenu
        newAIChatFileMenuItem.isHidden = !aiChatMenuConfig.shouldDisplayAnyAIChatFeature || showTopLevelMenu
    }

    private func updateInternalUserItem() {
        internalUserItem.title = internalUserDecider.isInternalUser ? "Remove Internal User State" : "Set Internal User State"
    }

    private func updateAutofillDebugScriptMenuItem() {
        autofillDebugScriptMenuItem.state = AutofillPreferences().debugScriptEnabled ? .on : .off
    }

    private func updateContentScopeDebugStateMenuItem() {
        contentScopeDebugStateMenuItem.state = contentScopePreferences.isDebugStateEnabled ? .on : .off
    }

    private func updateShiftNextStepsDaysMenuItem() {
        shiftNextStepsDaysMenuItem.title = "Shift \(appearancePreferences.maxNextStepsCardsDemonstrationDays) days"
    }

    @MainActor
    private func updateWatchdogMenuItems() {
        toggleWatchdogMenuItem.state = NSApp.delegateTyped.watchdog.isRunning ? .on : .off
    }

    private func updateRemoteConfigurationInfo() {
        var dateString: String
        if let date = Application.appDelegate.configurationManager.lastConfigurationInstallDate {
            dateString = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .medium)
            configurationDateAndTimeMenuItem.title = "Last Update Time: \(dateString)"
        } else {
            dateString = "Last Update Time: -"
        }
        configurationDateAndTimeMenuItem.title = dateString

        customConfigurationUrlMenuItem.title = "Configuration URL:  \(configurationURLProvider.url(for: .privacyConfiguration).absoluteString)"
    }

    @objc private func toggleAutofillScriptDebugSettingsAction(_ sender: NSMenuItem) {
        AutofillPreferences().debugScriptEnabled = !AutofillPreferences().debugScriptEnabled
        NotificationCenter.default.post(name: .autofillScriptDebugSettingsDidChange, object: nil)
        updateAutofillDebugScriptMenuItem()
    }

    @objc private func toggleContentScopeStateDebugSettingsAction(_ sender: NSMenuItem) {
        contentScopePreferences.isDebugStateEnabled = !contentScopePreferences.isDebugStateEnabled
        updateContentScopeDebugStateMenuItem()
    }

    @MainActor
    @objc private func downloadAlphaBuild() {
        let url = URL(string: "https://staticcdn.duckduckgo.com/macos-desktop-browser/alpha/duckduckgo-alpha.dmg")!
        Application.appDelegate.windowControllersManager.open(
            url,
            source: .userEntered(url.absoluteString, downloadRequested: true),
            target: nil,
            with: NSApp.currentEvent
        )
    }

    @MainActor
    func updateMenuItemsPositionForFireWindowDefault(_ isFireWindowDefault: Bool) {
        guard let fileMenu = self.item(at: 1), fileMenu.title == UserText.mainMenuFile else {
            return
        }

        fileMenu.submenu?.removeItem(newWindowMenuItem)
        fileMenu.submenu?.removeItem(newBurnerWindowMenuItem)

        if isFireWindowDefault {
            fileMenu.submenu?.insertItem(newBurnerWindowMenuItem, at: 1)
            fileMenu.submenu?.insertItem(newWindowMenuItem, at: 2)
        } else {
            fileMenu.submenu?.insertItem(newWindowMenuItem, at: 1)
            fileMenu.submenu?.insertItem(newBurnerWindowMenuItem, at: 2)
        }
    }

    @MainActor
    func updateMenuShortcutsFor(_ isFireWindowDefault: Bool) {
        if isFireWindowDefault {
            // When Fire Window is default: CMD+N opens Fire Window, CMD+SHIFT+N opens Standard Window
            newBurnerWindowMenuItem.keyEquivalent = "n"
            newBurnerWindowMenuItem.keyEquivalentModifierMask = [.command]
            newWindowMenuItem.keyEquivalent = "N"
            newWindowMenuItem.keyEquivalentModifierMask = [.command, .shift]
        } else {
            // When Fire Window is not default: CMD+N opens Standard Window, CMD+SHIFT+N opens Fire Window
            newWindowMenuItem.keyEquivalent = "n"
            newWindowMenuItem.keyEquivalentModifierMask = [.command]
            newBurnerWindowMenuItem.keyEquivalent = "N"
            newBurnerWindowMenuItem.keyEquivalentModifierMask = [.command, .shift]
        }
    }
}

// MARK: - Debug Menu Search Delegate

private class DebugMenuSearchDelegate: NSObject, NSSearchFieldDelegate {
    weak var menu: NSMenu?

    init(menu: NSMenu) {
        self.menu = menu
        super.init()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField,
              let menu = menu else { return }

        let searchText = searchField.stringValue.lowercased()

        if searchText.isEmpty {
            menu.showAllMenuItems()
        } else {
            menu.filterMenuItems(searchText: searchText)
        }
    }
}

// MARK: - Debug Menu Search Extension

extension NSMenu {
    func showAllMenuItems() {
        for item in items {
            // Skip search field and its separator
            if item.tag == -1 {
                continue
            }

            if !item.isSeparatorItem && item.view == nil {
                item.isHidden = false
                item.submenu?.showAllMenuItems()
            }
        }
    }

    func filterMenuItems(searchText: String) {
        for item in items {
            // Skip search field and its separator
            if item.tag == -1 {
                continue
            }

            // Skip separator items - they'll be handled based on surrounding items
            if item.isSeparatorItem {
                continue
            }

            // Skip custom view items
            if item.view != nil {
                continue
            }

            let titleMatches = item.title.lowercased().contains(searchText)

            if titleMatches {
                // If parent matches, show parent and ALL submenu items
                item.isHidden = false
                if let submenu = item.submenu {
                    submenu.showAllMenuItems()
                }
            } else {
                // Parent doesn't match - check if any submenu items match
                var submenuMatches = false
                if let submenu = item.submenu {
                    submenu.filterMenuItems(searchText: searchText)
                    submenuMatches = submenu.items.contains { !$0.isHidden && !$0.isSeparatorItem }
                }

                // Show item only if submenu has matches
                item.isHidden = !submenuMatches
            }
        }

        // Hide separators that are adjacent to hidden items or other separators
        manageSeparatorVisibility()
    }

    private func manageSeparatorVisibility() {
        var previousVisibleItem: NSMenuItem?

        for item in items {
            // Skip search field items
            if item.tag == -1 {
                continue
            }

            if item.isSeparatorItem {
                // Hide separator if:
                // - It's the first visible item
                // - The previous visible item was also a separator
                // - There are no more visible items after it
                if previousVisibleItem == nil || previousVisibleItem?.isSeparatorItem == true {
                    item.isHidden = true
                } else {
                    // Tentatively show it - will hide if it's the last item
                    item.isHidden = false
                }
            } else if !item.isHidden {
                previousVisibleItem = item
            }
        }

        // Hide trailing separators
        for item in items.reversed() {
            if item.tag == -1 {
                continue
            }

            if item.isSeparatorItem {
                if !item.isHidden {
                    item.isHidden = true
                }
            } else if !item.isHidden {
                break
            }
        }
    }
}

// MARK: - NSMenuDelegate
extension MainMenu: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === bookmarksMenu || menu === favoritesMenu else { return }
        guard isLazyMenuRebuild else { return }

        if bookmarksMenuNeedsRebuild {
            updateBookmarksMenu(
                favoriteViewModels: pendingFavoriteViewModels,
                topLevelBookmarkViewModels: pendingTopLevelViewModels
            )
            bookmarksMenuNeedsRebuild = false
            bookmarkFaviconsNeedUpdate = false
        } else if bookmarkFaviconsNeedUpdate {
            updateFavicons(in: menu)
            bookmarkFaviconsNeedUpdate = false
        }
    }
}

// MARK: - SharingMenuDelegate
extension MainMenu: SharingMenuDelegate {
    func sharingMenuRequestsSharingData() -> SharingMenu.SharingData? {
        guard let tabViewModel = (NSApp.keyWindow?.nextResponder as? MainWindowController ?? Application.appDelegate.windowControllersManager.lastKeyMainWindowController)?.mainViewController.tabCollectionViewModel.selectedTabViewModel,
              tabViewModel.canReload,
              !tabViewModel.isShowingErrorPage,
              let url = tabViewModel.tab.content.userEditableUrl else { return nil }

        return (tabViewModel.title, [url])
    }
}

#if DEBUG
#Preview {
    return MenuPreview(menu: NSApp.mainMenu!)
}
#endif
