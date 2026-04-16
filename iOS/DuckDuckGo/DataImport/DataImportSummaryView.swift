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

struct DataImportSummaryView: View {

    @ObservedObject var viewModel: DataImportSummaryViewModel

    @State private var isAnimating = false

    init(viewModel: DataImportSummaryViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            summaryList

            footer
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
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
    }

    private var allSuccessSection: some View {
        Section {
            SummaryListRow(
                icon: .success(DataImport.DataType.passwords.summarySuccessIcon),
                label: UserText.dataImportSummaryPasswordsSuccess,
                count: viewModel.passwordsSummary?.successful ?? 0
            )

            SummaryListRow(
                icon: .success(DataImport.DataType.bookmarks.summarySuccessIcon),
                label: UserText.dataImportSummaryBookmarksSuccess,
                count: viewModel.bookmarksSummary?.successful ?? 0
            )

            if let creditCardsSummary = viewModel.creditCardsSummary {
                SummaryListRow(
                    icon: .success(DataImport.DataType.creditCards.summarySuccessIcon),
                    label: UserText.dataImportSummaryCreditCardsSuccess,
                    count: creditCardsSummary.successful
                )
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
    }

    private func summarySection(dataType: DataImport.DataType,
                                successString: String,
                                summary: DataImport.DataTypeSummary) -> some View {
        Section {
            SummaryListRow(
                icon: .success(dataType.summarySuccessIcon),
                label: successString,
                count: summary.successful
            )

            if summary.failed > 0 {
                SummaryListRow(
                    icon: .failure,
                    label: UserText.dataImportSummaryFailed,
                    count: summary.failed
                )
            }

            if summary.duplicate > 0 {
                SummaryListRow(
                    icon: .failure,
                    label: UserText.dataImportSummaryDuplicates,
                    count: summary.duplicate
                )
            }
        }
        .listRowBackground(Color(designSystemColor: .surface))
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
                    viewModel.launchSync(source: SyncSettingsViewController.SourceConstants.dataImportSummarySyncPromotion)
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
                    onDismissTapped: { viewModel.dismiss() },
                    onContinueTapped: { viewModel.continueImportFromSafari() }
                )
            case .bookmarksPromo:
                ContinueImportCard(
                    title: UserText.dataImportSummaryBookmarksPromoTitle,
                    icon: Image(uiImage: DesignSystemImages.Color.Size96.extensionSafari),
                    dismissButtonTitle: UserText.dataImportSummaryPromoDismissAction,
                    continueButtonTitle: UserText.dataImportSummaryPromoContinueAction,
                    onDismissTapped: { viewModel.dismiss() },
                    onContinueTapped: { viewModel.continueImportFromSafari() }
                )
            case .message(let body):
                dismissButton
                
                footerMessage(body: body)
                    .padding(.top, 8)
            case .none:
                dismissButton
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 36)
    }

    private var dismissButton: some View {
        Button {
            viewModel.dismiss()
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

    private struct AnimationView: View {
        @Binding var isAnimating: Bool

        var body: some View {
            LottieView(
                lottieFile: "burst-blob-passwords",
                isAnimating: $isAnimating
            )
            .frame(width: 200, height: 128)
            .padding(.top, 48)
        }
    }

    private struct SummaryListRow: View {
        enum Icon {
            case success(UIImage)
            case failure
        }

        let icon: Icon
        let label: String
        let count: Int

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
        }
    }

    private struct ContinueImportCard: View {
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
                    .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                    .padding(.top, 16)

                Text(title)
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)

                HStack(spacing: 8) {
                    Button {
                        onDismissTapped()
                    } label: {
                        Text(dismissButtonTitle)
                            .daxButton()
                            .foregroundStyle(Color(designSystemColor: .textPrimary))
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.buttonHeight)
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        onContinueTapped()
                    } label: {
                        Text(continueButtonTitle)
                            .daxButton()
                            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.buttonHeight)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(designSystemColor: .surface))
            )
        }

        fileprivate enum Metrics {
            static let buttonCornerRadius: CGFloat = 12
            static let buttonHeight: CGFloat = 40
            static let imageSize: CGFloat = 64
        }

        private struct SecondaryButtonStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .background(configuration.isPressed ? Color(designSystemColor: .controlsFillSecondary) : Color(designSystemColor: .controlsFillPrimary))
                    .cornerRadius(Metrics.buttonCornerRadius)
            }
        }

        private struct PrimaryButtonStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .background(configuration.isPressed ? Color(designSystemColor: .buttonsPrimaryPressed) : Color(designSystemColor: .buttonsPrimaryDefault))
                    .cornerRadius(Metrics.buttonCornerRadius)
            }
        }
    }

    private struct SyncAndBackupCard: View {
        let title: String
        let onSyncTapped: () -> Void
        @ObservedObject var viewModel: DataImportSummaryViewModel
        
        var body: some View {
            VStack(alignment: .center, spacing: 0) {
                Image("Sync-Pending-96")
                    .resizable()
                    .frame(width: Metrics.imageSize, height: Metrics.imageSize)
                    .padding(.top, 16)
                
                Text(title)
                    .daxHeadline()
                    .foregroundStyle(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                
                HStack(spacing: 8) {
                    Button {
                        viewModel.dismissSyncPromo()
                    } label: {
                        Text(UserText.syncPromoDismissAction)
                            .font(Font(UIFont.boldSystemFont(ofSize: Metrics.buttonFontSize)))
                            .foregroundStyle(Color(designSystemColor: .textPrimary))
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.buttonHeight)
                    }
                    .buttonStyle(SecondarySyncButtonStyle())
                    
                    Button {
                        onSyncTapped()
                    } label: {
                        Text(UserText.syncPromoConfirmAction)
                            .font(Font(UIFont.boldSystemFont(ofSize: Metrics.buttonFontSize)))
                            .foregroundColor(Color(designSystemColor: .buttonsPrimaryText))
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.buttonHeight)
                    }
                    .buttonStyle(PrimarySyncButtonStyle())
                    .onFirstAppear {
                        viewModel.fireSyncButtonShownPixel()
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(designSystemColor: .surface))
            )
        }
        
        fileprivate enum Metrics {
            static let buttonCornerRadius: CGFloat = 12
            static let buttonHeight: CGFloat = 40
            static let buttonFontSize: CGFloat = 15
            static let imageSize: CGFloat = 64
        }
        
        private struct SecondarySyncButtonStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .background(configuration.isPressed ? Color(designSystemColor: .controlsFillSecondary) : Color(designSystemColor: .controlsFillPrimary))
                    .cornerRadius(Metrics.buttonCornerRadius)
            }
        }
        
        private struct PrimarySyncButtonStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .background(configuration.isPressed ? Color(designSystemColor: .buttonsPrimaryPressed) : Color(designSystemColor: .buttonsPrimaryDefault))
                    .cornerRadius(Metrics.buttonCornerRadius)
            }
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
