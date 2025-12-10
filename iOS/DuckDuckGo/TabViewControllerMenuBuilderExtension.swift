//
//  TabViewControllerMenuBuilderExtension.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Bookmarks
import simd
import WidgetKit
import Common
import PrivacyDashboard
import PixelExperimentKit
import DesignResourcesKit
import DesignResourcesKitIcons
import UIComponents

extension TabViewController {

    private enum ShortcutEntriesState {
        case newTab
        case pageLoaded
    }

    private var shouldShowAIChatInMenu: Bool {
        let settings = AIChatSettings(privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
        return settings.isAIChatBrowsingMenuUserSettingsEnabled
    }

    func buildBrowsingMenuHeaderContent() -> [BrowsingMenuEntry] {
        var entries = [BrowsingMenuEntry]()

        let newTabEntry = buildNewTabEntry()
        let shareEntry = buildShareEntry()
        let copyEntry = buildCopyEntry()

        if shouldShowAIChatInMenu {
            
            var chatEntry: BrowsingMenuEntry
            if aiChatFullModeFeature.isAvailable {
                chatEntry = buildNewAIChatEntry()
            } else {
                chatEntry = buildChatEntry(withSmallIcon: false)
            }

            entries.append(newTabEntry)
            entries.append(chatEntry)
            entries.append(copyEntry)
            entries.append(shareEntry)
        } else {
            let printEntry = buildPrintEntry(withSmallIcon: false)
            entries.append(newTabEntry)
            entries.append(printEntry)
            entries.append(copyEntry)
            entries.append(shareEntry)
        }
        
        return entries
    }

    var favoriteEntryIndex: Int { 1 }

    func buildShortcutsMenu() -> [BrowsingMenuEntry] {
        buildShortcutsEntries(state: .newTab)
    }

    func buildSheetBrowsingMenu(context: BrowsingMenuContext,
                                with bookmarksInterface: MenuBookmarksInteracting,
                                mobileCustomization: MobileCustomization,
                                browsingMenuSheetCapability: BrowsingMenuSheetCapable,
                                clearTabsAndData: @escaping () -> Void) -> BrowsingMenuModel? {
        
        let builder = BrowsingMenuBuilder(entryBuilder: self)
        
        return builder.buildMenu(
            context: context,
            bookmarksInterface: bookmarksInterface,
            mobileCustomization: mobileCustomization,
            clearTabsAndData: clearTabsAndData
        )
    }

    func buildBrowsingMenu(with bookmarksInterface: MenuBookmarksInteracting,
                           mobileCustomization: MobileCustomization,
                           clearTabsAndData: @escaping () -> Void) -> [BrowsingMenuEntry] {
        
        var entries = [BrowsingMenuEntry]()

        let linkEntries = buildLinkEntries(with: bookmarksInterface)
        entries.append(contentsOf: linkEntries)

        if shouldShowAIChatInMenu {
            let printEntry = buildPrintEntry(withSmallIcon: true)
            entries.append(printEntry)
        }

        if let domain = self.privacyInfo?.domain {
            entries.append(self.buildToggleProtectionEntry(forDomain: domain))
        }

        if link != nil {
            entries.append(buildReportBrokenSiteEntry())

            if mobileCustomization.isEnabled && !mobileCustomization.hasFireButton {
                entries.append(.separator)
                entries.append(buildClearDataEntry(clearTabsAndData: clearTabsAndData))
            }
        }

        // Do not add separator if there are no entries so far
        if entries.count > 0 {
            entries.append(.separator)
        }

        let shortcutsEntries = buildShortcutsEntries(state: .pageLoaded)
        entries.append(contentsOf: shortcutsEntries)

        return entries
    }
    
    func buildAITabMenuHeaderContent() -> [BrowsingMenuEntry] {
        var entries = [BrowsingMenuEntry]()

        entries.append(buildNewTabEntry())

        entries.append(buildNewAIChatEntry())

        return entries
    }
    
    func buildAITabMenu(useSmallIcon: Bool = true, includeSettings: Bool = true, separateUtililtyItems: Bool = false) -> [BrowsingMenuEntry] {
        var entries = [BrowsingMenuEntry]()
        
        entries.append(contentsOf: buildAITabLinkEntries(useSmallIcon: useSmallIcon, addPrint: !separateUtililtyItems))

        entries.append(.separator)
        
        entries.append(buildOpenBookmarksEntry(useSmallIcon: useSmallIcon))
        
        if featureFlagger.isFeatureOn(.autofillAccessCredentialManagement) {
            entries.append(buildAutoFillEntry(useSmallIcon: useSmallIcon))
        }
        
        entries.append(buildDownloadsEntry(useSmallIcon: useSmallIcon))
        
        entries.append(buildAIChatSidebarEntry(useSmallIcon: useSmallIcon))

        if separateUtililtyItems {
            entries.append(.separator)
            entries.append(buildPrintEntry(withSmallIcon: useSmallIcon))
        }

        entries.append(.separator)
        
        entries.append(buildAIChatSettingsEntry(useSmallIcon: useSmallIcon))

        if includeSettings {
            entries.append(buildSettingsEntry(useSmallIcon: useSmallIcon))
        }

        return entries
    }

    private func buildPrintEntry(withSmallIcon smallIcon: Bool) -> BrowsingMenuEntry {
        .regular(name: UserText.actionPrintSite,
                 accessibilityLabel: UserText.actionPrintSite,
                 image: smallIcon ? DesignSystemImages.Glyphs.Size16.print : DesignSystemImages.Glyphs.Size24.print,
                 action: { [weak self] in
            Pixel.fire(pixel: smallIcon ? .browsingMenuListPrint : .browsingMenuPrint)
            self?.print()
        })
    }
    
    private func buildNewTabEntry() -> BrowsingMenuEntry {
        .regular(name: UserText.actionNewTab,
                 accessibilityLabel: UserText.keyCommandNewTab,
                 image: DesignSystemImages.Glyphs.Size24.add,
                 action: { [weak self] in
            self?.onNewTabAction()
        })
    }
    
    private func buildDownloadsEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        .regular(name: UserText.actionDownloads,
                 image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.downloads : DesignSystemImages.Glyphs.Size24.downloads,
                 showNotificationDot: AppDependencyProvider.shared.downloadManager.unseenDownloadsAvailable,
                 action: { [weak self] in
            self?.onOpenDownloadsAction()
        })
    }
    
    private func buildAutoFillEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        .regular(name: UserText.actionAutofillLogins,
                 image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.keyLogin : DesignSystemImages.Glyphs.Size24.key,
                 action: { [weak self] in
            self?.onOpenAutofillLoginsAction()
        })
    }

    private func buildChatEntry(withSmallIcon smallIcon: Bool) -> BrowsingMenuEntry {
        .regular(name: UserText.actionOpenAIChat,
                 image: smallIcon ? DesignSystemImages.Glyphs.Size16.aiChat : DesignSystemImages.Glyphs.Size24.aiChat,
                 action: { [weak self] in
            self?.openAIChat()
        })
    }
    
    private func buildSettingsEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        .regular(name: UserText.actionSettings,
                 image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.settings : DesignSystemImages.Glyphs.Size24.settings,
                 action: { [weak self] in
            self?.onBrowsingSettingsAction()
        })
    }

    private func buildShortcutsEntries(state: ShortcutEntriesState) -> [BrowsingMenuEntry] {
        var entries = [BrowsingMenuEntry]()

        if state == .newTab {
            entries.append(BrowsingMenuEntry.regular(name: UserText.actionTabNew,
                                                     image: DesignSystemImages.Glyphs.Size16.add,
                                                     action: { [weak self] in
                self?.onNewTabAction()
            }))

            if shouldShowAIChatInMenu {
                var chatEntry: BrowsingMenuEntry
                if aiChatFullModeFeature.isAvailable {
                    chatEntry = buildNewAIChatEntry(withSmallIcon: true)
                } else {
                    chatEntry = buildChatEntry(withSmallIcon: true)
                }
                entries.append(chatEntry)
            }

            entries.append(.separator)
        }

        entries.append(buildOpenBookmarksEntry())

        if featureFlagger.isFeatureOn(.autofillAccessCredentialManagement) {
            entries.append(buildAutoFillEntry())
        }

        entries.append(buildDownloadsEntry())

        if state == .newTab, featureFlagger.isFeatureOn(.vpnMenuItem), AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge.hasAppStoreProductsAvailable {
            entries.append(buildVPNEntry())
        }

        entries.append(buildSettingsEntry())

        return entries
    }

    private func buildLinkEntries(with bookmarksInterface: MenuBookmarksInteracting) -> [BrowsingMenuEntry] {
        guard let link = link, !isError else { return [] }

        var entries = [BrowsingMenuEntry]()

        let bookmarkEntries = buildBookmarkEntries(for: link, with: bookmarksInterface)
        entries.append(bookmarkEntries.bookmark)
        assert(self.favoriteEntryIndex == entries.count, "Entry index should be in sync with entry placement")
        entries.append(bookmarkEntries.favorite)

        entries.append(.separator)

        if let entry = self.buildKeepSignInEntry(forLink: link) {
            entries.append(entry)
        }

        if let entry = self.buildUseNewDuckAddressEntry(forLink: link) {
            entries.append(entry)
        }

        if appSettings.currentRefreshButtonPosition.isEnabledForBrowsingMenu {
            entries.append(buildReloadEntry())
        }

        if let entry = textZoomCoordinator.makeBrowsingMenuEntry(forLink: link, inController: self, forWebView: self.webView, useSmallIcon: true) {
            entries.append(entry)
        }

        entries.append(buildDesktopSiteEntry(forLink: link))

        entries.append(buildFindInPageEntry(forLink: link))
                
        return entries
    }
    
    private func buildAITabLinkEntries(useSmallIcon: Bool = true, addPrint: Bool = true) -> [BrowsingMenuEntry] {
        guard let link = link, !isError else { return [] }

        var entries = [BrowsingMenuEntry]()

        if let entry = textZoomCoordinator.makeBrowsingMenuEntry(forLink: link, inController: self, forWebView: self.webView, useSmallIcon: useSmallIcon) {
            entries.append(entry)
        }

        entries.append(self.buildFindInPageEntry(forLink: link, useSmallIcon: useSmallIcon))

        if addPrint {
            entries.append(buildPrintEntry(withSmallIcon: useSmallIcon))
        }

        return entries
    }

    private func buildKeepSignInEntry(forLink link: Link, useSmallIcon: Bool = true) -> BrowsingMenuEntry? {
        guard let domain = link.url.host, !link.url.isDuckDuckGo else { return nil }
        let isFireproofed = fireproofing.isAllowed(cookieDomain: domain)
        
        if isFireproofed {
            return BrowsingMenuEntry.regular(name: UserText.disablePreservingLogins,
                                             image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.fireSolid : DesignSystemImages.Glyphs.Size24.fireSolid,
                                             action: { [weak self] in
                                                self?.disableFireproofingForDomain(domain)
                                             })
        }

        return BrowsingMenuEntry.regular(name: UserText.enablePreservingLogins,
                                         image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.fireproofSolid : DesignSystemImages.Glyphs.Size24.fireproofSolid,
                                         action: { [weak self] in
                                            self?.enableFireproofingForDomain(domain)
                                         })
    }

    private func buildShareEntry(useSmallIcon: Bool = false) -> BrowsingMenuEntry {
        return BrowsingMenuEntry.regular(name: UserText.actionShare,
                                         image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.shareApple :  DesignSystemImages.Glyphs.Size24.shareApple,
                                         action: { [weak self] in
            guard let self = self else { return }
            guard let menu = self.chromeDelegate?.omniBar.barView.menuButton else { return }
            Pixel.fire(pixel: .browsingMenuShare)
            self.onShareAction(forLink: self.link!, fromView: menu)
        })
    }

    private func buildCopyEntry() -> BrowsingMenuEntry {
        let image = DesignSystemImages.Glyphs.Size24.copy
        return BrowsingMenuEntry.regular(name: UserText.actionCopy, image: image, action: { [weak self] in
            guard let strongSelf = self else { return }
            if !strongSelf.isError, let url = strongSelf.webView.url {
                strongSelf.onCopyAction(forUrl: url)
            } else if let text = self?.chromeDelegate?.omniBar.text {
                strongSelf.onCopyAction(for: text)
            }

            Pixel.fire(pixel: .browsingMenuCopy)
            let addressBarBottom = strongSelf.appSettings.currentAddressBarPosition.isBottom
            ActionMessageView.present(message: UserText.actionCopyMessage,
                                      presentationLocation: .withBottomBar(andAddressBarBottom: addressBarBottom))
        })
    }

    private func onNewTabAction() {
        Pixel.fire(pixel: .browsingMenuNewTab)
        delegate?.tabDidRequestNewTab(self)
    }

    private func buildFindInPageEntry(forLink link: Link, useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        let image = useSmallIcon ? DesignSystemImages.Glyphs.Size16.findInPage : DesignSystemImages.Glyphs.Size24.findInPage
        return BrowsingMenuEntry.regular(name: UserText.findInPage, image: image, action: { [weak self] in
            Pixel.fire(pixel: .browsingMenuFindInPage)
            self?.requestFindInPage()
        })
    }
    
    private func buildDesktopSiteEntry(forLink link: Link, useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        let title = self.tabModel.isDesktop ? UserText.actionRequestMobileSite : UserText.actionRequestDesktopSite
        let image: UIImage
        if useSmallIcon {
            image = self.tabModel.isDesktop ? DesignSystemImages.Glyphs.Size16.deviceMobile : DesignSystemImages.Glyphs.Size16.deviceDesktop
        } else {
            image = self.tabModel.isDesktop ? DesignSystemImages.Glyphs.Size24.deviceMobile : DesignSystemImages.Glyphs.Size24.deviceDesktop
        }
        return BrowsingMenuEntry.regular(name: title, image: image, action: { [weak self] in
            self?.onToggleDesktopSiteAction(forUrl: link.url)
        })
    }
    
    private func buildZoomEntry(forLink link: Link, useSmallIcon: Bool = true) -> BrowsingMenuEntry? {
        return textZoomCoordinator.makeBrowsingMenuEntry(forLink: link, inController: self, forWebView: self.webView, useSmallIcon: useSmallIcon)
    }
    
    private func buildReloadEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        return BrowsingMenuEntry.regular(name: UserText.actionRefreshPage,
                                         image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.reload : DesignSystemImages.Glyphs.Size24.reload,
                                         action: { [weak self] in
            guard let self = self else { return }
            Pixel.fire(pixel: .browsingMenuRefreshPage)
            self.reload()
        })
    }
    
    private func buildReportBrokenSiteEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        return BrowsingMenuEntry.regular(name: UserText.actionReportBrokenSite,
                                         image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.feedbackBlank : DesignSystemImages.Glyphs.Size24.support,
                                         action: { [weak self] in
            self?.onReportBrokenSiteAction()
        })
    }
    
    private func buildClearDataEntry(clearTabsAndData: @escaping () -> Void, useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        return BrowsingMenuEntry.regular(name: UserText.actionForgetAll,
                                         accessibilityLabel: UserText.actionForgetAll,
                                         image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.fireSolid : DesignSystemImages.Glyphs.Size24.fireSolid,
                                         action: clearTabsAndData)
    }
    
    private func buildBookmarkEntries(for link: Link,
                                      with bookmarksInterface: MenuBookmarksInteracting,
                                      useSmallIcon: Bool = true) -> (bookmark: BrowsingMenuEntry,
                                                                     favorite: BrowsingMenuEntry) {
        let existingFavorite = bookmarksInterface.favorite(for: link.url)
        let existingBookmark = existingFavorite ?? bookmarksInterface.bookmark(for: link.url)
        
        return (bookmark: buildBookmarkEntry(for: link,
                                             bookmark: existingBookmark,
                                             with: bookmarksInterface,
                                             useSmallIcon: useSmallIcon),
                favorite: buildFavoriteEntry(for: link,
                                             bookmark: existingFavorite,
                                             with: bookmarksInterface,
                                             useSmallIcon: useSmallIcon))
    }

    private func buildBookmarkEntry(for link: Link,
                                    bookmark: BookmarkEntity?,
                                    with bookmarksInterface: MenuBookmarksInteracting,
                                    useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        
        if bookmark != nil {
            return BrowsingMenuEntry.regular(name: UserText.actionEditBookmark,
                                             image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.bookmarkSolid : DesignSystemImages.Glyphs.Size24.bookmarkSolid,
                                             action: { [weak self] in
                                                self?.performEditBookmarkAction(for: link)
                                             })
        }

        return BrowsingMenuEntry.regular(name: UserText.actionSaveBookmark,
                                         image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.bookmark : DesignSystemImages.Glyphs.Size24.bookmark,
                                         action: { [weak self] in
                                           self?.performSaveBookmarkAction(for: link,
                                                                           with: bookmarksInterface)
                                         })
    }

    private func buildOpenBookmarksEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        BrowsingMenuEntry.regular(name: UserText.actionOpenBookmarks,
                                  image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.bookmarks : DesignSystemImages.Glyphs.Size24.bookmarks,
                                  action: { [weak self] in
            self?.onOpenBookmarksAction()
        })
    }
    
    private func buildNewAIChatEntry(withSmallIcon smallIcon: Bool = false) -> BrowsingMenuEntry {
        .regular(name: UserText.actionNewAIChat,
                 accessibilityLabel: UserText.actionNewAIChat,
                 image: smallIcon ? DesignSystemImages.Glyphs.Size16.aiChatAdd : DesignSystemImages.Glyphs.Size24.aiChatAdd,
                 action: { [weak self] in
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsMenuNewChatTabTapped)
            self?.openNewChatInNewTab()
        })
    }
    
    private func buildAIChatSidebarEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        .regular(name: UserText.actionAIChatHistory,
                 accessibilityLabel: UserText.actionAIChatHistory,
                 image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.aiChatHistory : DesignSystemImages.Glyphs.Size24.aiChatHistory,
                 action: { [weak self] in
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsMenuSidebarTapped)
            self?.submitToggleSidebarAction()
        })
    }
    
    private func buildAIChatSettingsEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        .regular(name: UserText.actionAIChatSettings,
                 accessibilityLabel: UserText.actionAIChatSettings,
                 image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.aiChatSettings : DesignSystemImages.Glyphs.Size24.settings,
                 action: { [weak self] in
            DailyPixel.fireDailyAndCount(pixel: .aiChatSettingsMenuAIChatSettingsTapped)
            self?.submitOpenSettingsAction()
        })
    }

    private func performSaveBookmarkAction(for link: Link,
                                           with bookmarksInterface: MenuBookmarksInteracting) {
        Pixel.fire(pixel: .browsingMenuAddToBookmarks)
        DailyPixel.fire(pixel: .addBookmarkDaily)
        saveAsBookmark(favorite: false, viewModel: bookmarksInterface)
    }

    private func performEditBookmarkAction(for link: Link) {
        Pixel.fire(pixel: .browsingMenuEditBookmark)

        delegate?.tabDidRequestEditBookmark(tab: self)
    }

    private func buildFavoriteEntry(for link: Link,
                                    bookmark: BookmarkEntity?,
                                    with bookmarksInterface: MenuBookmarksInteracting,
                                    useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        if bookmark?.isFavorite(on: .mobile) ?? false {
            let action: () -> Void = { [weak self] in
                Pixel.fire(pixel: .browsingMenuRemoveFromFavorites)
                self?.performRemoveFavoriteAction(for: link, with: bookmarksInterface)
            }

            let entry = BrowsingMenuEntry.regular(name: UserText.actionRemoveFavorite,
                                                  image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.favoriteSolid : DesignSystemImages.Glyphs.Size24.favoriteSolid,
                                                  action: action)
            return entry

        }

        // Capture flow state here as will be reset after menu is shown
        let addToFavoriteFlow = daxDialogsManager.isAddFavoriteFlow

        let entry = BrowsingMenuEntry.regular(name: UserText.actionSaveFavorite,
                                              image: useSmallIcon ? DesignSystemImages.Glyphs.Size16.favorite : DesignSystemImages.Glyphs.Size24.favorite,
                                              action: { [weak self] in
            Pixel.fire(pixel: addToFavoriteFlow ? .browsingMenuAddToFavoritesAddFavoriteFlow : .browsingMenuAddToFavorites)
            DailyPixel.fire(pixel: .addFavoriteDaily)
            self?.performAddFavoriteAction(for: link, with: bookmarksInterface)
        })
        return entry
    }
    
    private func performAddFavoriteAction(for link: Link,
                                          with bookmarksInterface: MenuBookmarksInteracting) {
        bookmarksInterface.createOrToggleFavorite(title: link.title ?? "", url: link.url)
        favicons.loadFavicon(forDomain: link.url.host, intoCache: .fireproof, fromCache: .tabs)
        WidgetCenter.shared.reloadAllTimelines()
        syncService.scheduler.notifyDataChanged()

        ActionMessageView.present(message: UserText.webSaveFavoriteDone,
                                  actionTitle: UserText.actionGenericUndo,
                                  presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
                                  onAction: {
            self.performRemoveFavoriteAction(for: link, with: bookmarksInterface)
        })
    }
    
    private func performRemoveFavoriteAction(for link: Link,
                                             with bookmarksInterface: MenuBookmarksInteracting) {
        bookmarksInterface.createOrToggleFavorite(title: link.title ?? "", url: link.url)
        WidgetCenter.shared.reloadAllTimelines()
        syncService.scheduler.notifyDataChanged()

        ActionMessageView.present(message: UserText.webFavoriteRemoved,
                                  actionTitle: UserText.actionGenericUndo,
                                  presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
                                  onAction: {
            self.performAddFavoriteAction(for: link, with: bookmarksInterface)
        })
    }
    
    private func buildUseNewDuckAddressEntry(forLink link: Link, useSmallIcon: Bool = true) -> BrowsingMenuEntry? {
        guard emailManager?.isSignedIn == true else { return nil }
        let title = UserText.emailBrowsingMenuUseNewDuckAddress
        let image = useSmallIcon ? DesignSystemImages.Glyphs.Size16.email : DesignSystemImages.Glyphs.Size24.email

        return BrowsingMenuEntry.regular(name: title, image: image) { [weak self] in
            (self?.parent as? MainViewController)?.newEmailAddress()
        }
    }

    func onShareAction(forLink link: Link, fromView view: UIView) {
        shareLinkWithTemporaryDownload(temporaryDownloadForPreviewedFile, originalLink: link) { [weak self] link in
            guard let self = self else { return }
            var items: [Any] = [link, self.webView.viewPrintFormatter()]

            if let webView = self.webView {
                items.append(webView)
            }

            self.presentShareSheet(withItems: items, fromView: view) { [weak self] activityType, result, _, error in
                if result {
                    Pixel.fire(pixel: .shareSheetResultSuccess)
                } else {
                    Pixel.fire(pixel: .shareSheetResultFail, error: error)
                }

                if let activityType {
                    self?.firePixelForActivityType(activityType)
                }
            }
        }
    }
    
    private func firePixelForActivityType(_ activityType: UIActivity.ActivityType) {
        switch activityType {
        case .copyToPasteboard:
            Pixel.fire(pixel: .shareSheetActivityCopy)
        case .saveBookmarkInDuckDuckGo:
            Pixel.fire(pixel: .shareSheetActivityAddBookmark)
        case .saveFavoriteInDuckDuckGo:
            Pixel.fire(pixel: .shareSheetActivityAddFavorite)
        case .findInPage:
            Pixel.fire(pixel: .shareSheetActivityFindInPage)
        case .print:
            Pixel.fire(pixel: .shareSheetActivityPrint)
        case .addToReadingList:
            Pixel.fire(pixel: .shareSheetActivityAddToReadingList)
        default:
            Pixel.fire(pixel: .shareSheetActivityOther)
        }
    }

    private func shareLinkWithTemporaryDownload(_ temporaryDownload: Download?,
                                                originalLink: Link,
                                                completion: @escaping (Link) -> Void) {
        guard let download = temporaryDownload else {
            completion(originalLink)
            return
        }
        
        if let downloadLink = download.link {
            completion(downloadLink)
            return
        }
        
        AppDependencyProvider.shared.downloadManager.startDownload(download) { error in
            DispatchQueue.main.async {
                if error == nil, let downloadLink = download.link {
                    let fileSize = downloadLink.localFileURL?.fileSize ?? 0
                    let isFileSizeGreaterThan10MB = (fileSize > 10 * 1000 * 1000)
                    Pixel.fire(pixel: .downloadsSharingPredownloadedLocalFile,
                               withAdditionalParameters: [PixelParameters.fileSizeGreaterThan10MB: isFileSizeGreaterThan10MB ? "1" : "0"])
                    completion(downloadLink)
                } else {
                    completion(originalLink)
                }
            }
        }
    }
    
    private func onToggleDesktopSiteAction(forUrl url: URL) {
        Pixel.fire(pixel: .browsingMenuToggleBrowsingMode)
        tabModel.toggleDesktopMode()
        updateContentMode()
        
        if tabModel.isDesktop {
            load(url: url.toDesktopUrl())
        } else {
            reload()
        }
    }
    
    private func onReportBrokenSiteAction() {
        Pixel.fire(pixel: .browsingMenuReportBrokenSite)
        delegate?.tabDidRequestReportBrokenSite(tab: self)
    }
    
    private func onOpenDownloadsAction() {
        Pixel.fire(pixel: .downloadsListOpened,
                   withAdditionalParameters: [PixelParameters.originatedFromMenu: "1"])
        delegate?.tabDidRequestDownloads(tab: self)
    }
    
    private func onOpenAutofillLoginsAction() {
        Pixel.fire(pixel: .browsingMenuAutofill)
        delegate?.tab(self, didRequestAutofillLogins: nil, source: .overflow, extensionPromotionManager: extensionPromotionManager)
    }
    
    private func onBrowsingSettingsAction() {
        Pixel.fire(pixel: .settingsPresentedFromMenu)
        delegate?.tabDidRequestSettings(tab: self)
    }

    private func onOpenBookmarksAction() {
        delegate?.tabDidRequestBookmarks(tab: self)
    }

    private func openAIChat() {
        delegate?.tabDidRequestAIChat(tab: self)
    }

    private func buildToggleProtectionEntry(forDomain domain: String, useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        let config = ContentBlocking.shared.privacyConfigurationManager.privacyConfig
        let isProtected = !config.isUserUnprotected(domain: domain)
        let title = isProtected ? UserText.actionDisableProtection : UserText.actionEnableProtection
        let image: UIImage
        if useSmallIcon {
            image = isProtected ? DesignSystemImages.Glyphs.Size16.shieldBlocked : DesignSystemImages.Glyphs.Size16.shield
        } else {
            image = isProtected ? DesignSystemImages.Glyphs.Size24.shieldBlocked : DesignSystemImages.Glyphs.Size24.shield
        }

        return BrowsingMenuEntry.regular(name: title, image: image, action: { [weak self] in
            self?.onToggleProtectionAction(forDomain: domain, isProtected: isProtected)
        })
    }

    private func onToggleProtectionAction(forDomain domain: String, isProtected: Bool) {
        let toggleReportingConfig = ToggleReportingConfiguration(privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
        let toggleReportingFeature = ToggleReportingFeature(toggleReportingConfiguration: toggleReportingConfig)
        let toggleReportingManager = ToggleReportingManager(feature: toggleReportingFeature)
        if isProtected && toggleReportingManager.shouldShowToggleReport {
            delegate?.tab(self, didRequestToggleReportWithCompletionHandler: { [weak self] didSendReport in
                self?.togglePrivacyProtection(domain: domain, didSendReport: didSendReport)
            })
        } else {
            togglePrivacyProtection(domain: domain)
        }
        Pixel.fire(pixel: isProtected ? .browsingMenuDisableProtection : .browsingMenuEnableProtection)
        let tdsEtag = AppDependencyProvider.shared.configurationStore.loadEtag(for: .trackerDataSet) ?? ""
        SiteBreakageExperimentMetrics.fireTDSExperimentMetric(metricType: .privacyToggleUsed, etag: tdsEtag) { parameters in
            UniquePixel.fire(pixel: .debugBreakageExperiment, withAdditionalParameters: parameters)
        }
    }

    private func togglePrivacyProtection(domain: String, didSendReport: Bool = false) {
        let config = ContentBlocking.shared.privacyConfigurationManager.privacyConfig
        let isProtected = !config.isUserUnprotected(domain: domain)
        if isProtected {
            config.userDisabledProtection(forDomain: domain)
        } else {
            config.userEnabledProtection(forDomain: domain)
        }
        
        let message: String
        if isProtected {
            if didSendReport {
                message = UserText.messageProtectionDisabledAndToggleReportSent.format(arguments: domain)
            } else {
                message = UserText.messageProtectionDisabled.format(arguments: domain)
            }
        } else {
            message = UserText.messageProtectionEnabled.format(arguments: domain)
        }
        
        ContentBlocking.shared.contentBlockingManager.scheduleCompilation()
        
        ActionMessageView.present(message: message, actionTitle: UserText.actionGenericUndo,
                                  presentationLocation: .withBottomBar(andAddressBarBottom: appSettings.currentAddressBarPosition.isBottom),
                                  onAction: { [weak self] in
            self?.togglePrivacyProtection(domain: domain)
        })
    }

    private func buildVPNEntry(useSmallIcon: Bool = true) -> BrowsingMenuEntry {
        let vpnPromoHelper = VPNSubscriptionPromotionHelper()
        var image: UIImage = useSmallIcon ? DesignSystemImages.Glyphs.Size16.vpnOff : DesignSystemImages.Glyphs.Size24.vpnUnlocked
        var showNotificationDot: Bool = true
        var customDotColor: UIColor?
        var accessibilityLabel: String?

        switch vpnPromoHelper.subscriptionPromoStatus {
        case .promo:
            vpnPromoHelper.subscriptionPromoWasShown()
        case .noPromo:
            showNotificationDot = false
        case .subscribed:
            if case .connected = AppDependencyProvider.shared.connectionObserver.recentValue {
                image = useSmallIcon ? DesignSystemImages.Glyphs.Size16.vpnOn : DesignSystemImages.Glyphs.Size24.vpn
                accessibilityLabel = "\(UserText.actionVPN), \(UserText.settingsOn)"
                customDotColor = UIColor(designSystemColor: .alertGreen)
            } else {
                accessibilityLabel = "\(UserText.actionVPN), \(UserText.settingsOff)"
                customDotColor = UIColor(designSystemColor: .textSecondary).withAlphaComponent(0.33)
            }
        }

        return BrowsingMenuEntry.regular(name: UserText.actionVPN,
                                         accessibilityLabel: accessibilityLabel,
                                         image: image,
                                         showNotificationDot: showNotificationDot,
                                         customDotColor: customDotColor) { [weak self] in
            self?.onOpenVPNAction(with: vpnPromoHelper)
        }
    }

    private func onOpenVPNAction(with vpnPromoHelper: VPNSubscriptionPromotionHelper) {
        switch vpnPromoHelper.subscriptionPromoStatus {
        case .promo, .noPromo:
            let urlComponents = vpnPromoHelper.subscriptionURLComponents()
            NotificationCenter.default.post(
                name: .settingsDeepLinkNotification,
                object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: urlComponents),
                userInfo: nil
            )
            return
        case .subscribed:
            delegate?.tabDidRequestSettingsToVPN(self)
        }
    }

}

// MARK: - BrowsingMenuEntryBuilding

extension TabViewController: BrowsingMenuEntryBuilding {
    
    /// Returns the current link if valid and not in error state
    private var validLink: Link? {
        guard let link = link, !isError else { return nil }
        return link
    }
    
    func makeShortcutsMenu() -> [BrowsingMenuEntry] {
        buildShortcutsMenu()
    }
    
    func makeAITabMenu() -> [BrowsingMenuEntry] {
        buildAITabMenu(useSmallIcon: false, includeSettings: false, separateUtililtyItems: true)
    }
    
    func makeAITabMenuHeaderContent() -> [BrowsingMenuEntry] {
        // Add settings to the header.
        // It'll be filtered out in `makeAITabMenu`
        buildAITabMenuHeaderContent() + [makeSettingsEntry()]
    }
    
    func makeBrowsingMenu(with bookmarksInterface: MenuBookmarksInteracting,
                          mobileCustomization: MobileCustomization,
                          clearTabsAndData: @escaping () -> Void) -> [BrowsingMenuEntry] {
        buildBrowsingMenu(with: bookmarksInterface,
                         mobileCustomization: mobileCustomization,
                         clearTabsAndData: clearTabsAndData)
    }
    
    func makeBrowsingMenuHeaderContent() -> [BrowsingMenuEntry] {
        buildBrowsingMenuHeaderContent()
    }
    
    
    func makeNewTabEntry() -> BrowsingMenuEntry {
        buildNewTabEntry()
    }

    func makeChatEntry() -> BrowsingMenuEntry? {
        let settings = AIChatSettings(privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
        guard settings.isAIChatBrowsingMenuUserSettingsEnabled else { return nil }
        
        if aiChatFullModeFeature.isAvailable {
            return buildNewAIChatEntry(withSmallIcon: false)
        } else {
            return buildChatEntry(withSmallIcon: false)
        }
    }
    
    func makeSettingsEntry() -> BrowsingMenuEntry {
        buildSettingsEntry(useSmallIcon: false)
    }
    
    func makeShareEntry() -> BrowsingMenuEntry {
        buildShareEntry(useSmallIcon: false)
    }
    
    func makePrintEntry() -> BrowsingMenuEntry {
        buildPrintEntry(withSmallIcon: false)
    }
    
    func makeDownloadsEntry() -> BrowsingMenuEntry {
        buildDownloadsEntry(useSmallIcon: false)
    }
    
    func makeOpenBookmarksEntry() -> BrowsingMenuEntry {
        buildOpenBookmarksEntry(useSmallIcon: false)
    }

    func makeClearDataEntry(mobileCustomization: MobileCustomization, clearTabsAndData: @escaping () -> Void) -> BrowsingMenuEntry? {
        guard mobileCustomization.isEnabled && !mobileCustomization.hasFireButton else { return nil }
        return buildClearDataEntry(clearTabsAndData: clearTabsAndData, useSmallIcon: false)
    }
    
    
    func makeAutoFillEntry() -> BrowsingMenuEntry? {
        guard featureFlagger.isFeatureOn(.autofillAccessCredentialManagement) else { return nil }
        return buildAutoFillEntry(useSmallIcon: false)
    }
    
    func makeVPNEntry() -> BrowsingMenuEntry? {
        guard featureFlagger.isFeatureOn(.vpnMenuItem),
              AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge.hasAppStoreProductsAvailable else {
            return nil
        }
        return buildVPNEntry(useSmallIcon: false)
    }
    
    func makeBookmarkEntries(with bookmarksInterface: MenuBookmarksInteracting) -> (bookmark: BrowsingMenuEntry, favorite: BrowsingMenuEntry)? {
        guard let link = validLink else { return nil }
        return buildBookmarkEntries(for: link, with: bookmarksInterface, useSmallIcon: false)
    }
    
    func makeFindInPageEntry() -> BrowsingMenuEntry? {
        guard let link = validLink else { return nil }
        return buildFindInPageEntry(forLink: link, useSmallIcon: false)
    }
    
    func makeDesktopSiteEntry() -> BrowsingMenuEntry? {
        guard let link = validLink else { return nil }
        return buildDesktopSiteEntry(forLink: link, useSmallIcon: false)
    }
    
    func makeZoomEntry() -> BrowsingMenuEntry? {
        guard let link = validLink else { return nil }
        return buildZoomEntry(forLink: link, useSmallIcon: false)
    }
    
    func makeReloadEntry() -> BrowsingMenuEntry? {
        guard appSettings.currentRefreshButtonPosition.isEnabledForBrowsingMenu else { return nil }
        return buildReloadEntry(useSmallIcon: false)
    }
    
    func makeToggleProtectionEntry() -> BrowsingMenuEntry? {
        guard let domain = privacyInfo?.domain else { return nil }
        return buildToggleProtectionEntry(forDomain: domain, useSmallIcon: false)
    }
    
    func makeReportBrokenSiteEntry() -> BrowsingMenuEntry? {
        guard validLink != nil else { return nil }
        return buildReportBrokenSiteEntry(useSmallIcon: false)
    }
    
    func makeUseNewDuckAddressEntry() -> BrowsingMenuEntry? {
        guard let link = validLink else { return nil }
        return buildUseNewDuckAddressEntry(forLink: link, useSmallIcon: false)
    }
    
    func makeKeepSignInEntry() -> BrowsingMenuEntry? {
        guard let link = validLink else { return nil }
        return buildKeepSignInEntry(forLink: link, useSmallIcon: false)
    }
}
