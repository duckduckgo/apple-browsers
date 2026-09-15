//
//  NewTabPageBuilder.swift
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

import AIChat
import Bookmarks
import BrowserServicesKit
import Core
import Onboarding
import RemoteMessaging
import Subscription

/// Builds the New Tab Page shown in a browser tab.
struct NewTabPageBuilder {

    let favoritesInteractionModel: FavoritesListInteracting
    let homePageMessagesConfiguration: HomePageMessagesConfiguration
    let subscriptionDataReporting: SubscriptionDataReporting
    let daxDialogsManager: DaxDialogsManaging
    let onboardingFlowProvider: OnboardingFlowProviding
    let faviconLoader: FavoritesFaviconLoading
    let faviconsCache: FavoritesFaviconCaching
    let remoteMessagingActionHandler: RemoteMessagingActionHandling
    let remoteMessagingImageLoader: RemoteMessagingImageLoading
    let remoteMessagingPixelReporter: RemoteMessagingPixelReporting?
    let appSettings: AppSettings
    let aiChatSettings: AIChatSettingsProvider
    let subscriptionManager: any SubscriptionManager
    let internalUserCommands: URLBasedDebugCommands
    let floatingUIManager: FloatingUIManaging
    let redesignFeature: NewTabPageRedesignFeatureProviding

    /// `daxDialogFactory` is supplied per page rather than stored.
    func makeNewTabPage(tab: Tab,
                        openedAfterIdle: Bool,
                        daxDialogFactory: any NewTabDaxDialogProviding) -> any NewTabPage {
        // Fire tabs are excluded because their empty state is drawn elsewhere and would cover the
        // page.
        if !tab.fireTab, redesignFeature.isAvailable {
            return makeRedesignedNewTabPage()
        }

        return makeCurrentNewTabPage(tab: tab,
                                     openedAfterIdle: openedAfterIdle,
                                     daxDialogFactory: daxDialogFactory)
    }

    private func makeRedesignedNewTabPage() -> any NewTabPage {
        RedesignedNewTabPageViewController(blocks: [
            SwiftUIBlock(id: "daxLogo", rootView: NewTabPageDaxLogoView())
        ])
    }

    private func makeCurrentNewTabPage(tab: Tab,
                                       openedAfterIdle: Bool,
                                       daxDialogFactory: any NewTabDaxDialogProviding) -> any NewTabPage {
        NewTabPageViewController(isFocussedState: false,
                                 openedAfterIdle: openedAfterIdle,
                                 dismissKeyboardOnScroll: true,
                                 tab: tab,
                                 interactionModel: favoritesInteractionModel,
                                 homePageMessagesConfiguration: homePageMessagesConfiguration,
                                 subscriptionDataReporting: subscriptionDataReporting,
                                 newTabDialogFactory: daxDialogFactory,
                                 daxDialogsManager: daxDialogsManager,
                                 onboardingFlowProvider: onboardingFlowProvider,
                                 faviconLoader: faviconLoader,
                                 remoteMessagingActionHandler: remoteMessagingActionHandler,
                                 remoteMessagingImageLoader: remoteMessagingImageLoader,
                                 remoteMessagingPixelReporter: remoteMessagingPixelReporter,
                                 appSettings: appSettings,
                                 faviconsCache: faviconsCache,
                                 subscriptionManager: subscriptionManager,
                                 internalUserCommands: internalUserCommands,
                                 // Read per page: the setting can change while the app runs.
                                 narrowLayoutInLandscape: aiChatSettings.isAIChatSearchInputUserSettingsEnabled,
                                 floatingUIManager: floatingUIManager)
    }
}
