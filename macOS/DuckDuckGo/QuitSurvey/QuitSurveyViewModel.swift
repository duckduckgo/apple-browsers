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

// MARK: - Survey Option Model

struct QuitSurveyOption: Identifiable, Hashable {
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

    // MARK: - Configuration

    let availableOptions: [QuitSurveyOption] = [
        QuitSurveyOption(id: "browser-is-slow", text: UserText.quitSurveyOptionBrowserIsSlow),
        QuitSurveyOption(id: "browser-doesnt-work-as-expected", text: UserText.quitSurveyOptionBrowserDoesntWork),
        QuitSurveyOption(id: "no-extensions", text: UserText.quitSurveyOptionNoExtensions),
        QuitSurveyOption(id: "websites-dont-work-as-expected", text: UserText.quitSurveyOptionWebsitesDontWork),
        QuitSurveyOption(id: "issues-importing-my-stuff", text: UserText.quitSurveyOptionImportIssues),
        QuitSurveyOption(id: "not-seeing-privacy-benefits", text: UserText.quitSurveyOptionNoPrivacyBenefits),
        QuitSurveyOption(id: "something-else", text: UserText.quitSurveyOptionSomethingElse)
    ]

    private let feedbackSender: FeedbackSenderImplementing
    private let onQuit: () -> Void
    private var autoQuitTimer: Timer?

    // MARK: - Computed Properties

    var shouldShowTextInput: Bool {
        selectedOptions.contains("something-else")
    }

    var shouldEnableSubmit: Bool {
        !selectedOptions.isEmpty || !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initialization

    init(
        feedbackSender: FeedbackSenderImplementing = FeedbackSender(),
        onQuit: @escaping () -> Void
    ) {
        self.feedbackSender = feedbackSender
        self.onQuit = onQuit
    }

    // MARK: - Actions

    func selectPositiveResponse() {
        state = .positiveResponse
        startAutoQuitTimer()
    }

    func selectNegativeResponse() {
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
        let feedback = Feedback.from(
            selectedPillIds: Array(selectedOptions),
            text: feedbackText,
            appVersion: AppVersion.shared.versionNumber,
            category: .bug,
            problemCategory: ProblemCategory.allCategories.first { $0.isSomethingElseCategory } ?? ProblemCategory.allCategories.first!
        )

        feedbackSender.sendFeedback(feedback)
        Logger.general.debug("Quit survey feedback submitted")

        quit()
    }

    func quit() {
        stopAutoQuitTimer()
        onQuit()
    }

    func closeAndQuit() {
        quit()
    }

    // MARK: - Auto Quit Timer

    private func startAutoQuitTimer() {
        autoQuitCountdown = 5
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
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
}
