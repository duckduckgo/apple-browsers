//
//  DesignSystemImages+Color.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

public extension DesignSystemImages {
    enum Color {
        public enum Size12 {
            public static var chat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .chatColor12)
                    : .init(resource: .chatColor12Legacy)
            }
            public static var chatPinned: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .chatPinnedColor12)
                    : .init(resource: .chatPinnedColor12Legacy)
            }
        }

        public enum Size16 {
            public static var accessibility: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .accessibilityColor16)
                    : .init(resource: .accessibilityColor16Legacy)
            }
            public static var addToDock: DesignSystemImage { .init(resource: .addToDockColor16) }
            public static var adsBlocked: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .adsBlockedColor16)
                    : .init(resource: .adsBlockedColor16Legacy)
            }
            public static var aiChat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiChatColor16)
                    : .init(resource: .aiChatColor16Legacy)
            }
            public static var aiChatToggle: DesignSystemImage { .init(resource: .aiChatToggleColor16) }
            public static var aiChatGradient: DesignSystemImage { .init(resource: .aiChatColorGradient16) }
            public static var aiGeneral: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiGeneralColor16)
                    : .init(resource: .aiGeneralColor16Legacy)
            }
            public static var appearance: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .appearanceColor16)
                    : .init(resource: .appearanceColor16Legacy)
            }
            public static var assist: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .assistColor16)
                    : .init(resource: .assistColor16Legacy)
            }
            public static var autofill: DesignSystemImage { .init(resource: .autofillColor16) }
            public static var bitwarden: DesignSystemImage { .init(resource: .bitwardenColor16) }
            public static var bitwardenLocked: DesignSystemImage { .init(resource: .bitwardenLockedColor16) }
            public static var bookmark: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkColor16)
                    : .init(resource: .bookmarkColor16Legacy)
            }
            public static var bookmarkFavorite: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkFavoriteColor16)
                    : .init(resource: .bookmarkFavoriteColor16Legacy)
            }
            public static var bookmarkImport: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkImportColor16)
                    : .init(resource: .bookmarkImportColor16Legacy)
            }
            public static var bookmarksNew: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarksNewColor16)
                    : .init(resource: .bookmarksNewColor16Legacy)
            }
            public static var browser: DesignSystemImage { .init(resource: .browserColor16) }
            public static var calendarDay: DesignSystemImage { .init(resource: .calendarDayColor16) }
            public static var calendarMonth: DesignSystemImage { .init(resource: .calendarMonthColor16) }
            public static var calendarToday: DesignSystemImage { .init(resource: .calendarTodayColor16) }
            public static var calendarWeek: DesignSystemImage { .init(resource: .calendarWeekColor16) }
            public static var calendarYesterday: DesignSystemImage { .init(resource: .calendarYesterdayColor16) }
            public static var chat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .chatColor16)
                    : .init(resource: .chatColor16Legacy)
            }
            public static var chatPinned: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .chatPinnedColor16)
                    : .init(resource: .chatPinned16Legacy)
            }
            public static var cookie: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .cookieColor16)
                    : .init(resource: .cookieColor16Legacy)
            }
            public static var cookieBlocked: DesignSystemImage { .init(resource: .cookieBlockedColor16) }
            public static var dashboard: DesignSystemImage { .init(resource: .dashboardColor16) }
            public static var databroker: DesignSystemImage { .init(resource: .databrokerColor16) }
            public static var defaultBrowser: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .browserDefaultColor16)
                    : .init(resource: .defaultBrowserColor16Legacy)
            }
            public static var defaultBrowserAlt: DesignSystemImage { .init(resource: .defaultBrowserAltColor16) }
            public static var deviceMobileProtection: DesignSystemImage { .init(resource: .deviceMobileProtectionColor16) }
            public static var document: DesignSystemImage { .init(resource: .documentColor16) }
            public static var downloads: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .downloadsColor16)
                    : .init(resource: .downloadsColor16Legacy)
            }
            public static var duckAI: DesignSystemImage { .init(resource: .duckDuckGoAiColor16) }
            public static var duckDuckGo: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .duckDuckGoColor16)
                    : .init(resource: .duckDuckGoColor16Legacy)
            }
            public static var email: DesignSystemImage { .init(resource: .emailColor16) }
            public static var emailBlock: DesignSystemImage { .init(resource: .emailBlockColor16) }
            public static var emailCheck: DesignSystemImage { .init(resource: .emailCheckColor16) }
            public static var emailProtection: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .emailProtectionColor16)
                    : .init(resource: .emailProtectionColor16Legacy)
            }
            public static var exclamation: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .exclamationColor16)
                    : .init(resource: .exclamationColor16Legacy)
            }
            public static var exclamationHigh: DesignSystemImage { .init(resource: .exclamationHighColor16) }
            public static var exclamationMedium: DesignSystemImage { .init(resource: .exclamationMediumColor16) }
            public static var favorite: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .favoriteColor16)
                    : .init(resource: .favoriteColor16Legacy)
            }
            public static var favoriteGrey: DesignSystemImage { .init(resource: .favoriteGreyColor16) }
            public static var feedback: DesignSystemImage { .init(resource: .feedbackColor16) }
            public static var fewerAds: DesignSystemImage { .init(resource: .fewerAdsColor16) }
            public static var findSearch: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .searchFindColor16)
                    : .init(resource: .findSearchColor16Legacy)
            }
            public static var fire: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .fireColor16)
                    : .init(resource: .fireColor16Legacy)
            }
            public static var folder: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .folderColor16)
                    : .init(resource: .folderColor16Legacy)
            }
            public static var folderWin: DesignSystemImage { .init(resource: .folderWinColor16) }
            public static var globe: DesignSystemImage { .init(resource: .globeColor16) }
            public static var heart: DesignSystemImage { .init(resource: .heartColor16) }
            public static var heartGrey: DesignSystemImage { .init(resource: .heartGreyColor16) }
            public static var hideAIGeneratedImages: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .imageAIBlocked16)
                    : .init(resource: .imageAIBlocked16Legacy)
            }
            public static var history: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .historyColor16)
                    : .init(resource: .historyColor16Legacy)
            }
            public static var home: DesignSystemImage { .init(resource: .homeColor16) }
            public static var hourglass: DesignSystemImage { .init(resource: .hourglassColor16) }
            public static var identityBlockedPIR: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .identityBlockedPIRColor16)
                    : .init(resource: .identityBlockedPIRColor16Legacy)
            }
            public static var identityTheftRestoration: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .identityTheftRestorationColor16)
                    : .init(resource: .identityTheftRestorationColor16Legacy)
            }
            public static var `import`: DesignSystemImage { .init(resource: .importColor16) }
            public static var infoFeedback: DesignSystemImage { .init(resource: .infoFeedbackColor16) }
            public static var key: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .keyColor16)
                    : .init(resource: .keyColor16Legacy)
            }
            public static var linkSecure: DesignSystemImage { .init(resource: .linkSecureColor16) }
            public static var lock: DesignSystemImage { .init(resource: .lockColor16) }
            public static var paidAiChat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .duckDuckGoAiColor16)
                    : .init(resource: .paidAiChatColor16Legacy)
            }
            public static var privacyCheck: DesignSystemImage { .init(resource: .privacyCheckColor16) }
            public static var privacyCheckGray: DesignSystemImage { .init(resource: .privacyCheckGrayColor16) }
            public static var profile: DesignSystemImage { .init(resource: .profileColor16) }
            public static var radar: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .radarColor16)
                    : .init(resource: .radarColor16Legacy)
            }
            public static var releaseNotes: DesignSystemImage { .init(resource: .releaseNotesColor16) }
            public static var rocket: DesignSystemImage { .init(resource: .rocketColor16) }
            public static var sessionRestore: DesignSystemImage { .init(resource: .sessionRestoreColor16) }
            public static var settings: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .settingsColor16)
                    : .init(resource: .settingsColor16Legacy)
            }
            public static var shield: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .shieldColor16)
                    : .init(resource: .shieldColor16Legacy)
            }
            public static var shieldCheck: DesignSystemImage { .init(resource: .shieldCheckColor16) }
            public static var shieldNeutral: DesignSystemImage { .init(resource: .shieldNeutralColor16) }
            public static var shieldNeutralAlert: DesignSystemImage { .init(resource: .shieldNeutralAlertColor16) }
            public static var shopping: DesignSystemImage { .init(resource: .shoppingColor16) }
            public static var siri: DesignSystemImage { .init(resource: .siriColor16) }
            public static var sync: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .syncColor16)
                    : .init(resource: .syncColor16Legacy)
            }
            public static var subscription: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .subscriptionColor16)
                    : .init(resource: .privacyProColor16Legacy)
            }
            public static var survey: DesignSystemImage { .init(resource: .surveyColor16) }
            public static var tabsRecentlyClosed: DesignSystemImage { .init(resource: .tabsReccentlyClosedColor16) }
            public static var thumbsDown: DesignSystemImage { .init(resource: .thumbsDownColor16) }
            public static var thumbsDownNeutral: DesignSystemImage { .init(resource: .thumbsDownNeutralColor16) }
            public static var thumbsUp: DesignSystemImage { .init(resource: .thumbsUpColor16) }
            public static var thumbsUpNeutral: DesignSystemImage { .init(resource: .thumbsUpNeutralColor16) }
            public static var videoPlayer: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .videoPlayerColor16)
                    : .init(resource: .videoPlayerColor16Legacy)
            }
            public static var videoPlayerBlocked: DesignSystemImage { .init(resource: .videoPlayerBlockedColor16) }
            public static var vpn: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .vpnColor16)
                    : .init(resource: .vpnColor16Legacy)
            }
            public static var vpnGray: DesignSystemImage { .init(resource: .vpnGrayColor16) }
            public static var searchFindToggle: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .searchFindColor16)
                    : .init(resource: .searchFindToggleColor16)
            }
        }

        public enum Size24 {
            public static var accessibility: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .accessibilityColor24)
                    : .init(resource: .accessibilityColor24Legacy)
            }
            public static var add: DesignSystemImage { .init(resource: .addColor24) }
            public static var addToDock: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .addToDockColor24)
                    : .init(resource: .addToDockColor24Legacy)
            }
            public static var addWidget: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .addWidgetColor24)
                    : .init(resource: .addWidgetColor24Legacy)
            }
            public static var addressBarBottom: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .addressBarBottomColor24)
                    : .init(resource: .addressBarBottomColor24Legacy)
            }
            public static var adsBlocked: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .adsBlockedColor24)
                    : .init(resource: .adsBlockedColor24Legacy)
            }
            public static var radar: DesignSystemImage { .init(resource: .radarColor24) }
            public static var adsFewer: DesignSystemImage { .init(resource: .adsFewerColor24) }
            public static var aiChat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiChatColor24)
                    : .init(resource: .aiChatColor24Legacy)
            }
            public static var aiChatAdvanced: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiChatAdvancedColor24)
                    : .init(resource: .aiChatAdvancedColor24Legacy)
            }
            public static var aiChatGradient: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiChatColor24)
                    : .init(resource: .aiChatGradientColor24)
            }
            public static var aiGeneral: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiGeneralColor24)
                    : .init(resource: .aiGeneralColor24Legacy)
            }
            public static var announce: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .announceColor24)
                    : .init(resource: .announceColor24Legacy)
            }
            public static var appTP: DesignSystemImage { .init(resource: .appTPColor24) }
            public static var appDuckDuckGo: DesignSystemImage { .init(resource: .appDuckDuckGo24) }
            public static var appearance: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .appearanceColor24)
                    : .init(resource: .appearanceColor24Legacy)
            }
            public static var askSiri: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .askSiriColor24)
                    : .init(resource: .askSiriColor24Legacy)
            }
            public static var autofill: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .autofillColor24)
                    : .init(resource: .autofillColor24Legacy)
            }
            public static var bitwarden: DesignSystemImage { .init(resource: .bitwardenColor24) }
            public static var bookmark: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkColor24)
                    : .init(resource: .bookmarkColor24Legacy)
            }
            public static var bookmarkFavorite: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkFavoriteColor24)
                    : .init(resource: .bookmarkFavoriteColor24Legacy)
            }
            public static var bookmarkImport: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkImportColor24)
                    : .init(resource: .bookmarkImportColor24Legacy)
            }
            public static var bookmarkCheck: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkCheckColor24)
                    : .init(resource: .bookmarkCheckColor24Legacy)
            }
            public static var bookmarks: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarksColor24)
                    : .init(resource: .bookmarksColor24Legacy)
            }
            public static var browser: DesignSystemImage { .init(resource: .browserColor24) }
            public static var browserDefault: DesignSystemImage { .init(resource: .browserDefaultColor24) }
            public static var browserGlobe: DesignSystemImage { .init(resource: .browserGlobeColor24) }
            public static var check: DesignSystemImage { .init(resource: .checkColor24) }
            public static var cookie: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .cookieColor24)
                    : .init(resource: .cookieColor24Legacy)
            }
            public static var cookieBlocked: DesignSystemImage { .init(resource: .cookieBlockedColor24) }
            public static var creditCard: DesignSystemImage { .init(resource: .creditCardColor24) }
            public static var creditCardCheck: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .creditCardCheckColor24)
                    : .init(resource: .creditCardCheckColor24Legacy)
            }
            public static var defaultBrowserMobile: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .defaultBrowserMobileColor24)
                    : .init(resource: .defaultBrowserMobileColor24Legacy)
            }
            public static var deviceAll: DesignSystemImage { .init(resource: .deviceAllColor24) }
            public static var deviceLaptopInstall: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .deviceLaptopInstallColor24)
                    : .init(resource: .deviceLaptopInstallColor24Legacy)
            }
            public static var document: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .documentColor24)
                    : .init(resource: .documentColor24Legacy)
            }
            public static var downloads: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .downloadsColor24)
                    : .init(resource: .downloadsColor24Legacy)
            }
            public static var duckDuckGo: DesignSystemImage { .init(resource: .duckDuckGoColor24) }
            public static var duckAI: DesignSystemImage { .init(resource: .duckAIColor24) }
            public static var email: DesignSystemImage { .init(resource: .emailColor24) }
            public static var emailBlock: DesignSystemImage { .init(resource: .emailBlockColor24) }
            public static var emailCheck: DesignSystemImage { .init(resource: .emailCheckColor24) }
            public static var emailProtection: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .emailProtectionColor24)
                    : .init(resource: .emailProtectionColor24Legacy)
            }
            public static var exclamation: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .exclamationColor24)
                    : .init(resource: .exclamationColor24Legacy)
            }
            public static var exclamationHigh: DesignSystemImage { .init(resource: .exclamationHighColor24) }
            public static var exclamationMedium: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .exclamationMediumColor24)
                    : .init(resource: .exclamationMediumColor24Legacy)
            }
            public static var favorite: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .favoriteColor24)
                    : .init(resource: .favoriteColor24Legacy)
            }
            public static var favoriteGrey: DesignSystemImage { .init(resource: .favoriteGreyColor24) }
            public static var feedback: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .feedbackColor24)
                    : .init(resource: .feedbackColor24Legacy)
            }
            public static var fire: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .fireColor24)
                    : .init(resource: .fireColor24Legacy)
            }
            public static var findSearch: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .findSearchColor24)
                    : .init(resource: .findSearchColor24Legacy)
            }
            public static var folder: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .folderColor24)
                    : .init(resource: .folderColor24Legacy)
            }
            public static var folderWin: DesignSystemImage { .init(resource: .folderWinColor24) }
            public static var globe: DesignSystemImage { .init(resource: .globeColor24) }
            public static var heart: DesignSystemImage { .init(resource: .heartColor24) }
            public static var heartGray: DesignSystemImage { .init(resource: .heartGrayColor24) }
            public static var history: DesignSystemImage { .init(resource: .historyColor24) }
            public static var home: DesignSystemImage { .init(resource: .homeColor24) }
            public static var homescreenLock: DesignSystemImage { .init(resource: .homescreenLockColor24) }
            public static var identityBlockedPIR: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .identityBlockedPIRColor24)
                    : .init(resource: .identityBlockedPIRColor24Legacy)
            }
            public static var identityTheftRestoration: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .identityTheftRestorationColor24)
                    : .init(resource: .identityTheftRestorationColor24Legacy)
            }
            public static var `import`: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .importColor24)
                    : .init(resource: .importColor24Legacy)
            }
            public static var info: DesignSystemImage { .init(resource: .infoRecolorable24)}
            public static var key: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .keyColor24)
                    : .init(resource: .keyColor24Legacy)
            }
            public static var keyAuto: DesignSystemImage { .init(resource: .keyAutoColor24) }
            public static var keyCheck: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .keyCheckColor24)
                    : .init(resource: .keyCheckColor24Legacy)
            }
            public static var keyImport: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .keyColorImport24)
                    : .init(resource: .keyColorImport24Legacy)
            }
            public static var lightning: DesignSystemImage { .init(resource: .lightningColor24) }
            public static var lock: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .lockColor24)
                    : .init(resource: .lockColor24Legacy)
            }
            public static var microphone: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .microphoneColor24)
                    : .init(resource: .microphoneColor24Legacy)
            }
            public static var microphoneAdd: DesignSystemImage { .init(resource: .microphoneAdd24) }
            public static var microphoneRemove: DesignSystemImage { .init(resource: .microphoneRemove24) }
            public static var paidAiChat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .paidAiChatColor24)
                    : .init(resource: .paidAiChatColor24Legacy)
            }
            public static var platformApple: DesignSystemImage { .init(resource: .platformAppleColor24) }
            public static var platformMacOS: DesignSystemImage { .init(resource: .platformMacOSColor24) }
            public static var platformWindows: DesignSystemImage { .init(resource: .platformWindowsColor24) }
            public static var privacyCheck: DesignSystemImage { .init(resource: .privacyCheckColor24) }
            public static var privacyCheckGreyscale: DesignSystemImage { .init(resource: .privacyCheckGreyscaleColor24) }
            public static var profile: DesignSystemImage { .init(resource: .profileColor24) }
            public static var rocket: DesignSystemImage { .init(resource: .rocketColor24) }
            public static var sessionRestore: DesignSystemImage { .init(resource: .sessionRestoreColor24) }
            public static var settings: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .settingsColor24)
                    : .init(resource: .settingsColor24Legacy)
            }
            public static var shield: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .shieldColor24)
                    : .init(resource: .shieldColor24Legacy)
            }
            public static var shieldCheck: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .shieldCheckColor24)
                    : .init(resource: .shieldCheckColor24Legacy)
            }
            public static var shieldNeutral: DesignSystemImage { .init(resource: .shieldNeutralColor24) }
            public static var shieldNeutralAlert: DesignSystemImage { .init(resource: .shieldNeutralAlertColor24) }
            public static var shopping: DesignSystemImage { .init(resource: .shoppingColor24) }
            public static var shoppingDownload: DesignSystemImage { .init(resource: .shoppingDownloadColor24) }
            public static var siri: DesignSystemImage { .init(resource: .siriColor24) }
            public static var subscription: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .privacyProColor24)
                    : .init(resource: .privacyProColor24Legacy)
            }
            public static var sync: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .syncColor24)
                    : .init(resource: .syncColor24Legacy)
            }
            public static var videoPlayer: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .videoPlayerColor24)
                    : .init(resource: .videoPlayerColor24Legacy)
            }
            public static var videoPlayerBlocked: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .videoPlayerBlockedColor24)
                    : .init(resource: .videoPlayerBlockedColor24Legacy)
            }
            public static var vpn: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .vpnColor24)
                    : .init(resource: .vpnColor24Legacy)
            }
            public static var vpnGrayscale: DesignSystemImage { .init(resource: .vpnGrayscaleColor24) }
        }

        public enum Size32 {
            public static var duckDuckAI: DesignSystemImage { .init(resource: .duckAIColor32) }
            public static var duckDuckGo: DesignSystemImage { .init(resource: .duckDuckGoColor32) }
            public static var document: DesignSystemImage { .init(resource: .documentColor32) }
            public static var shieldUtility: DesignSystemImage { .init(resource: .shieldUtilityColor32) }
        }

        public enum Size72 {
            public static var fire: DesignSystemImage { .init(resource: .fireColor72) }
        }

        public enum Size96 {
            public static var announcement: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .announcement96)
                    : .init(resource: .announcement96Legacy)
            }
            public static var browserWarn: DesignSystemImage {
                .init(resource: .browserWarn96)
            }
            public static var cookieCheckFeature: DesignSystemImage { .init(resource: .cookieCheckFeature96) }
            public static var daxDuckAIStacked: DesignSystemImage { .init(resource: .daxDuckAIStacked96) }
            public static var duckAIDDGHero: DesignSystemImage { .init(resource: .duckAIDDGHeroColor96) }
            public static var duckAI: DesignSystemImage { .init(resource: .duckAI96) }
            public static var duckAISubscription: DesignSystemImage { .init(resource: .duckAISubscription96) }
            public static var duckDuckGo: DesignSystemImage { .init(resource: .duckDuckGo96) }
            public static var extensionChrome: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .extensionChrome96)
                    : .init(resource: .extensionChrome96Legacy)
            }
            public static var extensionSafari: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .extensionSafari96)
                    : .init(resource: .extensionSafari96Legacy)
            }
            public static var fireTab: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .fireWindowLightPhone96)
                    : .init(resource: .fireWindowLightPhone96Legacy)
            }
            public static var fire: DesignSystemImage { .init(resource: .fire96) }
            public static var passwordsAppFeature: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .passwordsApp96)
                    : .init(resource: .passwordsAppFeature96)
            }
            public static var passwordsKeychainFeature: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .passwordsKeychainFeature96)
                    : .init(resource: .passwordsKeychainFeature96Legacy)
            }
            public static var syncPasswordsDesktop: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .desktopSyncPasswords96)
                    : .init(resource: .syncPasswordsDesktop96Legacy)
            }
            public static var youtubeClean: DesignSystemImage { .init(resource: .youTubeClean96) }
        }

        public enum Size128 {
            public static var duckAIPaid: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .duckDuckGoDuckAI128)
                    : .init(resource: .duckAIPaid128)
            }
            public static var success: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .success128)
                    : .init(resource: .success128Legacy)
            }
            public static var fileDrag: DesignSystemImage { .init(resource: .fileDrag128) }
            public static var fileDrop: DesignSystemImage { .init(resource: .fileDrop128) }
            public static var fileIssue: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .fileIssue128)
                    : .init(resource: .fileIssue128Legacy)
            }
            public static var bringStuff: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bringStuff128)
                    : .init(resource: .bringStuff128Legacy)
            }
            public static var bringStuffDownload: DesignSystemImage { .init(resource: .bringStuffDownload128) }
            public static var fire: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .fire128)
                    : .init(resource: .fire128Legacy)
            }
            public static var lockLocked: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .lockLocked128)
                    : .init(resource: .lockLocked128Legacy)
            }
            public static var networkProtectionVPN: DesignSystemImage { .init(resource: .networkProtectionVPN128) }
            public static var networkProtectionVPNDisabled: DesignSystemImage { .init(resource: .networkProtectionVPNDisabled128) }
            public static var youTubeAdBlockWarning: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .youTubeWarning128)
                    : .init(resource: .youTubeWarningFeature128)
            }
        }
    }
}
