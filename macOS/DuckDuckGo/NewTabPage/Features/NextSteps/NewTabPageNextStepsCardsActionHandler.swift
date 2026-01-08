//
//  NewTabPageNextStepsCardsActionHandler.swift
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

import BrowserServicesKit
import Foundation
import NewTabPage
import PrivacyConfig
import Subscription

protocol NewTabPageNextStepsCardsActionHandling {
    /// Performs the action associated with the given card.
    /// - Parameters:
    ///   - card: The identifier of the card for which to perform the action.
    ///   - completion: A closure to be called upon completion of the action, if needed to refresh the cards state.
    @MainActor func performAction(for card: NewTabPageDataModel.CardID, refreshCardsAction: (() -> Void)?)
}

protocol NewTabPageNextStepsCardsTabOpening {
    @MainActor
    func openTab(_ tab: Tab)
}

final class NewTabPageNextStepsCardsActionHandler: NewTabPageNextStepsCardsActionHandling {
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let dockCustomizer: DockCustomization
    private let dataImportProvider: DataImportStatusProviding
    private let tabOpener: NewTabPageNextStepsCardsTabOpening
    private let pixelHandler: NewTabPageNextStepsCardsPixelHandling

    var duckPlayerURL: String {
        let duckPlayerSettings = privacyConfigurationManager.privacyConfig.settings(for: .duckPlayer)
        return duckPlayerSettings["tryDuckPlayerLink"] as? String ?? "https://www.youtube.com/watch?v=yKWIA-Pys4c"
    }

    init(defaultBrowserProvider: DefaultBrowserProvider,
         dockCustomizer: DockCustomization,
         dataImportProvider: DataImportStatusProviding,
         tabOpener: NewTabPageNextStepsCardsTabOpening,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         pixelHandler: NewTabPageNextStepsCardsPixelHandling) {

        self.defaultBrowserProvider = defaultBrowserProvider
        self.dockCustomizer = dockCustomizer
        self.dataImportProvider = dataImportProvider
        self.tabOpener = tabOpener
        self.privacyConfigurationManager = privacyConfigurationManager
        self.pixelHandler = pixelHandler
    }

    @MainActor func performAction(for card: NewTabPageDataModel.CardID, refreshCardsAction: (() -> Void)?) {
        pixelHandler.fireNextStepsCardClickedPixel(card)
        switch card {
        case .defaultApp:
            performDefaultBrowserAction()
        case .addAppToDockMac:
            performDockAction()
        case .bringStuff:
            performImportBookmarksAndPasswordsAction(completion: refreshCardsAction)
        case .duckplayer:
            performDuckPlayerAction()
        case .emailProtection:
            performEmailProtectionAction()
        case .subscription:
            performSubscriptionAction()
        }
    }
}

private extension NewTabPageNextStepsCardsActionHandler {
    func performDefaultBrowserAction() {
        do {
            pixelHandler.fireDefaultBrowserRequestedPixel()
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }

    func performImportBookmarksAndPasswordsAction(completion: (() -> Void)?) {
        dataImportProvider.showImportWindow(customTitle: nil, completion: completion)
    }

    @MainActor
    func performDuckPlayerAction() {
        if let videoUrl = URL(string: duckPlayerURL) {
            let tab = Tab(content: .url(videoUrl, source: .link), shouldLoadInBackground: true)
            tabOpener.openTab(tab)
        }
    }

    @MainActor
    func performEmailProtectionAction() {
        let tab = Tab(content: .url(EmailUrls().emailProtectionLink, source: .ui), shouldLoadInBackground: true)
        tabOpener.openTab(tab)
    }

    func performDockAction() {
        pixelHandler.fireAddedToDockPixel()
        dockCustomizer.addToDock()
    }

    @MainActor
    func performSubscriptionAction() {
        pixelHandler.fireSubscriptionCardClickedPixel()
        guard let url = SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.newTabPageNextStepsCard.rawValue)?.url else {
            return
        }

        let tab = Tab(content: .url(url, source: .link), shouldLoadInBackground: true)
        tabOpener.openTab(tab)
    }
}
