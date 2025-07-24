//
//  ReportProblemFormView.swift
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

import SwiftUI
import SwiftUIExtensions
import DesignResourcesKit
import DesignResourcesKitIcons

final class ReportProblemFormViewController: NSHostingController<ReportProblemFormFlowView> {

    enum Constants {
        static let width: CGFloat = 448
        static let height: CGFloat = 540

        // Constants for thank you screen
        static let thankYouWidth: CGFloat = 448
        static let thankYouHeight: CGFloat = 232
    }

    override init(rootView: ReportProblemFormFlowView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct ReportProblemFormFlowView: View {
    @State private var showThankYou = false
    @State private var selectedProblemCategory: ProblemCategory?

    var onClose: () -> Void
    var onSeeWhatsNew: () -> Void
    var onResize: (CGFloat, CGFloat) -> Void
    var onReportBrokenSite: (() -> Void)?
    var canReportBrokenSite: Bool

    var body: some View {
        Group {
            if showThankYou {
                ThankYouView(
                    onClose: onClose,
                    onSeeWhatsNew: onSeeWhatsNew
                )
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            onResize(ReportProblemFormViewController.Constants.thankYouWidth,
                                     ReportProblemFormViewController.Constants.thankYouHeight)
                        }
                    }
                }
            } else if let selectedCategory = selectedProblemCategory {
                ProblemDetailFormView(
                    problemCategory: selectedCategory,
                    onSubmit: {
                        showThankYou = true
                    },
                    onBack: {
                        selectedProblemCategory = nil
                    },
                    onClose: onClose
                )
            } else {
                ProblemCategoriesView(
                    onCategorySelected: { category in
                        if category.id == "brokenWebsite" {
                            onReportBrokenSite?()
                            onClose()
                        } else {
                            selectedProblemCategory = category
                        }
                    },
                    onClose: onClose,
                    canReportBrokenSite: canReportBrokenSite
                )
            }
        }
    }
}

// MARK: - Problem Categories

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

struct ProblemCategoriesView: View {
    var onCategorySelected: (ProblemCategory) -> Void
    var onClose: () -> Void
    var canReportBrokenSite: Bool

    private var availableCategories: [ProblemCategory] {
        ProblemCategory.allCategories.filter { category in
            if category.id == "brokenWebsite" {
                return canReportBrokenSite
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                header()
                categoriesList()
            }

            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header() -> some View {
        HStack(spacing: 12) {
            Image(.feedbackAsk)

            VStack(alignment: .leading, spacing: 8) {
                Text(UserText.reportProblemFormTitle)
                    .systemTitle2()

                Text(UserText.reportProblemFormSubtitle)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .padding([.leading, .trailing, .bottom], 24)
    }

    private func categoriesList() -> some View {
        VStack(spacing: 0) {
            ForEach(availableCategories, id: \.id) { category in
                ProblemCategoryView(category: category,
                                    shouldShowDivider: category.id != availableCategories.last?.id,
                                    isTopCategory: category.id == availableCategories.first?.id,
                                    isLastCategory: category.id == availableCategories.last?.id,
                                    onCategorySelected: onCategorySelected)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.toneShade, lineWidth: 1)
        )
        .padding([.leading, .trailing, .bottom], 24)
    }
    private func footer() -> some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color(baseColor: .gray20))
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text(UserText.feedbackDisclaimer)
                .caption2()
                .multilineTextAlignment(.leading)
                .padding([.leading, .trailing], 24)

            Button {
                onClose()
            } label: {
                Text(UserText.cancel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DismissActionButtonStyle())
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}

struct ProblemCategoryView: View {
    let category: ProblemCategory
    let shouldShowDivider: Bool
    let isTopCategory: Bool
    let isLastCategory: Bool
    var onCategorySelected: (ProblemCategory) -> Void

    @State var isHovered: Bool = false

    var body: some View {
        Button {
            onCategorySelected(category)
        } label: {
            HStack {
                Text(category.name)
                    .systemLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(nsImage: DesignSystemImages.Glyphs.Size16.chevronRight)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.controlsFillPrimary : Color.clear)
        .if(isTopCategory) { view in
            view.cornerRadius(6, corners: [.topLeft, .topRight])
        }
        .if(isLastCategory) { view in
            view.cornerRadius(6, corners: [.bottomLeft, .bottomRight])
        }
        .onHover { hovering in
            isHovered = hovering
        }

        if shouldShowDivider {
            Divider()
                .background(isHovered ? Color.clear : Color.toneShade)
                .padding(.horizontal, 8)
        }
    }

}

// MARK: - Problem Detail Form

final class ProblemDetailViewModel: ObservableObject {
    @Published var selectedOptions: Set<String> = []
    @Published var customText: String = ""

    let problemCategory: ProblemCategory
    let availableOptions: [String]

    var shouldEnableSubmit: Bool {
        !selectedOptions.isEmpty || !customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(problemCategory: ProblemCategory) {
        self.problemCategory = problemCategory
        self.availableOptions = problemCategory.subcategories.shuffled().prefix(7) + [UserText.feedbackSomethingElse]
    }

    func toggleOption(_ option: String) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }
}

struct ProblemDetailFormView: View {
    @StateObject private var viewModel: ProblemDetailViewModel

    var onSubmit: () -> Void
    var onBack: () -> Void
    var onClose: () -> Void

    init(problemCategory: ProblemCategory, onSubmit: @escaping () -> Void, onBack: @escaping () -> Void, onClose: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: ProblemDetailViewModel(problemCategory: problemCategory))
        self.onSubmit = onSubmit
        self.onBack = onBack
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                header()
                optionsPills()
                userTextInput()
            }

            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onBack()
            } label: {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.arrowLeft)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.problemCategory.name)
                    .systemTitle2()

                Text(UserText.reportProblemFormSelectAllThatApply)
                    .systemLabel()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func optionsPills() -> some View {
        FlexibleView(
            availableWidth: ReportProblemFormViewController.Constants.width,
            data: viewModel.availableOptions,
            spacing: 8,
            alignment: .leading
        ) { option in
            FeaturePill(
                text: option,
                isSelected: viewModel.selectedOptions.contains(option)
            ) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.toggleOption(option)
                }
            }
        }
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 24)
    }

    private func userTextInput() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UserText.reportProblemFormTellUsMore)
                .systemLabel()

            TextEditor(text: $viewModel.customText)
                .systemLabel()
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(viewModel.customText.isEmpty ? Color(.separatorColor) : Color(baseColor: .blue50),
                                lineWidth: 1)
                )
                .overlay(
                    Group {
                        if viewModel.customText.isEmpty {
                            HStack {
                                VStack {
                                    HStack {
                                        Text(UserText.reportProblemFormPlaceholder)
                                            .systemLabel(color: .textTertiary)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                                .padding(11)
                            }
                        }
                    }
                )
        }
        .padding([.leading, .trailing], 24)
        .padding(.bottom, 8)
    }

    private func footer() -> some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color(baseColor: .gray20))
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            Text(UserText.feedbackDisclaimer)
                .caption2()
                .multilineTextAlignment(.leading)
                .padding([.leading, .trailing], 24)

            HStack(spacing: 10) {
                Button {
                    onClose()
                } label: {
                    Text(UserText.cancel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DismissActionButtonStyle())

                Button {
                    onSubmit()
                } label: {
                    Text(UserText.submit)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: viewModel.shouldEnableSubmit))
            }
            .padding([.leading, .trailing], 24)
            .padding(.bottom, 16)
        }
    }
}
