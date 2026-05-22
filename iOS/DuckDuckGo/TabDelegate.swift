//
//  TabDelegate.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import WebKit
import Core
import BrowserServicesKit
import PrivacyDashboard

enum TabClosingBehavior {
    case createEmptyTabAtSamePosition
    case createOrReuseEmptyTab
    case onlyClose
    case createNewChat
}

protocol TabDelegate: AnyObject {

    func tabWillRequestNewTab(_ tab: TabViewController) -> UIKeyModifierFlags?

    func tabDidRequestNewTab(_ tab: TabViewController)
    
    func newTab(reuseExisting: Bool)

    func tabDidRequestActivate(_ tab: TabViewController)

    func tab(_ tab: TabViewController,
             didRequestNewWebViewWithConfiguration configuration: WKWebViewConfiguration,
             for navigationAction: WKNavigationAction,
             inheritingAttribution: AdClickAttributionLogic.State?) -> WKWebView?

    func tabDidRequestClose(_ tab: Tab,
                            behavior: TabClosingBehavior,
                            clearTabHistory: Bool)

    func tab(_ tab: TabViewController,
             didRequestNewTabForUrl url: URL,
             openedByPage: Bool,
             inheritingAttribution: AdClickAttributionLogic.State?)

    func tab(_ tab: TabViewController,
             didRequestNewBackgroundTabForUrl url: URL,
             inheritingAttribution: AdClickAttributionLogic.State?)

    func tab(_ tab: TabViewController,
             didRequestNewFireTabForUrl url: URL,
             inheritingAttribution: AdClickAttributionLogic.State?)

    func tabLoadingStateDidChange(tab: TabViewController)

    /// Called once per settled navigation: WKNavigationDelegate didFinish or didFail.
    /// Fired regardless of whether the tab is current. Use this to persist tab state
    /// after a navigation resolves, not on every loading-state tick.
    func tabDidFinishNavigation(_ tab: TabViewController)

    func tab(_ tab: TabViewController, didUpdatePreview preview: UIImage)

    func tab(_ tab: TabViewController, didChangePrivacyInfo privacyInfo: PrivacyInfo?)
    
    /// Called when a tab extracts a Dax Easter Egg logo URL from the current page.
    /// This occurs when the DaxEasterEggHandler finds a dynamic logo on search result pages.
    ///
    /// - Parameters:
    ///   - tab: The tab that extracted the logo URL
    ///   - logoURL: The extracted logo URL, or nil if no logo was found or the page reset to default
    func tab(_ tab: TabViewController, didExtractDaxEasterEggLogoURL logoURL: String?)

    func tabDidRequestReportBrokenSite(tab: TabViewController)

    func tab(_ tab: TabViewController, didRequestToggleReportWithCompletionHandler completionHandler: @escaping (Bool) -> Void)

    func tabDidRequestBookmarks(tab: TabViewController)
    
    func tabDidRequestEditBookmark(tab: TabViewController)
    
    func tabDidRequestDownloads(tab: TabViewController)

    func tabDidRequestAIChat(tab: TabViewController)

    func tab(_ tab: TabViewController,
             didRequestAutofillLogins account: SecureVaultModels.WebsiteAccount?,
             source: AutofillSettingsSource,
             extensionPromotionManager: AutofillExtensionPromotionManaging?)

    func tab(_ tab: TabViewController,
             didRequestDataImport source: DataImportViewModel.ImportScreen,
             onFinished: @escaping () -> Void,
             onCancelled: @escaping () -> Void)

    func tabDidRequestSettings(tab: TabViewController)

    func tab(_ tab: TabViewController,
             didRequestSettingsToLogins account: SecureVaultModels.WebsiteAccount,
             source: AutofillSettingsSource)

    func tab(_ tab: TabViewController,
             didRequestSettingsToCreditCards card: SecureVaultModels.CreditCard,
             source: AutofillSettingsSource)

    func tabDidRequestSettingsToCreditCardManagement(_ tab: TabViewController,
                                                     source: AutofillSettingsSource)

    func tabDidRequestSettingsToVPN(_ tab: TabViewController)

    func tabDidRequestSettingsToAIChat(_ tab: TabViewController)

    func tabDidRequestSettingsToSync(_ tab: TabViewController)

    func tabDidRequestFindInPage(tab: TabViewController)
    func closeFindInPage(tab: TabViewController)

    func tabContentProcessDidTerminate(tab: TabViewController)

    /// User activated an in-page link in this tab.
    func tabDidEngageWithPage(_ tab: TabViewController)
    
    func tabDidRequestFireButtonPulse(tab: TabViewController)

    func tabDidRequestDeleteContextualChat(tab: TabViewController, chatID: String)

    func tabDidRequestPrivacyDashboardButtonPulse(tab: TabViewController, animated: Bool)

    func tabDidRequestSearchBarRect(tab: TabViewController) -> CGRect

    func tab(_ tab: TabViewController,
             didRequestPresentingTrackerAnimation privacyInfo: PrivacyInfo,
             isCollapsing: Bool)

    func tabDidRequestPresentingYouTubeAdBlockAnimation(tab: TabViewController)

    func tabDidRequestShowingMenuHighlighter(tab: TabViewController)
    
    func tab(_ tab: TabViewController, didRequestPresentingAlert alert: UIAlertController)

    func tabCheckIfItsBeingCurrentlyPresented(_ tab: TabViewController) -> Bool
    
    func showBars()

    func tab(_ tab: TabViewController, didRequestLoadURL url: URL)
    func tab(_ tab: TabViewController, didRequestLoadQuery query: String)

    func tabDidRequestRefresh(tab: TabViewController)
    func tabDidRequestNavigationToDifferentSite(tab: TabViewController)
    
    var isAIChatEnabled: Bool { get }

    var isEmailProtectionSignedIn: Bool { get }
    func tabDidRequestNewPrivateEmailAddress(tab: TabViewController)

    func tabDidRequestFireMode(tab: TabViewController)
}

extension TabDelegate {

    func tabDidRequestClose(_ tab: TabViewController) {
        tabDidRequestClose(tab.tabModel, behavior: .onlyClose, clearTabHistory: true)
    }

    func tabDidFinishNavigation(_ tab: TabViewController) {}

}
