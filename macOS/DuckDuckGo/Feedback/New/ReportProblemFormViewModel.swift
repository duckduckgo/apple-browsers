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
    @Published var selectedOptions: Set<String> = []
    @Published var customText: String = ""

    // MARK: - Properties

    private let feedbackSender = FeedbackSender()
    let canReportBrokenSite: Bool
    private let onReportBrokenSite: (() -> Void)?
    private(set) var availableOptions: [String] = []

    // MARK: - Computed Properties

    var availableCategories: [ProblemCategory] {
        ProblemCategory.allCategories.filter { category in
            if category.id == "brokenWebsite" {
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

    init(canReportBrokenSite: Bool, onReportBrokenSite: (() -> Void)?) {
        self.canReportBrokenSite = canReportBrokenSite
        self.onReportBrokenSite = onReportBrokenSite
    }

    // MARK: - Methods

    func selectCategory(_ category: ProblemCategory) {
        if category.id == "brokenWebsite" {
            onReportBrokenSite?()
        } else {
            selectedProblemCategory = category
            // Set available options once when category is selected (shuffled once and stable)
            availableOptions = Array(category.subcategories.shuffled().prefix(7)) + [UserText.feedbackSomethingElse]
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

    func toggleOption(_ option: String) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }

    func submitFeedback() {
        guard let category = selectedProblemCategory else { return }
        let selectedOptionsString = selectedOptions.map { $0.toTag }.joined(separator: ",")
        let subcategory = "\(category.name.toTag),\(selectedOptionsString)"
        let description = customText.isEmpty ? category.name : customText
        let feedback = Feedback(category: .bug,
                                comment: description,
                                appVersion: "\(AppVersion.shared.versionNumber)",
                                osVersion: "\(ProcessInfo.processInfo.operatingSystemVersion)",
                                subcategory: subcategory)

//         feedbackSender.sendFeedback(feedback)

        // Reset form state and show thank you
        selectedProblemCategory = nil
        availableOptions.removeAll()
        selectedOptions.removeAll()
        customText = ""
        showThankYou = true
    }
}

// MARK: - ProblemCategory Model

struct ProblemCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let subcategories: [String]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ProblemCategory, rhs: ProblemCategory) -> Bool {
        lhs.id == rhs.id
    }

    static let allCategories: [ProblemCategory] = [
        ProblemCategory(
            id: "browserTooSlow",
            name: UserText.problemCategoryBrowserTooSlow,
            subcategories: [
                UserText.problemSubcategoryBrowserStartsSlowly,
                UserText.problemSubcategoryBrowserUsesTooMuchMemory,
                UserText.problemSubcategoryChangingTabsTakesTooLong,
                UserText.problemSubcategoryNewTabsOpenSlowly,
                UserText.problemSubcategoryWebsitesLoadSlowly
            ]
        ),
        ProblemCategory(
            id: "browserDoesntWork",
            name: UserText.problemCategoryBrowserDoesntWork,
            subcategories: [
                UserText.problemSubcategoryBrowserUsesTooMuchMemory,
                UserText.problemSubcategoryCameraAudioPermissions,
                UserText.problemSubcategoryCantRestartFailedDownloads,
                UserText.problemSubcategoryConfusingOrMissingSettings,
                UserText.problemSubcategoryLoggedOutUnexpectedly,
                UserText.problemSubcategoryLostTabsOrHistory,
                UserText.problemSubcategoryNoDownloadHistory,
                UserText.problemSubcategoryTooManyCaptchas,
                UserText.problemSubcategoryVideoAudioPlaysAutomatically,
                UserText.problemSubcategoryVideoDoesntPlay
            ]
        ),
        ProblemCategory(
            id: "installUpdates",
            name: UserText.problemCategoryInstallUpdates,
            subcategories: [
                UserText.problemSubcategoryBrowserVersionIssues,
                UserText.problemSubcategoryCantControlUpdates,
                UserText.problemSubcategoryInstalling,
                UserText.problemSubcategoryUninstalling,
                UserText.problemSubcategoryTooManyUpdates
            ]
        ),
        ProblemCategory(
            id: "brokenWebsite",
            name: UserText.problemCategoryBrokenWebsite,
            subcategories: [
                UserText.problemSubcategorySiteWontLoad,
                UserText.problemSubcategorySiteLooksBroken,
                UserText.problemSubcategoryFeaturesDontWork,
                UserText.problemSubcategorySomethingElse
            ]
        ),
        ProblemCategory(
            id: "adsIssues",
            name: UserText.problemCategoryAdsIssues,
            subcategories: [
                UserText.problemSubcategoryBannerAdsBlockingContent,
                UserText.problemSubcategoryDistractingAnimationsOnAds,
                UserText.problemSubcategoryInterruptingPopups,
                UserText.problemSubcategoryLargeBannerAds,
                UserText.problemSubcategorySiteAsksToTurnOffAdBlocker
            ]
        ),
        ProblemCategory(
            id: "passwordIssues",
            name: UserText.problemCategoryPasswordIssues,
            subcategories: [
                UserText.problemSubcategoryCantSyncPasswords,
                UserText.problemSubcategoryExportingPasswords,
                UserText.problemSubcategoryImportingPasswords,
                UserText.problemSubcategoryPasswordsManagement
            ]
        ),
        ProblemCategory(
            id: "somethingElse",
            name: UserText.problemCategorySomethingElse,
            subcategories: [
                UserText.problemSubcategoryCantCompleteAPurchase,
                UserText.problemSubcategoryCantRestartFailedDownloads,
                UserText.problemSubcategoryConfusingOrMissingSettings,
                UserText.problemSubcategoryNoDownloadsHistory,
                UserText.problemSubcategoryVideoAudioPlaysAutomatically
            ]
        )
    ]
}

extension String {
    var toTag: String {
        self
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
    }
}
