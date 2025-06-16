//
//  PreferencesViewController.swift
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
import BrowserServicesKit
import SwiftUI
import SwiftUIExtensions
import Combine
import DDGSync
import VPN
import AIChat
import Subscription

final class PreferencesViewController: NSViewController {

    weak var delegate: BrowserTabSelectionDelegate?

    let model: PreferencesSidebarModel
    let tabCollectionViewModel: TabCollectionViewModel
    let privacyConfigurationManager: PrivacyConfigurationManaging
    private var selectedTabContentCancellable: AnyCancellable?
    private var selectedPreferencePaneCancellable: AnyCancellable?

    private var bitwardenManager: BWManagement = BWManager.shared

    init(
        syncService: DDGSyncing,
        duckPlayer: DuckPlayer = DuckPlayer.shared,
        tabCollectionViewModel: TabCollectionViewModel,
        privacyConfigurationManager: PrivacyConfigurationManaging,
        aiChatRemoteSettings: AIChatRemoteSettingsProvider = AIChatRemoteSettings(),
        subscriptionManager: any SubscriptionAuthV1toV2Bridge = Application.appDelegate.subscriptionAuthV1toV2Bridge,
        featureFlagger: FeatureFlagger
    ) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.privacyConfigurationManager = privacyConfigurationManager
        model = PreferencesSidebarModel(privacyConfigurationManager: privacyConfigurationManager,
                                        featureFlagger: featureFlagger,
                                        syncService: syncService,
                                        vpnGatekeeper: DefaultVPNFeatureGatekeeper(subscriptionManager: subscriptionManager),
                                        includeDuckPlayer: duckPlayer.shouldDisplayPreferencesSideBar,
                                        includeAIChat: aiChatRemoteSettings.isAIChatEnabled,
                                        subscriptionManager: subscriptionManager)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if !Application.appDelegate.isAuthV2Enabled {
            let prefRootView = Preferences.RootView(model: model,
                                                    subscriptionManager: Application.appDelegate.subscriptionManagerV1!,
                                                    subscriptionUIHandler: Application.appDelegate.subscriptionUIHandler)
            let host = NSHostingView(rootView: prefRootView)
            view.addAndLayout(host)
        } else {
            let prefRootView = Preferences.RootViewV2(model: model,
                                                      subscriptionManager: Application.appDelegate.subscriptionManagerV2!,
                                                      subscriptionUIHandler: Application.appDelegate.subscriptionUIHandler)
            let host = NSHostingView(rootView: prefRootView)
            view.addAndLayout(host)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        model.refreshSections()
        bitwardenManager.refreshStatusIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        selectedTabContentCancellable = model.selectedTabContent
            .dropFirst()
            .sink { [weak self] in
                self?.delegate?.selectedTabContent($0)
            }

        selectedPreferencePaneCancellable = model.$selectedPane
            .dropFirst()
            .sink { [weak self] identifier in
                self?.delegate?.selectedPreferencePane(identifier)
            }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        selectedTabContentCancellable = nil
        selectedPreferencePaneCancellable = nil
    }
}
