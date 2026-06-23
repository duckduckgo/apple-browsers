//
//  DataImportSummaryView.swift
//  DuckDuckGo
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

import UIKit
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import BrowserServicesKit
import Lottie
import MetricBuilder

struct DataImportSummaryView: View {

    @ObservedObject var viewModel: DataImportSummaryViewModel

    @State private var isAnimating = false
    @State private var summaryViewWidth: CGFloat = 0
    @State private var summaryRowWidth: CGFloat = 0

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var summaryRowHorizontalInset: CGFloat {
        guard summaryViewWidth > 0, summaryRowWidth > 0 else {
            return 16
        }

        return max(0, (summaryViewWidth - summaryRowWidth) / 2)
    }

    private var summaryRowWidthChangeHandler: (CGFloat) -> Void {
        { width in
            updateMeasuredWidth(width, currentWidth: summaryRowWidth) { nextWidth in
                summaryRowWidth = nextWidth
            }
        }
    }

    init(viewModel: DataImportSummaryViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        adjustedSummaryList
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerOverlay
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Rectangle()
                .foregroundColor(Color(designSystemColor: .surfaceTertiary))
                .ignoresSafeArea()
        )
        .onFirstAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = true
            }
        }
        .background(GeometryReader { proxy -> Color in
            DispatchQueue.main.async {
                updateMeasuredWidth(proxy.size.width, currentWidth: summaryViewWidth) { nextWidth in
                    summaryViewWidth = nextWidth
                }
            }
            return Color.clear
        })
    }

    @ViewBuilder
    private var adjustedSummaryList: some View {
        if #available(iOS 17.0, *), isPad {
            summaryList
                .contentMargins(.top, 0)
        } else {
            summaryList
        }
    }

    private var footerOverlay: some View {
        footer
            .frame(width: summaryRowWidth > 0 ? summaryRowWidth : nil)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                Color(designSystemColor: .surfaceTertiary)
                    .ignoresSafeArea(edges: .bottom)
            )
    }

    private var summaryList: some View {
        List {
            summaryHeader
                .removeGroupedListStyleInsets()
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if viewModel.isAllSuccessful() {
                allSuccessSection
            } else {
                if let passwordsSummary = viewModel.passwordsSummary {
                    summarySection(
                        dataType: .passwords,
                        successString: UserText.dataImportSummaryPasswordsSuccess,
                        summary: passwordsSummary
                    )
                }

                if let bookmarksSummary = viewModel.bookmarksSummary {
                    summarySection(
                        dataType: .bookmarks,
                        successString: UserText.dataImportSummaryBookmarksSuccess,
                        summary: bookmarksSummary
                    )
                }

                if let creditCardsSummary = viewModel.creditCardsSummary {
                    summarySection(
                        dataType: .creditCards,
                        successString: UserText.dataImportSummaryCreditCardsSuccess,
                        summary: creditCardsSummary
                    )
                }
            }
        }
        .compactSectionSpacingIfAvailable()
        .listStyle(.insetGrouped)
        .hideScrollContentBackground()
    }

    private var summaryHeader: some View {
        VStack(spacing: 0) {
            AnimationView(isAnimating: $isAnimating)

            Text(UserText.dataImportSummaryTitle)
                .daxTitle1()
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            if viewModel.shouldShowPasswordsFileDeletionHint {
                Text(UserText.dataImportSummaryPasswordsSubtitle)
                    .daxSubheadRegular()
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var allSuccessSection: some View {
        Section {
            SummaryListRow(
                icon: .success(DataImport.DataType.passwords.summarySuccessIcon),
                label: UserText.dataImportSummaryPasswordsSuccess,
                count: viewModel.passwordsSummary?.successful ?? 0,
                onFrameChange: summaryRowWidthChangeHandler
            )

            SummaryListRow(
                icon: .success(DataImport.DataType.bookmarks.summarySuccessIcon),
                label: UserText.dataImportSummaryBookmarksSuccess,
                count: viewModel.bookmarksSummary?.successful ?? 0,
                onFrameChange: summaryRowWidthChangeHandler
            )

            if let creditCardsSummary = viewModel.creditCardsSummary {
                SummaryListRow(
                    icon: .success(DataImport.DataType.creditCards.summarySuccessIcon),
                    label: UserText.dataImportSummaryCreditCardsSuccess,
                    count: creditCardsSummary.successful,
                    onFrameChange: summaryRowWidthChangeHandler
                )
            }
        }
    }

    private func summarySection(dataType: DataImport.DataType,
                                successString: String,
                                summary: DataImport.DataTypeSummary) -> some View {
        Section {
            SummaryListRow(
                icon: .success(dataType.summarySuccessIcon),
                label: successString,
                count: summary.successful,
                onFrameChange: summaryRowWidthChangeHandler
            )

            if summary.failed > 0 {
                SummaryListRow(
                    icon: .failure,
                    label: UserText.dataImportSummaryFailed,
                    count: summary.failed,
                    onFrameChange: summaryRowWidthChangeHandler
                )
            }

            if summary.duplicate > 0 {
                SummaryListRow(
                    icon: .failure,
                    label: UserText.dataImportSummaryDuplicates,
                    count: summary.duplicate,
                    onFrameChange: summaryRowWidthChangeHandler
                )
            }
        }
    }

    private func syncButton(title: String) -> some View {
        Button {
            viewModel.launchSync(source: SyncSettingsViewController.SourceConstants.dataImportSummary)
        } label: {
            VStack {
                Text(title)
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(GhostButtonStyle())
        .onFirstAppear {
            viewModel.fireSyncButtonShownPixel()
        }
    }

    private var footer: some View {
        VStack {
            switch viewModel.footer {
            case .syncButton(let title):
                dismissButton
                
                syncButton(title: title)
            case .syncPromo(let title):
                SyncAndBackupCard(title: title, onSyncTapped: {
                    viewModel.launchSync(source: SyncSettingsViewController.SourceConstants.dataImportSummarySyncPromotion, fromSyncPromo: true)
                }, viewModel: viewModel)
                .onFirstAppear {
                    viewModel.fireSyncPromoDisplayedPixel()
                }
            case .passwordsPromo:
                ContinueImportCard(
                    title: UserText.dataImportSummaryPasswordsPromoTitle,
                    icon: Image(uiImage: DesignSystemImages.Color.Size96.passwordsKeychainFeature),
                    dismissButtonTitle: UserText.dataImportSummaryPromoDismissAction,
                    continueButtonTitle: UserText.dataImportSummaryPromoContinueAction,
                    onDismissTapped: { viewModel.handleContinueImportAction(.dismissTapped, for: .passwords) },
                    onContinueTapped: { viewModel.handleContinueImportAction(.continueTapped, for: .passwords) }
                )
                .onFirstAppear {
                    viewModel.handleContinueImportAction(.shown, for: .passwords)
                }
            case .bookmarksPromo:
                ContinueImportCard(
                    title: UserText.dataImportSummaryBookmarksPromoTitle,
                    icon: Image(uiImage: DesignSystemImages.Color.Size96.extensionSafari),
                    dismissButtonTitle: UserText.dataImportSummaryPromoDismissAction,
                    continueButtonTitle: UserText.dataImportSummaryPromoContinueAction,
                    onDismissTapped: { viewModel.handleContinueImportAction(.dismissTapped, for: .bookmarks) },
                    onContinueTapped: { viewModel.handleContinueImportAction(.continueTapped, for: .bookmarks) }
                )
                .onFirstAppear {
                    viewModel.handleContinueImportAction(.shown, for: .bookmarks)
                }
            case .message(let body):
                dismissButton
                
                footerMessage(body: body)
                    .padding(.top, 8)
            case .none:
                dismissButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 16)
        .padding(.bottom, isPad ? summaryRowHorizontalInset : 0)
    }

    private func updateMeasuredWidth(_ width: CGFloat,
                                     currentWidth: CGFloat,
                                     setWidth: (CGFloat) -> Void) {
        let nextWidth = max(0, width)

        guard nextWidth > 0 else { return }
        guard abs(nextWidth - currentWidth) > 0.5 else { return }
        setWidth(nextWidth)
    }

    private var dismissButton: some View {
        Button {
            viewModel.doneTapped()
        } label: {
            Text(UserText.dataImportSummaryDone)
        }
        .buttonStyle(PrimaryButtonStyle())
        .frame(maxWidth: 360)
    }

    private func footerMessage(body: String) -> some View {
        Text(body)
            .font(.system(size: 13))
            .foregroundStyle(Color.secondary)
            .lineLimit(nil)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    fileprivate struct AnimationView: View {
        @Binding var isAnimating: Bool

        var body: some View {
            LottieView(
                lottieFile: "burst-blob-passwords",
                isAnimating: $isAnimating
            )
            .frame(width: 200, height: 128)
        }
    }

    fileprivate struct SummaryListRow: View {
        enum Icon {
            case success(UIImage)
            case failure
        }

        let icon: Icon
        let label: String
        let count: Int
        let onFrameChange: ((CGFloat) -> Void)?

        var body: some View {
            HStack {
                HStack(spacing: 12) {
                    switch icon {
                    case .success(let successIcon):
                        Image(uiImage: successIcon)
                    case .failure:
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.crossRecolorable)
                    }

                    Text(label)
                        .daxBodyRegular()
                        .foregroundStyle(Color(designSystemColor: .textPrimary))
                }

                Spacer()

                Text("\(count)")
                    .daxBodyRegular()
                    .foregroundStyle(Color(designSystemColor: .textSecondary))
            }
            .listRowBackground(
                Color(designSystemColor: .surface)
                    .background(GeometryReader { proxy -> Color in
                        DispatchQueue.main.async {
                            onFrameChange?(proxy.size.width)
                        }
                        return Color.clear
                    })
            )
        }
    }

    fileprivate struct ContinueImportCard: View {
        let title: String
        let icon: Image
        let dismissButtonTitle: String
        let continueButtonTitle: String
        let onDismissTapped: () -> Void
        let onContinueTapped: () -> Void

        var body: some View {
            VStack(alignment: .center, spacing: 0) {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                    .padding(.top, 16)

                Text(title)
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    Button(dismissButtonTitle, action: onDismissTapped)
                        .buttonStyle(SecondaryFillButtonStyle(compact: true))

                    Button(continueButtonTitle, action: onContinueTapped)
                        .buttonStyle(DuckUI.PrimaryButtonStyle(compact: true))
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
                    .fill(Color(designSystemColor: .surface))
            )
        }

        fileprivate enum Metrics {
            static var imageSize: CGFloat { AppRebrand.isAppRebranded() ? 96 : 64 }
        }
    }

    private struct SyncAndBackupCard: View {
        let title: String
        let onSyncTapped: () -> Void
        @ObservedObject var viewModel: DataImportSummaryViewModel
        
        var body: some View {
            VStack(alignment: .center, spacing: 0) {
                Image(rebrandable: "Sync-Pending-96")
                    .resizable()
                    .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                    .padding(.top, 16)
                
                Text(title)
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                
                HStack(spacing: 8) {
                    Button(UserText.syncPromoDismissAction, action: viewModel.dismissSyncPromo)
                        .buttonStyle(SecondaryFillButtonStyle(compact: true))

                    Button(UserText.syncPromoConfirmAction, action: onSyncTapped)
                        .buttonStyle(DuckUI.PrimaryButtonStyle(compact: true))
                        .onFirstAppear {
                            viewModel.fireSyncButtonShownPixel()
                        }
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: ContainerMetrics.cornerRadius)
                    .fill(Color(designSystemColor: .surface))
            )
        }

        fileprivate enum Metrics {
            static let imageSize: CGFloat = 64
        }
    }

}

private extension DataImport.DataType {

    var summarySuccessIcon: UIImage {
        switch self {
        case .bookmarks:
            return DesignSystemImages.Color.Size24.bookmarkCheck
        case .passwords:
            return DesignSystemImages.Color.Size24.keyCheck
        case .creditCards:
            return DesignSystemImages.Color.Size24.creditCardCheck
        }
    }
}

#Preview("Summary Rows") {
    List {
        DataImportSummaryView.SummaryListRow(
            icon: .success(DataImport.DataType.passwords.summarySuccessIcon),
            label: "Passwords",
            count: 42,
            onFrameChange: nil
        )
        DataImportSummaryView.SummaryListRow(
            icon: .failure,
            label: "Failed",
            count: 3,
            onFrameChange: nil
        )
    }
}

#Preview("Continue Import Card") {
    DataImportSummaryView.ContinueImportCard(
        title: "Continue importing your passwords?",
        icon: Image(uiImage: DesignSystemImages.Color.Size96.passwordsKeychainFeature),
        dismissButtonTitle: "Not Now",
        continueButtonTitle: "Continue",
        onDismissTapped: {},
        onContinueTapped: {}
    )
}

#Preview("Summary Animation") {
    DataImportSummaryView.AnimationView(isAnimating: .constant(true))
}
