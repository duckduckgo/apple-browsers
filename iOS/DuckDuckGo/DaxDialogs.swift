//
//  DaxDialogs.swift
//  DuckDuckGo
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Foundation
import Core
import TrackerRadarKit
import BrowserServicesKit
import Common
import PrivacyDashboard

protocol EntityProviding {
    
    func entity(forHost host: String) -> Entity?
    
}

protocol NewTabDialogSpecProvider {
    func nextHomeScreenMessageNew() -> DaxDialogs.HomeScreenSpec?
    func dismiss()
}

protocol ContextualDaxDialogDisabling {
    func disableContextualDaxDialogs()
}

protocol ContextualOnboardingLogic {
    var isShowingFireDialog: Bool { get }
    var shouldShowPrivacyButtonPulse: Bool { get }
    var isShowingSearchSuggestions: Bool { get }
    var isShowingSitesSuggestions: Bool { get }

    func setTryAnonymousSearchMessageSeen()
    func setTryVisitSiteMessageSeen()
    func setSearchMessageSeen()
    func setFireEducationMessageSeen()
    func clearedBrowserData()
    func setFinalOnboardingDialogSeen()
    func setPrivacyButtonPulseSeen()
    func setDaxDialogDismiss()

    func enableAddFavoriteFlow()
}

protocol PrivacyProPromotionCoordinating {
    /// Indicates whether the Privacy Pro promotion dialog is currently being displayed
    var isShowingPrivacyProPromotion: Bool { get }
    
    /// Indicates whether the user has seen the Privacy Pro promotion dialog
    var privacyProPromotionDialogSeen: Bool { get set }
}

extension ContentBlockerRulesManager: EntityProviding {
    
    func entity(forHost host: String) -> Entity? {
        currentMainRules?.trackerData.findParentEntityOrFallback(forHost: host)
    }
    
}

final class DaxDialogs: NewTabDialogSpecProvider, ContextualOnboardingLogic {
    
    struct MajorTrackers {
        
        static let facebookDomain = "facebook.com"
        static let googleDomain = "google.com"
        
        static let domains = [facebookDomain, googleDomain]
        
    }
    
    enum HomeScreenSpec: Equatable {
        case initial
        case subsequent
        case final
        case addFavorite
        case privacyProPromotion
    }
    
    func overrideShownFlagFor(_ spec: BrowsingSpec, flag: Bool) {
        switch spec.type {
        case .withMultipleTrackers, .withOneTracker:
            settings.browsingWithTrackersShown = flag
        case .afterSearch:
            settings.browsingAfterSearchShown = flag
        case .visitWebsite:
            break
        case .withoutTrackers:
            settings.browsingWithoutTrackersShown = flag
        case .siteIsMajorTracker, .siteOwnedByMajorTracker:
            settings.browsingMajorTrackingSiteShown = flag
            settings.browsingWithoutTrackersShown = flag
        case .fire:
            settings.fireMessageExperimentShown = flag
        case .final:
            settings.browsingFinalDialogShown = flag
        }
    }
    
    struct BrowsingSpec: Equatable {
        // swiftlint:disable nesting

        enum SpecType: String {
            case afterSearch
            case visitWebsite
            case withoutTrackers
            case siteIsMajorTracker
            case siteOwnedByMajorTracker
            case withOneTracker
            case withMultipleTrackers
            case fire
            case final
        }
        // swiftlint:enable nesting

        static let afterSearch = BrowsingSpec(type: .afterSearch, pixelName: .daxDialogsSerpUnique)

        static let visitWebsite = BrowsingSpec(type: .visitWebsite, pixelName: .onboardingContextualTryVisitSiteUnique)

        static let withoutTrackers = BrowsingSpec(type: .withoutTrackers,
                                                  pixelName: .daxDialogsWithoutTrackersUnique,
                                                  message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingWithoutTrackers)

        static let siteIsMajorTracker = BrowsingSpec(type: .siteIsMajorTracker,
                                                     pixelName: .daxDialogsSiteIsMajorUnique,
                                                     message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingSiteIsMajorTracker)

        static let siteOwnedByMajorTracker = BrowsingSpec(type: .siteOwnedByMajorTracker,
                                                          pixelName: .daxDialogsSiteOwnedByMajorUnique,
                                                          message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingSiteOwnedByMajorTracker)

        static let withOneTracker = BrowsingSpec(type: .withOneTracker,
                                                 pixelName: .daxDialogsWithTrackersUnique,
                                                 message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingWithOneTracker)

        static let withMultipleTrackers = BrowsingSpec(type: .withMultipleTrackers,
                                                       pixelName: .daxDialogsWithTrackersUnique,
                                                       message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingWithMultipleTrackers)

        static let fire = BrowsingSpec(type: .fire, pixelName: .daxDialogsFireEducationShownUnique)

        static let final = BrowsingSpec(type: .final, pixelName: .daxDialogsEndOfJourneyTabUnique)

        let message: String
        let pixelName: Pixel.Event
        let type: SpecType

        init(type: SpecType, pixelName: Pixel.Event, message: String = "") {
            self.type = type
            self.pixelName = pixelName
            self.message = message
        }

        func format(args: CVarArg...) -> BrowsingSpec {
            format(message: message, args: args)
        }

        func format(message: String, args: CVarArg...) -> BrowsingSpec {
            withUpdatedMessage(String(format: message, arguments: args))
        }

        func withUpdatedMessage(_ message: String) -> BrowsingSpec {
            BrowsingSpec(
                type: type,
                pixelName: pixelName,
                message: message
            )
        }
    }

    private enum Constants {
        static let homeScreenMessagesSeenMaxCeiling = 2
    }

    public static let shared = DaxDialogs(entityProviding: ContentBlocking.shared.contentBlockingManager)

    private var settings: DaxDialogsSettings
    private var entityProviding: EntityProviding
    private let variantManager: VariantManager
    private let launchOptionsHandler: LaunchOptionsHandler

    private var nextHomeScreenMessageOverride: HomeScreenSpec?
    
    // So we can avoid showing two dialogs for the same page
    private var lastURLDaxDialogReturnedFor: URL?

    private var currentHomeSpec: HomeScreenSpec?

    private let onboardingPrivacyProPromotionHelper: OnboardingPrivacyProPromotionHelping

    /// Use singleton accessor, this is only accessible for tests
    init(settings: DaxDialogsSettings = DefaultDaxDialogsSettings(),
         entityProviding: EntityProviding,
         variantManager: VariantManager = DefaultVariantManager(),
         launchOptionsHandler: LaunchOptionsHandler = LaunchOptionsHandler(),
         onboardingPrivacyProPromotionHelper: OnboardingPrivacyProPromotionHelping = OnboardingPrivacyProPromotionHelper()
    ) {
        self.settings = settings
        self.entityProviding = entityProviding
        self.variantManager = variantManager
        self.launchOptionsHandler = launchOptionsHandler
        self.onboardingPrivacyProPromotionHelper = onboardingPrivacyProPromotionHelper
    }

    private var firstBrowsingMessageSeen: Bool {
        return settings.browsingAfterSearchShown
            || settings.browsingWithTrackersShown
            || settings.browsingWithoutTrackersShown
            || settings.browsingMajorTrackingSiteShown
    }

    private var firstSearchSeenButNoSiteVisited: Bool {
        return settings.browsingAfterSearchShown
            && !settings.browsingWithTrackersShown
            && !settings.browsingWithoutTrackersShown
            && !settings.browsingMajorTrackingSiteShown
    }

    private var nonDDGBrowsingMessageSeen: Bool {
        settings.browsingWithTrackersShown
        || settings.browsingWithoutTrackersShown
        || settings.browsingMajorTrackingSiteShown
    }

    private var finalDaxDialogSeen: Bool {
        settings.browsingFinalDialogShown
    }

    private var visitedSiteAndFireButtonSeen: Bool {
        settings.fireMessageExperimentShown &&
        firstBrowsingMessageSeen
    }

    private var shouldDisplayFinalContextualBrowsingDialog: Bool {
        !finalDaxDialogSeen &&
        visitedSiteAndFireButtonSeen
    }

    var isShowingSearchSuggestions: Bool {
        return currentHomeSpec == .initial
    }

    var isShowingSitesSuggestions: Bool {
        return lastShownDaxDialogType == .visitWebsite || currentHomeSpec == .subsequent
    }

    var isEnabled: Bool {
        if launchOptionsHandler.onboardingStatus.isOverriddenCompleted {
            return false
        }
        return !settings.isDismissed
    }

    var isShowingFireDialog: Bool {
        guard let lastShownDaxDialogType else { return false }
        return lastShownDaxDialogType == .fire
    }

    var isAddFavoriteFlow: Bool {
        return nextHomeScreenMessageOverride == .addFavorite
    }
    
    var shouldShowFireButtonPulse: Bool {
        // Show fire the user hasn't seen the fire education dialog or the fire button has not animated before.
        nonDDGBrowsingMessageSeen && (!settings.fireMessageExperimentShown && settings.fireButtonPulseDateShown == nil) && isEnabled
    }

    var shouldShowPrivacyButtonPulse: Bool {
        return settings.browsingWithTrackersShown && !settings.privacyButtonPulseShown && fireButtonPulseTimer == nil && isEnabled
    }

    func isStillOnboarding() -> Bool {
        if peekNextHomeScreenMessageExperiment() != nil {
            return true
        }
        return false
    }

    func dismiss() {
        settings.isDismissed = true
        // Reset last shown dialog as we don't have to show it anymore.
        clearOnboardingBrowsingData()
    }
    
    func primeForUse() {
        settings.isDismissed = false
    }

    func enableAddFavoriteFlow() {
        nextHomeScreenMessageOverride = .addFavorite
    }

    func resumeRegularFlow() {
        nextHomeScreenMessageOverride = nil
    }
    
    func clearHeldURLData() {
        lastURLDaxDialogReturnedFor = nil
    }
    
    private var fireButtonPulseTimer: Timer?
    private static let timeToFireButtonExpire: TimeInterval = 1 * 60 * 60
    
    private(set) var lastVisitedOnboardingWebsiteURL: URL?
    private(set) var lastShownDaxDialogType: BrowsingSpec.SpecType?

    private var shouldShowNetworkTrackerDialog: Bool {
        !settings.browsingMajorTrackingSiteShown && !settings.browsingWithTrackersShown
    }

    private func lastShownDaxDialog(privacyInfo: PrivacyInfo) -> BrowsingSpec? {
        guard let dialogType = lastShownDaxDialogType else { return  nil }
        switch dialogType {
        case BrowsingSpec.SpecType.afterSearch:
            return BrowsingSpec.afterSearch
        case BrowsingSpec.SpecType.visitWebsite:
            return nil
        case BrowsingSpec.SpecType.withoutTrackers:
            return BrowsingSpec.withoutTrackers
        case BrowsingSpec.SpecType.siteIsMajorTracker:
            guard let host = privacyInfo.domain else { return nil }
            return majorTrackerMessage(host, isReloadingDialog: true)
        case BrowsingSpec.SpecType.siteOwnedByMajorTracker:
            guard let host = privacyInfo.domain, let owner = isOwnedByFacebookOrGoogle(host) else { return nil }
            return majorTrackerOwnerMessage(host, owner, isReloadingDialog: true)
        case BrowsingSpec.SpecType.withOneTracker, BrowsingSpec.SpecType.withMultipleTrackers:
            guard let entityNames = blockedEntityNames(privacyInfo.trackerInfo) else { return nil }
            return trackersBlockedMessage(entityNames, isReloadingDialog: true)
        case BrowsingSpec.SpecType.fire:
            return .fire
        case BrowsingSpec.SpecType.final:
            return nil
        }
    }

    func fireButtonPulseStarted() {
        ViewHighlighter.dismissPrivacyIconPulseAnimation()
        if settings.fireButtonPulseDateShown == nil {
            settings.fireButtonPulseDateShown = Date()
        }
        if fireButtonPulseTimer == nil, let date = settings.fireButtonPulseDateShown {
            let timeSinceShown = Date().timeIntervalSince(date)
            let timerTime = DaxDialogs.timeToFireButtonExpire - timeSinceShown
            fireButtonPulseTimer = Timer(timeInterval: timerTime, repeats: false) { _ in
                self.settings.fireButtonEducationShownOrExpired = true
                ViewHighlighter.hideAll()
            }
            RunLoop.current.add(fireButtonPulseTimer!, forMode: RunLoop.Mode.common)
        }
    }
    
    func fireButtonPulseCancelled() {
        fireButtonPulseTimer?.invalidate()
        settings.fireButtonEducationShownOrExpired = true
    }

    func setTryAnonymousSearchMessageSeen() {
        settings.tryAnonymousSearchShown = true
    }

    func setTryVisitSiteMessageSeen() {
        settings.tryVisitASiteShown = true
    }

    func setSearchMessageSeen() {
        lastShownDaxDialogType = BrowsingSpec.visitWebsite.type
    }

    func setFireEducationMessageSeen() {
        // Set also privacy button pulse seen as we don't have to show anymore if we saw the fire educational message.
        settings.privacyButtonPulseShown = true
        settings.fireMessageExperimentShown = true
        lastShownDaxDialogType = BrowsingSpec.fire.type
    }

    func clearedBrowserData() {
        setDaxDialogDismiss()
    }

    func setPrivacyButtonPulseSeen() {
        settings.privacyButtonPulseShown = true
    }

    func setDaxDialogDismiss() {
        clearOnboardingBrowsingData()
    }

    func setFinalOnboardingDialogSeen() {
        settings.browsingFinalDialogShown = true
    }

    func nextBrowsingMessageIfShouldShow(for privacyInfo: PrivacyInfo) -> BrowsingSpec? {

        let message = nextBrowsingMessageExperiment(privacyInfo: privacyInfo)
        if message != nil {
            lastURLDaxDialogReturnedFor = privacyInfo.url
        }
        
        return message
    }

    private func nextBrowsingMessageExperiment(privacyInfo: PrivacyInfo) -> BrowsingSpec? {

        func hasTrackers(host: String) -> Bool {
            isFacebookOrGoogle(privacyInfo.url) || isOwnedByFacebookOrGoogle(host) != nil || blockedEntityNames(privacyInfo.trackerInfo) != nil
        }

        // Reset current home spec when navigating
        currentHomeSpec = nil

        guard isEnabled, nextHomeScreenMessageOverride == nil else { return nil }

        if let lastVisitedOnboardingWebsiteURL,
            compareUrls(url1: lastVisitedOnboardingWebsiteURL, url2: privacyInfo.url) {
            return lastShownDaxDialog(privacyInfo: privacyInfo)
        }

        guard let host = privacyInfo.domain else { return nil }

        var spec: BrowsingSpec?

        if privacyInfo.url.isDuckDuckGoSearch && !settings.browsingAfterSearchShown {
            spec = searchMessage()
        } else if isFacebookOrGoogle(privacyInfo.url) && shouldShowNetworkTrackerDialog {
            // Set visit site suggestion site seen when navigating so we don't show the suggestion on new tab after visiting a site.
            setTryVisitSiteMessageSeen()
            // won't be shown if owned by major tracker message has already been shown
            spec = majorTrackerMessage(host, isReloadingDialog: false)
        } else if let owner = isOwnedByFacebookOrGoogle(host), shouldShowNetworkTrackerDialog {
            // Set visit site suggestion site seen when navigating so we don't show the suggestion on new tab after visiting a site.
            setTryVisitSiteMessageSeen()
            // won't be shown if major tracker message has already been shown
            spec = majorTrackerOwnerMessage(host, owner, isReloadingDialog: false)
        } else if let entityNames = blockedEntityNames(privacyInfo.trackerInfo), !settings.browsingWithTrackersShown {
            // Set visit site suggestion site seen when navigating so we don't show the suggestion on new tab after visiting a site.
            setTryVisitSiteMessageSeen()
            spec = trackersBlockedMessage(entityNames, isReloadingDialog: false)
        } else if !settings.browsingWithoutTrackersShown && !privacyInfo.url.isDuckDuckGoSearch && !hasTrackers(host: host) {
            // Set visit site suggestion site seen when navigating so we don't show the suggestion on new tab after visiting a site.
            setTryVisitSiteMessageSeen()
            // if non duck duck go search and no trackers found and no tracker message already shown, show no trackers message
            spec = noTrackersMessage()
        } else if shouldDisplayFinalContextualBrowsingDialog {
            // If the user visited a website and saw the fire dialog
            spec = finalMessage()
        }

        if let spec {
            lastShownDaxDialogType = spec.type
            lastVisitedOnboardingWebsiteURL = privacyInfo.url
        } else {
            clearOnboardingBrowsingData()
        }

        return spec
    }

    func nextHomeScreenMessageNew() -> HomeScreenSpec? {
        // Reset the last browsing information when opening a new tab so loading the previous website won't show again the Dax dialog
        clearedBrowserData()

        guard let homeScreenSpec = peekNextHomeScreenMessageExperiment() else {
            currentHomeSpec = nil
            return nil
        }
        currentHomeSpec = homeScreenSpec
        return homeScreenSpec
    }

    private func peekNextHomeScreenMessageExperiment() -> HomeScreenSpec? {
        if nextHomeScreenMessageOverride != nil {
            return nextHomeScreenMessageOverride
        }

        guard isEnabled else { return nil }

        // If the user has already seen the end of journey dialog we want to check if the user is eligible to purchase Privacy Pro and if so, display an additional Privacy Pro promotion dialog.
        guard !finalDaxDialogSeen else {

            if onboardingPrivacyProPromotionHelper.shouldDisplay && !privacyProPromotionDialogSeen {
                return .privacyProPromotion
            }

            return nil
        }

        // Check final first as if we skip anonymous searches we don't want to show this.
        if settings.fireMessageExperimentShown {
            return .final
        }

        // If try a visit hasn't been show return initial
        if !settings.tryAnonymousSearchShown {
            return .initial
        }

        if !settings.tryVisitASiteShown {
            return .subsequent
        }
        
        return nil
    }

    private func noTrackersMessage() -> DaxDialogs.BrowsingSpec? {
        if !settings.browsingWithoutTrackersShown && !settings.browsingMajorTrackingSiteShown && !settings.browsingWithTrackersShown {
            settings.browsingWithoutTrackersShown = true
            return BrowsingSpec.withoutTrackers
        }
        return nil
    }

    func majorTrackerOwnerMessage(_ host: String, _ majorTrackerEntity: Entity, isReloadingDialog: Bool) -> DaxDialogs.BrowsingSpec? {
        if !isReloadingDialog && settings.browsingMajorTrackingSiteShown { return nil }
        
        guard let entityName = majorTrackerEntity.displayName,
            let entityPrevalence = majorTrackerEntity.prevalence else { return nil }
        settings.browsingMajorTrackingSiteShown = true
        settings.browsingWithoutTrackersShown = true
        return BrowsingSpec.siteOwnedByMajorTracker.format(args: host.droppingWwwPrefix(),
                                                           entityName,
                                                           entityPrevalence)
    }

    private func majorTrackerMessage(_ host: String, isReloadingDialog: Bool) -> DaxDialogs.BrowsingSpec? {
        if !isReloadingDialog && settings.browsingMajorTrackingSiteShown { return nil }
        guard let entityName = entityProviding.entity(forHost: host)?.displayName else { return nil }
        settings.browsingMajorTrackingSiteShown = true
        settings.browsingWithoutTrackersShown = true
        return BrowsingSpec.siteIsMajorTracker.format(args: entityName, host)
    }
    
    private func searchMessage() -> BrowsingSpec? {
        guard !settings.browsingAfterSearchShown else { return nil }
        settings.browsingAfterSearchShown = true
        return BrowsingSpec.afterSearch
    }

    private func finalMessage() -> BrowsingSpec? {
        guard !finalDaxDialogSeen else { return nil }
        return BrowsingSpec.final
    }

    private func trackersBlockedMessage(_ entitiesBlocked: [String], isReloadingDialog: Bool) -> BrowsingSpec? {
        if !isReloadingDialog && settings.browsingWithTrackersShown { return nil }

        var spec: BrowsingSpec?
        switch entitiesBlocked.count {

        case 0:
            spec = nil

        case 1:
            settings.browsingWithTrackersShown = true
            let args = entitiesBlocked[0]
            spec = BrowsingSpec.withOneTracker.format(message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingWithOneTracker, args: args)

        default:
            settings.browsingWithTrackersShown = true
            let args: [CVarArg] = [entitiesBlocked.count - 2, entitiesBlocked[0], entitiesBlocked[1]]
            spec = BrowsingSpec.withMultipleTrackers.format(message: UserText.Onboarding.ContextualOnboarding.daxDialogBrowsingWithMultipleTrackers, args: args)
        }
        return spec
    }
 
    private func blockedEntityNames(_ trackerInfo: TrackerInfo) -> [String]? {
        setTryVisitSiteMessageSeen()
        guard !trackerInfo.trackersBlocked.isEmpty else { return nil }
        
        return trackerInfo.trackersBlocked.removingDuplicates { $0.entityName }
            .sorted(by: { $0.prevalence ?? 0.0 > $1.prevalence ?? 0.0 })
            .compactMap { $0.entityName }
    }
    
    private func isFacebookOrGoogle(_ url: URL) -> Bool {
        return [ MajorTrackers.facebookDomain, MajorTrackers.googleDomain ].contains { domain in
            return url.isPart(ofDomain: domain)
        }
    }
    
    private func isOwnedByFacebookOrGoogle(_ host: String) -> Entity? {
        guard let entity = entityProviding.entity(forHost: host) else { return nil }
        return entity.domains?.contains(where: { MajorTrackers.domains.contains($0) }) ?? false ? entity : nil
    }

    private func compareUrls(url1: URL?, url2: URL?) -> Bool {
        guard let url1, let url2 else { return false }

        if url1 == url2 {
            return true
        }

        return url1.isSameDuckDuckGoSearchURL(other: url2)
    }

    private func clearOnboardingBrowsingData() {
        lastShownDaxDialogType = nil
        lastVisitedOnboardingWebsiteURL = nil
        currentHomeSpec = nil
    }
}

extension DaxDialogs: PrivacyProPromotionCoordinating {
    
    var isShowingPrivacyProPromotion: Bool {
        currentHomeSpec == .privacyProPromotion
    }

    var privacyProPromotionDialogSeen: Bool {
        get {
            settings.privacyProPromotionDialogShown
        }
        set {
            settings.privacyProPromotionDialogShown = newValue
        }
    }
}

extension DaxDialogs: ContextualDaxDialogDisabling {

    func disableContextualDaxDialogs() {
        dismiss()
    }

}

extension URL {

    func isSameDuckDuckGoSearchURL(other: URL?) -> Bool {
        guard let other else { return false }

        guard isDuckDuckGoSearch && other.isDuckDuckGoSearch else { return false }

        // Extract 'q' parameter from both URLs
        let queryValue1 = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value
        let queryValue2 = URLComponents(url: other, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value

        let normalizedQuery1 = queryValue1?
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "%20", with: " ")
        let normalizedQuery2 = queryValue2?
            .replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: "%20", with: " ")
        
        return normalizedQuery1 == normalizedQuery2
    }
}

private extension ViewHighlighter {

    static func dismissPrivacyIconPulseAnimation() {
        guard ViewHighlighter.highlightedViews.contains(where: { $0.view is PrivacyIconView }) else { return }
        ViewHighlighter.hideAll()
    }

}

#if canImport(XCTest)
extension DaxDialogs {

    func setLastVisitedURL(_ url: URL?) {
        lastVisitedOnboardingWebsiteURL = url
    }

    func setLastShownDialog(type: BrowsingSpec.SpecType) {
        lastShownDaxDialogType = type
    }

}
#endif
