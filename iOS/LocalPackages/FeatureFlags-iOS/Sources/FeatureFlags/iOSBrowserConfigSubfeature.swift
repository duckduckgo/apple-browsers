//
//  iOSBrowserConfigSubfeature.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import PrivacyConfig

public enum iOSBrowserConfigSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .iOSBrowserConfig
    }

    // Demonstrative case for default value. Remove once a real-world feature is added
    case intentionallyLocalOnlySubfeatureForTests

    case widgetReporting

    // Local inactivity provisional notifications delivered to Notification Center.
    // https://app.asana.com/1/137249556945/project/72649045549333/task/1211003501974970?focus=true
    case inactivityNotification

    /// https://app.asana.com/1/137249556945/project/715106103902962/task/1210997282929955?focus=true
    case unifiedURLPredictor

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211660503405838?focus=true
    case forgetAllInSettings

    /// https://app.asana.com/1/137249556945/project/481882893211075/task/1212057154681076?focus=true
    case productTelemetrySurfaceUsage

    ///  https://app.asana.com/1/137249556945/project/414709148257752/task/1212395110448661?focus=true
    case appRatingPrompt

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1212238464901412?focus=true
    case showWhatsNewPromptOnDemand

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212875994217788?focus=true
    case genericBackgroundTask

    /// Failsafe flag for disabling call stack tree depth limiting in crash collector
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213037858764805
    case crashCollectionLimitCallStackTreeDepth

    /// Enables sending MetricKit launch-time telemetry pixels.
    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1214963974721156
    case launchTimeMetrics

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1217109908046478?focus=true
    case tabTerminationTelemetry

    case tabEvictionOnMemoryWarning
    case tabLRUEviction

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212835969125260
    case browsingMenuSheetEnabledByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213336304802675
    case showNTPAfterIdleReturn

    case crashReportOptInStatusResetting

    case screenTimeCleaning

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215448831345663?focus=true
    case bottomBarViewportFixedElementsWorkaround

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1211806114021630?focus=true
    case onboardingRebranding

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214974217398704?focus=true
    case appRebranding

    /// https://app.asana.com/1/137249556945/task/1213314048601761
    case fireMode

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213965646075290
    case fireButtonRefinements

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1216535350078652
    case fireButtonSingleTabDeleteAll

    /// https://app.asana.com/1/137249556945/project/392891325557410/task/1212828713075939?focus=true
    case omniBarLongPressMenu

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214797978179697?focus=true
    case customProductPageDuckAiChat

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215151176422651?focus=true
    case customProductPageDuckAiOnboardingFlow

    /// Gate the default-to-NTP-after-idle behavior for existing iPhone users behind a remote flag.
    /// https://app.asana.com/1/137249556945/project/1204186595873227/task/1214830562427843
    case defaultExistingIPhoneUsersToNewTabAfterIdle

    case customizeNTPIcons

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215169783702336
    case walletPassDownload

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215359554019438?focus=true
    case floatingUI

    /// https://app.asana.com/1/137249556945/project/392891325557410/task/1216807388526023?focus=true
    case tabSwitcherJuly2026

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215385432113040?focus=true
    case removeChatHistory

    /// NA experiment: search token to speed up SERP by combining Index/Deep responses.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1216365830146824
    case searchTokenExperimentV2

    /// NA Experiment: tailor the onboarding flow based on the user's download reason.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1216491579842691?focus=true
    case onboardingFlowByDownloadReasonExperiment

    /// Caches the blank-snapshot overlay off the suspend path to avoid the background scene-update watchdog.
    case blankSnapshotCaching

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1216629730083154?focus=true
    case systemFindInPage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1217015452646368?focus=true
    case iPadTabsBarInWindowControlsRow
}
