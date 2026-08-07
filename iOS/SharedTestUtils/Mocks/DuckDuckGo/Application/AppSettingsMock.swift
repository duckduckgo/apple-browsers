//
//  AppSettingsMock.swift
//  DuckDuckGo
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

import Bookmarks
import Foundation
import Onboarding
import WebExtensions
@testable import DuckDuckGo

class AppSettingsMock: AppSettings {

    var defaultTextZoomLevel: DuckDuckGo.TextZoomLevel = .percent100

    var recentlyVisitedSites: Bool = false

    var isSyncBookmarksPaused: Bool = false

    var isSyncCredentialsPaused: Bool = false

    var currentAddressBarPosition: DuckDuckGo.AddressBarPosition = .top

    var keepAddressBarVisibleOnIPad: Bool = false

    var currentRefreshButtonPosition: DuckDuckGo.RefreshButtonPosition = .addressBar

    var showFullSiteAddress: Bool = false

    var showTrackersBlockedAnimation: Bool = true

    var autofillCredentialsEnabled: Bool = false
    
    var autofillCredentialsSavePromptShowAtLeastOnce: Bool = false
    
    var autofillCredentialsHasBeenEnabledAutomaticallyIfNecessary: Bool = false

    var autofillIsNewInstallForOnByDefault: Bool?

    func setAutofillIsNewInstallForOnByDefault() { }

    var autofillCreditCardsEnabled: Bool = false
    
    var autocomplete: Bool = true

    var currentThemeStyle: DuckDuckGo.ThemeStyle = .systemDefault

    var autoClearAction: DuckDuckGo.FireRequest.Options = .data

    var autoClearTiming: DuckDuckGo.AutoClearSettingsModel.Timing = .delay15min

    var longPressPreviews: Bool = false

    var allowUniversalLinks: Bool = false

    var sendDoNotSell: Bool = true

    var currentFireButtonAnimation: DuckDuckGo.FireButtonAnimationType = .fireRising

    var textSize: Int = 14

    var favoritesDisplayMode: FavoritesDisplayMode = .displayNative(.mobile)

    var autofill: Bool = false

    var autofillImportViaSyncStart: Date?

    func clearAutofillImportViaSyncStart() {
        autofillImportViaSyncStart = nil
    }

    var voiceSearchEnabled: Bool = false

    var widgetInstalled: Bool = false
    func isWidgetInstalled() async -> Bool {
        widgetInstalled
    }
    
    var cookiePopupPreference: CookiePopupPreference = .default

    var autoconsentEnabled: Bool {
        get { cookiePopupPreference.isBlockingEnabled }
        set { cookiePopupPreference = newValue ? .default : .off }
    }

    var crashCollectionOptInStatus: CrashCollectionOptInStatus = .undetermined
    var crashCollectionShouldRevertOptedInStatusTrigger: Int = 0

    var newTabPageSectionsEnabled: Bool = false

    var duckPlayerMode: DuckDuckGo.DuckPlayerMode = .alwaysAsk
    var duckPlayerAskModeOverlayHidden: Bool = false
    var duckPlayerOpenInNewTab: Bool = false
    var duckPlayerNativeUI: Bool = false
    var duckPlayerAutoplay: Bool = false
    
    var newTabPageShortcutsSettings: Data?
    var newTabPageSectionsSettings: Data?

    var newTabPageIntroMessageEnabled: Bool?
    var newTabPageIntroMessageSeenCount: Int = 0

    var onboardingUserType: OnboardingUserType = .notSet
    var onboardingForceRestorePromptEligible: Bool = false
    var onboardingFlowType: OnboardingFlowType?

    var duckPlayerNativeUISERPEnabled: Bool = true
    var duckPlayerNativeYoutubeMode: DuckDuckGo.NativeDuckPlayerYoutubeMode = .allCases.first!
    var duckPlayerNativeUIPrimingModalPresentationEventCount: Int = 0
    var duckPlayerNativeUIPrimingModalLastPresentationTime: Int = 0
    var duckPlayerPillDismissCount: Int = 0
    var duckPlayerWelcomeMessageShown: Bool = false
    var duckPlayerVariant: DuckDuckGo.DuckPlayerVariant = .classicWeb
    var duckPlayerPrimingMessagePresented: Bool = false
    var duckPlayerControlsVisible: Bool = true
    var duckPlayerNativeUIWasUsed: Bool = false
    var duckPlayerNativeUISettingsMapped: Bool = false
    var autoClearAIChatHistory: Bool = false
}
