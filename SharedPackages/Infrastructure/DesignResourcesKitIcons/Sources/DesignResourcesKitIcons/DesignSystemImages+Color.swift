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
            public static var chat: DesignSystemImage { .init(resource: .chatColor12) }
            public static var chatPinned: DesignSystemImage { .init(resource: .chatPinned12) }
        }

        public enum Size16 {
            public static var accessibility: DesignSystemImage { .init(resource: .accessibilityColor16) }
            public static var addToDock: DesignSystemImage { .init(resource: .addToDockColor16) }
            public static var adsBlocked: DesignSystemImage { .init(resource: .adsBlockedColor16) }
            public static var aiChat: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiChatColor16)
                    : .init(resource: .aiChatColor16Legacy)
            }
            public static var aiChatToggle: DesignSystemImage { .init(resource: .aiChatToggleColor16) }
            public static var aiChatGradient: DesignSystemImage { .init(resource: .aiChatColorGradient16) }
            public static var aiGeneral: DesignSystemImage { .init(resource: .aiGeneralColor16) }
            public static var appearance: DesignSystemImage { .init(resource: .appearanceColor16) }
            public static var assist: DesignSystemImage { .init(resource: .assistColor16) }
            public static var autofill: DesignSystemImage { .init(resource: .autofillColor16) }
            public static var bitwarden: DesignSystemImage { .init(resource: .bitwardenColor16) }
            public static var bitwardenLocked: DesignSystemImage { .init(resource: .bitwardenLockedColor16) }
            public static var bookmark: DesignSystemImage { .init(resource: .bookmarkColor16) }
            public static var bookmarkFavorite: DesignSystemImage { .init(resource: .bookmarkFavoriteColor16) }
            public static var bookmarkImport: DesignSystemImage { .init(resource: .bookmarkImportColor16) }
            public static var bookmarksNew: DesignSystemImage { .init(resource: .bookmarksNewColor16) }
            public static var browser: DesignSystemImage { .init(resource: .browserColor16) }
            public static var calendarDay: DesignSystemImage { .init(resource: .calendarDayColor16) }
            public static var calendarMonth: DesignSystemImage { .init(resource: .calendarMonthColor16) }
            public static var calendarToday: DesignSystemImage { .init(resource: .calendarTodayColor16) }
            public static var calendarWeek: DesignSystemImage { .init(resource: .calendarWeekColor16) }
            public static var calendarYesterday: DesignSystemImage { .init(resource: .calendarYesterdayColor16) }
            public static var chat: DesignSystemImage { .init(resource: .chatColor16) }
            public static var chatPinned: DesignSystemImage { .init(resource: .chatPinned16) }
            public static var cookie: DesignSystemImage { .init(resource: .cookieColor16) }
            public static var cookieBlocked: DesignSystemImage { .init(resource: .cookieBlockedColor16) }
            public static var dashboard: DesignSystemImage { .init(resource: .dashboardColor16) }
            public static var databroker: DesignSystemImage { .init(resource: .databrokerColor16) }
            public static var defaultBrowser: DesignSystemImage { .init(resource: .defaultBrowserColor16) }
            public static var defaultBrowserAlt: DesignSystemImage { .init(resource: .defaultBrowserAltColor16) }
            public static var deviceMobileProtection: DesignSystemImage { .init(resource: .deviceMobileProtectionColor16) }
            public static var document: DesignSystemImage { .init(resource: .documentColor16) }
            public static var downloads: DesignSystemImage { .init(resource: .downloadsColor16) }
            public static var duckDuckGo: DesignSystemImage { .init(resource: .duckDuckGoColor16) }
            public static var email: DesignSystemImage { .init(resource: .emailColor16) }
            public static var emailBlock: DesignSystemImage { .init(resource: .emailBlockColor16) }
            public static var emailCheck: DesignSystemImage { .init(resource: .emailCheckColor16) }
            public static var emailProtection: DesignSystemImage { .init(resource: .emailProtectionColor16) }
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
            public static var findSearch: DesignSystemImage { .init(resource: .findSearchColor16) }
            public static var fire: DesignSystemImage { .init(resource: .fireColor16) }
            public static var folder: DesignSystemImage { .init(resource: .folderColor16) }
            public static var folderWin: DesignSystemImage { .init(resource: .folderWinColor16) }
            public static var globe: DesignSystemImage { .init(resource: .globeColor16) }
            public static var heart: DesignSystemImage { .init(resource: .heartColor16) }
            public static var heartGrey: DesignSystemImage { .init(resource: .heartGreyColor16) }
            public static var hideAIGeneratedImages: DesignSystemImage { .init(resource: .imageAIBlocked16) }
            public static var history: DesignSystemImage { .init(resource: .historyColor16) }
            public static var home: DesignSystemImage { .init(resource: .homeColor16) }
            public static var hourglass: DesignSystemImage { .init(resource: .hourglassColor16) }
            public static var identityBlockedPIR: DesignSystemImage { .init(resource: .identityBlockedPIRColor16) }
            public static var identityTheftRestoration: DesignSystemImage { .init(resource: .identityTheftRestorationColor16) }
            public static var `import`: DesignSystemImage { .init(resource: .importColor16) }
            public static var infoFeedback: DesignSystemImage { .init(resource: .infoFeedbackColor16) }
            public static var key: DesignSystemImage { .init(resource: .keyColor16) }
            public static var linkSecure: DesignSystemImage { .init(resource: .linkSecureColor16) }
            public static var lock: DesignSystemImage { .init(resource: .lockColor16) }
            public static var paidAiChat: DesignSystemImage { .init(resource: .paidAiChatColor16) }
            public static var privacyCheck: DesignSystemImage { .init(resource: .privacyCheckColor16) }
            public static var privacyCheckGray: DesignSystemImage { .init(resource: .privacyCheckGrayColor16) }
            public static var profile: DesignSystemImage { .init(resource: .profileColor16) }
            public static var radar: DesignSystemImage { .init(resource: .radarColor16) }
            public static var releaseNotes: DesignSystemImage { .init(resource: .releaseNotesColor16) }
            public static var rocket: DesignSystemImage { .init(resource: .rocketColor16) }
            public static var sessionRestore: DesignSystemImage { .init(resource: .sessionRestoreColor16) }
            public static var settings: DesignSystemImage { .init(resource: .settingsColor16) }
            public static var shield: DesignSystemImage { .init(resource: .shieldColor16) }
            public static var shieldCheck: DesignSystemImage { .init(resource: .shieldCheckColor16) }
            public static var shieldNeutral: DesignSystemImage { .init(resource: .shieldNeutralColor16) }
            public static var shieldNeutralAlert: DesignSystemImage { .init(resource: .shieldNeutralAlertColor16) }
            public static var shopping: DesignSystemImage { .init(resource: .shoppingColor16) }
            public static var siri: DesignSystemImage { .init(resource: .siriColor16) }
            public static var sync: DesignSystemImage { .init(resource: .syncColor16) }
            public static var subscription: DesignSystemImage { .init(resource: .privacyProColor16) }
            public static var survey: DesignSystemImage { .init(resource: .surveyColor16) }
            public static var tabsRecentlyClosed: DesignSystemImage { .init(resource: .tabsReccentlyClosedColor16) }
            public static var thumbsDown: DesignSystemImage { .init(resource: .thumbsDownColor16) }
            public static var thumbsDownNeutral: DesignSystemImage { .init(resource: .thumbsDownNeutralColor16) }
            public static var thumbsUp: DesignSystemImage { .init(resource: .thumbsUpColor16) }
            public static var thumbsUpNeutral: DesignSystemImage { .init(resource: .thumbsUpNeutralColor16) }
            public static var videoPlayer: DesignSystemImage { .init(resource: .videoPlayerColor16) }
            public static var videoPlayerBlocked: DesignSystemImage { .init(resource: .videoPlayerBlockedColor16) }
            public static var vpn: DesignSystemImage { .init(resource: .vpnColor16) }
            public static var vpnGray: DesignSystemImage { .init(resource: .vpnGrayColor16) }
            public static var searchFindToggle: DesignSystemImage { .init(resource: .searchFindToggleColor16) }
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
            public static var addWidget: DesignSystemImage { .init(resource: .addWidgetColor24) }
            public static var addressBarBottom: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .addressBarBottomColor24)
                    : .init(resource: .addressBarBottomColor24Legacy)
            }
            public static var adsBlocked: DesignSystemImage { .init(resource: .adsBlockedColor24) }
            public static var radar: DesignSystemImage { .init(resource: .radarColor24) }
            public static var adsFewer: DesignSystemImage { .init(resource: .adsFewerColor24) }
            public static var aiChat: DesignSystemImage { .init(resource: .aiChatColor24) }
            public static var aiChatAdvanced: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .aiChatAdvancedColor24)
                    : .init(resource: .aiChatAdvancedColor24Legacy)
            }
            public static var aiChatGradient: DesignSystemImage { .init(resource: .aiChatGradientColor24) }
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
            public static var bookmark: DesignSystemImage { .init(resource: .bookmarkColor24) }
            public static var bookmarkFavorite: DesignSystemImage { .init(resource: .bookmarkFavoriteColor24) }
            public static var bookmarkImport: DesignSystemImage { .init(resource: .bookmarkImportColor24) }
            public static var bookmarkCheck: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .bookmarkCheckColor24)
                    : .init(resource: .bookmarkCheckColor24Legacy)
            }
            public static var bookmarks: DesignSystemImage { .init(resource: .bookmarksColor24) }
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
            public static var defaultBrowserMobile: DesignSystemImage { .init(resource: .defaultBrowserMobileColor24) }
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
            public static var exclamationMedium: DesignSystemImage { .init(resource: .exclamationMediumColor24) }
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
            public static var `import`: DesignSystemImage { .init(resource: .importColor24) }
            public static var info: DesignSystemImage { .init(resource: .infoRecolorable24)}
            public static var key: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .keyColor24)
                    : .init(resource: .keyColor24Legacy)
            }
            public static var keyAuto: DesignSystemImage { .init(resource: .keyAutoColor24) }
            public static var keyCheck: DesignSystemImage {
                .init(resource: .keyCheckColor24)
            }
            public static var keyImport: DesignSystemImage { .init(resource: .keyColorImport24) }
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
            public static var shieldCheck: DesignSystemImage { .init(resource: .shieldCheckColor24) }
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
                    ? .init(resource: .fireTabColor96)
                    : .init(resource: .fireTabColor96Legacy)
            }
            public static var fire: DesignSystemImage { .init(resource: .fire96) }
            public static var passwordsAppFeature: DesignSystemImage { .init(resource: .passwordsAppFeature96) }
            public static var passwordsKeychainFeature: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .passwordsKeychainFeature96)
                    : .init(resource: .passwordsKeychainFeature96Legacy)
            }
            public static var syncPasswordsDesktop: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .syncPasswordsDesktop96)
                    : .init(resource: .syncPasswordsDesktop96Legacy)
            }
        }

        public enum Size128 {
            public static var duckAIPaid: DesignSystemImage { .init(resource: .duckAIPaid128) }
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
            public static var fire: DesignSystemImage {
                AppRebrand.isAppRebranded()
                    ? .init(resource: .fire128)
                    : .init(resource: .fire128Legacy)
            }
            public static var networkProtectionVPN: DesignSystemImage { .init(resource: .networkProtectionVPN128) }
            public static var networkProtectionVPNDisabled: DesignSystemImage { .init(resource: .networkProtectionVPNDisabled128) }
            public static var youTubeAdBlockWarning: DesignSystemImage { .init(resource: .youTubeWarningFeature128) }
        }
    }
}
