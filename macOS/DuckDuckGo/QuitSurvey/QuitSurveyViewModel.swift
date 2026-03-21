//
//  QuitSurveyViewModel.swift
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

import Combine
import Foundation
import os.log
import Common
import History
import PixelKit
import PrivacyConfig
import PrivacyDashboard
import AppKit

// MARK: - Domain Entry Model

struct QuitSurveyDomainEntry: Identifiable, Hashable {
    let domain: String
    let title: String?
    let favicon: NSImage?

    var id: String { domain }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.domain == rhs.domain }
    func hash(into hasher: inout Hasher) { hasher.combine(domain) }
}

// MARK: - Survey Option Model

struct QuitSurveyOption: Identifiable, Hashable, Equatable {
    let id: String
    let text: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QuitSurveyOption, rhs: QuitSurveyOption) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Survey State

enum QuitSurveyState: Equatable {
    case initialQuestion
    case positiveResponse
    case negativeFeedback
}

// MARK: - View Model

@MainActor
final class QuitSurveyViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var state: QuitSurveyState = .initialQuestion
    @Published var selectedOptions: Set<String> = []
    @Published var feedbackText: String = ""
    @Published private(set) var autoQuitCountdown: Int = 5
    @Published private(set) var isSubmitting: Bool = false
    @Published private(set) var selectedDomains: Set<String> = []
    @Published var otherDomainText: String = ""
    @Published private(set) var isOtherDomainSelected: Bool = false

    // MARK: - Configuration

    private static let allOptions: [QuitSurveyOption] = [
        QuitSurveyOption(id: "pages-froze", text: UserText.quitSurveyOptionPagesFroze),
        QuitSurveyOption(id: "pages-loaded-slowly", text: UserText.quitSurveyOptionPagesLoadedSlowly),
        QuitSurveyOption(id: websitesDidntWorkOptionId, text: UserText.quitSurveyOptionWebsitesDidntWork),
        QuitSurveyOption(id: "browser-crashed", text: UserText.quitSurveyOptionBrowserCrashed),
        QuitSurveyOption(id: "tabs-opened-slowly", text: UserText.quitSurveyOptionTabsOpenedSlowly),
        QuitSurveyOption(id: "slowed-my-computer", text: UserText.quitSurveyOptionSlowedMyComputer),
        QuitSurveyOption(id: "slow-to-open", text: UserText.quitSurveyOptionSlowToOpen),
        QuitSurveyOption(id: "couldnt-disable-ai", text: UserText.quitSurveyOptionCouldntDisableAI),
        QuitSurveyOption(id: "hard-to-find-settings", text: UserText.quitSurveyOptionHardToFindSettings),
        QuitSurveyOption(id: "no-password-manager-extensions", text: UserText.quitSurveyOptionNoPasswordManagerExtensions),
        QuitSurveyOption(id: "ad-blocker-didnt-work", text: UserText.quitSurveyOptionAdBlockerDidntWork),
        QuitSurveyOption(id: "onboarding-wasnt-helpful", text: UserText.quitSurveyOptionOnboardingWasntHelpful),
        QuitSurveyOption(id: "benefits-unclear", text: UserText.quitSurveyOptionBenefitsUnclear),
        QuitSurveyOption(id: "privacy-concerns", text: UserText.quitSurveyOptionPrivacyConcerns),
        QuitSurveyOption(id: "just-trying-it-out", text: UserText.quitSurveyOptionJustTryingItOut),
        QuitSurveyOption(id: "sign-in-hassles", text: UserText.quitSurveyOptionSignInHassles),

        QuitSurveyOption(id: "no-website-translations", text: UserText.quitSurveyOptionNoWebsiteTranslations),
        QuitSurveyOption(id: "issue-importing-my-stuff", text: UserText.quitSurveyOptionIssueImportingMyStuff)
    ]

    static let websitesDidntWorkOptionId = "websites-didnt-work"
    private static let websitesDidntWorkOption = QuitSurveyOption(id: websitesDidntWorkOptionId, text: UserText.quitSurveyOptionWebsitesDidntWork)
    private static let somethingElseOption = QuitSurveyOption(id: "something-else", text: UserText.quitSurveyOptionSomethingElse)

    static let domainSelectorTriggerIds: Set<String> = [websitesDidntWorkOptionId, "pages-froze", "pages-loaded-slowly"]

    let availableOptions: [QuitSurveyOption]
    let recentDomains: [QuitSurveyDomainEntry]

    private let feedbackSender: FeedbackSenderImplementing
    private var persistor: QuitSurveyPersistor?
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let onQuit: () -> Void
    private var autoQuitTimer: Timer?

    // MARK: - Computed Properties

    var shouldShowTextInput: Bool {
        !selectedOptions.isEmpty
    }

    var shouldEnableSubmit: Bool {
        !selectedOptions.isEmpty || !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowDomainSelector: Bool {
        featureFlagger.isFeatureOn(.websitesHistoryFirstTimeQuitSurvey)
            && !selectedOptions.isDisjoint(with: Self.domainSelectorTriggerIds)
            && !recentDomains.isEmpty
    }

    // MARK: - Initialization

    init(
        feedbackSender: FeedbackSenderImplementing = FeedbackSender(),
        persistor: QuitSurveyPersistor? = nil,
        featureFlagger: FeatureFlagger,
        pixelFiring: PixelFiring? = PixelKit.shared,
        historyCoordinating: HistoryCoordinating? = nil,
        faviconManaging: FaviconManagement? = nil,
        onQuit: @escaping () -> Void
    ) {
        self.feedbackSender = feedbackSender
        self.persistor = persistor
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.onQuit = onQuit
        let otherOptions = Self.allOptions.filter { $0.id != Self.websitesDidntWorkOption.id }
        let randomOptions = Array(otherOptions.shuffled().prefix(7))
        self.availableOptions = (randomOptions + [Self.websitesDidntWorkOption]).shuffled() + [Self.somethingElseOption]
        self.recentDomains = Self.fetchRecentDomainEntries(from: historyCoordinating,
                                                           faviconManaging: faviconManaging,
                                                           featureFlagger: featureFlagger)
        fireSurveyShown()
    }

    private static func fetchRecentDomainEntries(from history: HistoryCoordinating?,
                                                 faviconManaging: FaviconManagement?,
                                                 featureFlagger: FeatureFlagger) -> [QuitSurveyDomainEntry] {
        guard featureFlagger.isFeatureOn(.websitesHistoryFirstTimeQuitSurvey) else { return [] }
        guard let entries = history?.history else { return [] }
        var seen = Set<String>()
        return entries
            .sorted { $0.lastVisit > $1.lastVisit }
            .compactMap { entry -> (HistoryEntry, String)? in
                guard let host = entry.url.trimmingQueryItemsAndFragment().host else { return nil }
                return (entry, host)
            }
            .filter { seen.insert($0.1).inserted }
            .prefix(5)
            .map { (entry, domain) in
                let title = entry.title.flatMap { $0.isEmpty ? nil : $0 }
                let favicon = faviconManaging?.getCachedFavicon(forDomainOrAnySubdomain: domain, sizeCategory: .small)?.image
                return QuitSurveyDomainEntry(domain: domain, title: title, favicon: favicon)
            }
    }

    // MARK: - Actions

    func selectPositiveResponse() {
        fireSurveyThumbsUp()
        state = .positiveResponse
        startAutoQuitTimer()
    }

    func selectNegativeResponse() {
        fireSurveyThumbsDown()
        state = .negativeFeedback
    }

    func goBack() {
        stopAutoQuitTimer()
        selectedOptions.removeAll()
        feedbackText = ""
        clearDomainState()
        state = .initialQuestion
    }

    func toggleOption(_ optionId: String) {
        if selectedOptions.contains(optionId) {
            selectedOptions.remove(optionId)
            if Self.domainSelectorTriggerIds.contains(optionId) && !shouldShowDomainSelector {
                clearDomainState()
            }
        } else {
            selectedOptions.insert(optionId)
        }
    }

    private func clearDomainState() {
        selectedDomains.removeAll()
        isOtherDomainSelected = false
        otherDomainText = ""
    }

    func toggleDomain(_ domain: String) {
        if selectedDomains.contains(domain) {
            selectedDomains.remove(domain)
        } else {
            selectedDomains.insert(domain)
        }
    }

    func toggleOtherDomain() {
        isOtherDomainSelected.toggle()
        if !isOtherDomainSelected {
            otherDomainText = ""
        }
    }

    func submitFeedback() {
        isSubmitting = true

        var effectiveDomains = selectedDomains
        let rawOther = otherDomainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedURL = URL(string: rawOther).flatMap { $0.host != nil ? $0 : nil }
            ?? URL(string: "https://\(rawOther)")
        let trimmedOther = (resolvedURL?.trimmingQueryItemsAndFragment().host ?? rawOther)
            .replacingOccurrences(of: ",", with: "")
        if isOtherDomainSelected && !trimmedOther.isEmpty {
            effectiveDomains.insert(trimmedOther)
        }

        let domainsPrefix = effectiveDomains.isEmpty
            ? ""
            : "Affected domains: \(effectiveDomains.sorted().joined(separator: ", "))\n\n"
        let combinedText = domainsPrefix + feedbackText

        let feedback = Feedback.from(
            selectedPillIds: Array(selectedOptions),
            text: combinedText,
            appVersion: AppVersion.shared.versionNumber,
            category: .firstTimeQuitSurvey,
            problemCategory: Self.firstTimeQuitSurveyCategory
        )

        let reasons = getReasonsForPixel()
        let affectedDomains = effectiveDomains.isEmpty ? nil : effectiveDomains.sorted().joined(separator: ",")
        fireThumbsDownPixelSubmission(reasons: reasons, affectedDomains: affectedDomains)

        // Store reasons for the return user pixel (fired on next app launch)
        persistor?.pendingReturnUserReasons = reasons

        feedbackSender.sendFeedback(feedback) { [weak self] in
            DispatchQueue.main.async {
                Logger.general.debug("Quit survey feedback submitted")
                self?.isSubmitting = false
                self?.quit()
            }
        }
    }

    func quit() {
        stopAutoQuitTimer()
        onQuit()
    }

    func closeAndQuit() {
        quit()
    }

    // MARK: - Pixels

    private func fireSurveyShown() {
        pixelFiring?.fire(QuitSurveyPixels.quitSurveyShown)
    }

    private func fireSurveyThumbsUp() {
        pixelFiring?.fire(QuitSurveyPixels.quitSurveyThumbsUp)
    }

    private func fireSurveyThumbsDown() {
        pixelFiring?.fire(QuitSurveyPixels.quitSurveyThumbsDown)
    }

    private func fireThumbsDownPixelSubmission(reasons: String, affectedDomains: String?) {
        pixelFiring?.fire(QuitSurveyPixels.quitSurveyThumbsDownSubmission(reasons: reasons, affectedDomains: affectedDomains))
    }

    /// This methods calculates the parameters for the thumbs down submission pixel.
    /// The reasons are calculated in the following way:
    /// - The selected reasons get a 1
    /// - The non-selected reasons get a 0
    /// - The non-shown reasons get a -1
    private func getReasonsForPixel() -> String {
        let selectedReasons = selectedOptions
            .map { "\($0)=1" }
            .joined(separator: ",")
        let nonSelectedReasons = availableOptions
            .compactMap(\.id)
            .filter { !selectedOptions.contains($0) }
            .map { "\($0)=0" }
            .joined(separator: ",")
        let nonShownReasons = Self.allOptions
            .filter { !availableOptions.contains($0) }
            .map { "\($0.id)=-1" }
            .joined(separator: ",")

        if nonSelectedReasons.isEmpty {
            return "\(selectedReasons),\(nonShownReasons)"
        } else {
            return "\(selectedReasons),\(nonSelectedReasons),\(nonShownReasons)"
        }
    }

    // MARK: - Auto Quit Timer

    private func startAutoQuitTimer() {
        autoQuitCountdown = 5
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeMainThread {
                guard let self else { return }
                self.autoQuitCountdown -= 1
                if self.autoQuitCountdown <= 0 {
                    self.quit()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoQuitTimer = timer
    }

    private func stopAutoQuitTimer() {
        autoQuitTimer?.invalidate()
        autoQuitTimer = nil
    }

    deinit {
        autoQuitTimer?.invalidate()
    }

    private static let firstTimeQuitSurveyCategory = ProblemCategory(id: "first-time-quit-survey",
                                                                     text: "First time quit survey",
                                                                     subcategories: [])
}
