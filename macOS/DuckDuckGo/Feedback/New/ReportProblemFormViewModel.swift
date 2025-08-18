//
//  ReportProblemFormViewModel.swift
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
import SwiftUI
import Common

final class ReportProblemFormViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var showThankYou = false
    @Published var selectedProblemCategory: ProblemCategory?
    @Published var selectedOptions: Set<String> = []  // Now stores SubCategory IDs
    @Published var customText: String = ""

    // MARK: - Properties

    private let feedbackSender: FeedbackSenderImplementing
    let canReportBrokenSite: Bool
    private let onReportBrokenSite: (() -> Void)?
    private(set) var availableOptions: [SubCategory] = []

    // MARK: - Computed Properties

    var availableCategories: [ProblemCategory] {
        ProblemCategory.allCategories.filter { category in
            if category.isReportBrokenWebsiteCategory {
                return canReportBrokenSite
            }
            return true
        }
    }

    var isShowingCategorySelection: Bool {
        selectedProblemCategory == nil && !showThankYou
    }

    var isShowingDetailForm: Bool {
        selectedProblemCategory != nil && !showThankYou
    }

    var shouldEnableSubmit: Bool {
        !selectedOptions.isEmpty || !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initialization

    init(canReportBrokenSite: Bool,
         onReportBrokenSite: (() -> Void)?,
         feedbackSender: FeedbackSenderImplementing = FeedbackSender()) {
        self.canReportBrokenSite = canReportBrokenSite
        self.onReportBrokenSite = onReportBrokenSite
        self.feedbackSender = feedbackSender
    }

    // MARK: - Methods

    func selectCategory(_ category: ProblemCategory) {
        if category.isReportBrokenWebsiteCategory {
            onReportBrokenSite?()
        } else {
            selectedProblemCategory = category
            // Set available options once when category is selected (shuffled once and stable)
            let shuffledSubcategories = Array(category.subcategories.shuffled().prefix(7))
            let somethingElseOption = SubCategory(id: "something-else", text: UserText.feedbackSomethingElse)
            availableOptions = shuffledSubcategories + [somethingElseOption]
            // Reset form data when selecting a new category
            selectedOptions.removeAll()
            customText = ""
        }
    }

    func goBackToCategorySelection() {
        selectedProblemCategory = nil
        availableOptions.removeAll()
        selectedOptions.removeAll()
        customText = ""
    }

    func toggleOption(_ optionId: String) {
        if selectedOptions.contains(optionId) {
            selectedOptions.remove(optionId)
        } else {
            selectedOptions.insert(optionId)
        }
    }

    func submitFeedback() {
        guard let category = selectedProblemCategory else { return }

        let feedback = Feedback.from(selectedPillIds: Array(selectedOptions),
                                     text: customText,
                                     appVersion: AppVersion.shared.versionNumber,
                                     category: .bug,
                                     problemCategory: category)

        feedbackSender.sendFeedback(feedback)
        showThankYou = true
    }
}

// MARK: - ProblemCategory Model

struct SubCategory: Identifiable, Hashable {
    let id: String      // Backend identifier (e.g., "banner-ads-blocking-content")
    let text: String    // Localized display text

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SubCategory, rhs: SubCategory) -> Bool {
        lhs.id == rhs.id
    }
}

struct ProblemCategory: Identifiable, Hashable {
    let id: String              // Backend identifier (e.g., "ads-causing-issues")
    let text: String            // Localized display text
    let subcategories: [SubCategory]

    var isReportBrokenWebsiteCategory: Bool { id == Self.reportBrokenWebsiteID }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProblemCategory, rhs: ProblemCategory) -> Bool {
        lhs.id == rhs.id
    }

    private static let reportBrokenWebsiteID = "report-broken-website"

    static let allCategories: [ProblemCategory] = [
        ProblemCategory(
            id: "computer-or-browser-is-too-slow",
            text: UserText.problemCategoryBrowserTooSlow,
            subcategories: [
                SubCategory(id: "browser-starts-slowly", text: UserText.problemSubcategoryBrowserStartsSlowly),
                SubCategory(id: "browser-uses-too-much-memory", text: UserText.problemSubcategoryBrowserUsesTooMuchMemory),
                SubCategory(id: "changing-tabs-takes-too-long", text: UserText.problemSubcategoryChangingTabsTakesTooLong),
                SubCategory(id: "new-tabs-open-slowly", text: UserText.problemSubcategoryNewTabsOpenSlowly),
                SubCategory(id: "websites-load-slowly", text: UserText.problemSubcategoryWebsitesLoadSlowly)
            ]
        ),
        ProblemCategory(
            id: "browser-doesnt-work-as-expected",
            text: UserText.problemCategoryBrowserDoesntWork,
            subcategories: [
                SubCategory(id: "browser-uses-too-much-memory", text: UserText.problemSubcategoryBrowserUsesTooMuchMemory),
                SubCategory(id: "camera-audio-permissions", text: UserText.problemSubcategoryCameraAudioPermissions),
                SubCategory(id: "cant-restart-failed-downloads", text: UserText.problemSubcategoryCantRestartFailedDownloads),
                SubCategory(id: "confusing-or-missing-settings", text: UserText.problemSubcategoryConfusingOrMissingSettings),
                SubCategory(id: "logged-out-unexpectedly", text: UserText.problemSubcategoryLoggedOutUnexpectedly),
                SubCategory(id: "lost-tabs-or-history", text: UserText.problemSubcategoryLostTabsOrHistory),
                SubCategory(id: "no-download-history", text: UserText.problemSubcategoryNoDownloadHistory),
                SubCategory(id: "too-many-captchas", text: UserText.problemSubcategoryTooManyCaptchas),
                SubCategory(id: "video-audio-plays-automatically", text: UserText.problemSubcategoryVideoAudioPlaysAutomatically),
                SubCategory(id: "video-doesnt-play", text: UserText.problemSubcategoryVideoDoesntPlay)
            ]
        ),
        ProblemCategory(
            id: "browser-install-and-updates",
            text: UserText.problemCategoryInstallUpdates,
            subcategories: [
                SubCategory(id: "browser-version-issues", text: UserText.problemSubcategoryBrowserVersionIssues),
                SubCategory(id: "cant-control-updates", text: UserText.problemSubcategoryCantControlUpdates),
                SubCategory(id: "installing", text: UserText.problemSubcategoryInstalling),
                SubCategory(id: "uninstalling", text: UserText.problemSubcategoryUninstalling),
                SubCategory(id: "too-many-updates", text: UserText.problemSubcategoryTooManyUpdates)
            ]
        ),
        ProblemCategory(
            id: reportBrokenWebsiteID,
            text: UserText.problemCategoryBrokenWebsite,
            subcategories: [
                SubCategory(id: "site-wont-load", text: UserText.problemSubcategorySiteWontLoad),
                SubCategory(id: "site-looks-broken", text: UserText.problemSubcategorySiteLooksBroken),
                SubCategory(id: "features-dont-work", text: UserText.problemSubcategoryFeaturesDontWork),
                SubCategory(id: "something-else", text: UserText.problemSubcategorySomethingElse)
            ]
        ),
        ProblemCategory(
            id: "ads-causing-issues",
            text: UserText.problemCategoryAdsIssues,
            subcategories: [
                SubCategory(id: "banner-ads-blocking-content", text: UserText.problemSubcategoryBannerAdsBlockingContent),
                SubCategory(id: "distracting-animations-on-ads", text: UserText.problemSubcategoryDistractingAnimationsOnAds),
                SubCategory(id: "interrupting-pop-ups", text: UserText.problemSubcategoryInterruptingPopups),
                SubCategory(id: "large-banner-ads", text: UserText.problemSubcategoryLargeBannerAds),
                SubCategory(id: "site-asks-to-turn-off-ad-blocker", text: UserText.problemSubcategorySiteAsksToTurnOffAdBlocker)
            ]
        ),
        ProblemCategory(
            id: "password-issues",
            text: UserText.problemCategoryPasswordIssues,
            subcategories: [
                SubCategory(id: "cant-sync-passwords", text: UserText.problemSubcategoryCantSyncPasswords),
                SubCategory(id: "exporting-passwords", text: UserText.problemSubcategoryExportingPasswords),
                SubCategory(id: "importing-passwords", text: UserText.problemSubcategoryImportingPasswords),
                SubCategory(id: "passwords-management", text: UserText.problemSubcategoryPasswordsManagement)
            ]
        ),
        ProblemCategory(
            id: "something-else",
            text: UserText.problemCategorySomethingElse,
            subcategories: [
                SubCategory(id: "cant-complete-a-purchase", text: UserText.problemSubcategoryCantCompleteAPurchase),
                SubCategory(id: "cant-restart-failed-downloads", text: UserText.problemSubcategoryCantRestartFailedDownloads),
                SubCategory(id: "confusing-or-missing-settings", text: UserText.problemSubcategoryConfusingOrMissingSettings),
                SubCategory(id: "no-downloads-history", text: UserText.problemSubcategoryNoDownloadsHistory),
                SubCategory(id: "video-audio-plays-automatically", text: UserText.problemSubcategoryVideoAudioPlaysAutomatically)
            ]
        )
    ]
}
