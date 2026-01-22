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
import PixelKit

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

    // MARK: - Configuration

    private static let allOptions: [QuitSurveyOption] = [
        QuitSurveyOption(id: "asked-to-disable-ad-blocker", text: UserText.quitSurveyOptionAskedToDisableAdBlocker),
        QuitSurveyOption(id: "pages-froze", text: UserText.quitSurveyOptionPagesFroze),
        QuitSurveyOption(id: "pages-loaded-slowly", text: UserText.quitSurveyOptionPagesLoadedSlowly),
        QuitSurveyOption(id: "more-captchas", text: UserText.quitSurveyOptionMoreCaptchas),
        QuitSurveyOption(id: "couldnt-check-out", text: UserText.quitSurveyOptionCouldntCheckOut),
        QuitSurveyOption(id: "couldnt-sign-in-to-bank", text: UserText.quitSurveyOptionCouldntSignInToBank),
        QuitSurveyOption(id: "videos-didnt-play", text: UserText.quitSurveyOptionVideosDidntPlay),
        QuitSurveyOption(id: "browser-crashed", text: UserText.quitSurveyOptionBrowserCrashed),
        QuitSurveyOption(id: "tabs-opened-slowly", text: UserText.quitSurveyOptionTabsOpenedSlowly),
        QuitSurveyOption(id: "slowed-my-computer", text: UserText.quitSurveyOptionSlowedMyComputer),
        QuitSurveyOption(id: "slow-to-open", text: UserText.quitSurveyOptionSlowToOpen),
        QuitSurveyOption(id: "couldnt-disable-ai", text: UserText.quitSurveyOptionCouldntDisableAI),
        QuitSurveyOption(id: "bad-ai-responses", text: UserText.quitSurveyOptionBadAIResponses),
        QuitSurveyOption(id: "hard-to-find-settings", text: UserText.quitSurveyOptionHardToFindSettings),
        QuitSurveyOption(id: "hard-to-manage-downloads", text: UserText.quitSurveyOptionHardToManageDownloads),
        QuitSurveyOption(id: "shortcuts-didnt-work", text: UserText.quitSurveyOptionShortcutsDidntWork),
        QuitSurveyOption(id: "navigation-unfamiliar", text: UserText.quitSurveyOptionNavigationUnfamiliar),
        QuitSurveyOption(id: "fire-button-removed-too-much", text: UserText.quitSurveyOptionFireButtonRemovedTooMuch),
        QuitSurveyOption(id: "couldnt-find-incognito", text: UserText.quitSurveyOptionCouldntFindIncognito),
        QuitSurveyOption(id: "password-manager-unavailable", text: UserText.quitSurveyOptionPasswordManagerUnavailable),
        QuitSurveyOption(id: "ad-blocker-didnt-work", text: UserText.quitSurveyOptionAdBlockerDidntWork),
        QuitSurveyOption(id: "couldnt-skip-onboarding", text: UserText.quitSurveyOptionCouldntSkipOnboarding),
        QuitSurveyOption(id: "onboarding-wasnt-helpful", text: UserText.quitSurveyOptionOnboardingWasntHelpful),
        QuitSurveyOption(id: "couldnt-import-bookmarks", text: UserText.quitSurveyOptionCouldntImportBookmarks),
        QuitSurveyOption(id: "couldnt-import-passwords", text: UserText.quitSurveyOptionCouldntImportPasswords),
        QuitSurveyOption(id: "couldnt-import-pay-details", text: UserText.quitSurveyOptionCouldntImportPayDetails),
        QuitSurveyOption(id: "couldnt-change-search-engine", text: UserText.quitSurveyOptionCouldntChangeSearchEngine),
        QuitSurveyOption(id: "unexpected-search-results", text: UserText.quitSurveyOptionUnexpectedSearchResults),
        QuitSurveyOption(id: "benefits-unclear", text: UserText.quitSurveyOptionBenefitsUnclear),
        QuitSurveyOption(id: "privacy-concerns", text: UserText.quitSurveyOptionPrivacyConcerns),
        QuitSurveyOption(id: "unsure-how-history-is-handled", text: UserText.quitSurveyOptionUnsureHowHistoryIsHandled),
        QuitSurveyOption(id: "just-trying-it-out", text: UserText.quitSurveyOptionJustTryingItOut),
        QuitSurveyOption(id: "not-ready-to-switch-browsers", text: UserText.quitSurveyOptionNotReadyToSwitchBrowsers),
        QuitSurveyOption(id: "had-to-re-sign-in", text: UserText.quitSurveyOptionHadToReSignIn),
        QuitSurveyOption(id: "sign-in-hassles", text: UserText.quitSurveyOptionSignInHassles)
    ]

    private static let somethingElseOption = QuitSurveyOption(id: "something-else", text: UserText.quitSurveyOptionSomethingElse)

    let availableOptions: [QuitSurveyOption]

    private let feedbackSender: FeedbackSenderImplementing
    private var persistor: QuitSurveyPersistor?
    private let onQuit: () -> Void
    private var autoQuitTimer: Timer?

    // MARK: - Computed Properties

    var shouldShowTextInput: Bool {
        !selectedOptions.isEmpty
    }

    var shouldEnableSubmit: Bool {
        !selectedOptions.isEmpty || !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initialization

    init(
        feedbackSender: FeedbackSenderImplementing = FeedbackSender(),
        persistor: QuitSurveyPersistor? = nil,
        onQuit: @escaping () -> Void
    ) {
        self.feedbackSender = feedbackSender
        self.persistor = persistor
        self.onQuit = onQuit

        // Select 8 random options + "Something else"
        let randomOptions = Array(Self.allOptions.shuffled().prefix(8))
        self.availableOptions = randomOptions + [Self.somethingElseOption]
        fireSurveyShown()
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
        state = .initialQuestion
    }

    func toggleOption(_ optionId: String) {
        if selectedOptions.contains(optionId) {
            selectedOptions.remove(optionId)
        } else {
            selectedOptions.insert(optionId)
        }
    }

    func submitFeedback() {
        isSubmitting = true

        let feedback = Feedback.from(
            selectedPillIds: Array(selectedOptions),
            text: feedbackText,
            appVersion: AppVersion.shared.versionNumber,
            category: .firstTimeQuitSurvey,
            problemCategory: Self.firstTimeQuitSurveyCategory
        )

        let reasons = getReasonsForPixel()
        fireThumbsDownPixelSubmission(reasons: reasons)

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
        PixelKit.fire(QuitSurveyPixels.quitSurveyShown)
    }

    private func fireSurveyThumbsUp() {
        PixelKit.fire(QuitSurveyPixels.quitSurveyThumbsUp)
    }

    private func fireSurveyThumbsDown() {
        PixelKit.fire(QuitSurveyPixels.quitSurveyThumbsDown)
    }

    private func fireThumbsDownPixelSubmission(reasons: String) {
        PixelKit.fire(QuitSurveyPixels.quitSurveyThumbsDownSubmission(reasons: reasons))
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
