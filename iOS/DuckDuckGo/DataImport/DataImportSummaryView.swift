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
        VStack {
            VStack(spacing: 0) {
                AnimationView(isAnimating: $isAnimating)
                
                Text(UserText.dataImportSummaryTitle)
                    .daxTitle1()
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                
                if viewModel.isAllSuccessful() {
                    SuccessContainer(
                        passwordsSuccessCount: viewModel.passwordsSummary?.successful ?? 0,
                        bookmarksSuccessCount: viewModel.bookmarksSummary?.successful ?? 0,
                        creditCardsSuccessCount: viewModel.creditCardsSummary?.successful
                    )
                } else {
                    if viewModel.passwordsSummary != nil {
                        Text(UserText.dataImportSummaryPasswordsSubtitle)
                            .daxSubheadRegular()
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    
                    ScrollView {
                        
                        VStack(spacing: 28) {
                            if let passwordsSummary = viewModel.passwordsSummary {
                                StatsContainer(
                                    successString: UserText.dataImportSummaryPasswordsSuccess,
                                    successCount: passwordsSummary.successful,
                                    failureCount: passwordsSummary.failed,
                                    duplicatesCount: passwordsSummary.duplicate
                                )
                            }
                            
                            if let bookmarksSummary = viewModel.bookmarksSummary {
                                StatsContainer(
                                    successString: UserText.dataImportSummaryBookmarksSuccess,
                                    successCount: bookmarksSummary.successful,
                                    failureCount: bookmarksSummary.failed,
                                    duplicatesCount: bookmarksSummary.duplicate
                                )
                            }
                            
                            if let creditCardsSummary = viewModel.creditCardsSummary {
                                StatsContainer(
                                    successString: UserText.dataImportSummaryCreditCardsSuccess,
                                    successCount: creditCardsSummary.successful,
                                    failureCount: creditCardsSummary.failed,
                                    duplicatesCount: creditCardsSummary.duplicate
                                )
                            }
                        }
                        .padding(.trailing, 16) // Used to position scroll indicator outside of content area
                        
                    }
                    .padding(.trailing, -16)
                    .padding(.top, 28)
                }
            }
            .frame(maxWidth: 360)
            
            
            Spacer()
            
            footer
            
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
        .padding(.horizontal, 24)
        .background(Rectangle()
            .foregroundColor(Color(designSystemColor: .surfaceTertiary))
            .ignoresSafeArea())
        .onFirstAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAnimating = true
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
                    viewModel.launchSync(source: SyncSettingsViewController.SourceConstants.dataImportSummarySyncPromotion)
                }, viewModel: viewModel)
                .onFirstAppear {
                    viewModel.fireSyncPromoDisplayedPixel()
                }
            case .message(let body):
                dismissButton
                
                footerMessage(body: body)
                    .padding(.top, 8)
            case .none:
                dismissButton
            }
        }
        .frame(maxWidth: 360)
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
            .padding(.top, 64)
        }
    }


    private struct SuccessContainer: View {
        var passwordsSuccessCount: Int
        var bookmarksSuccessCount: Int
        var creditCardsSuccessCount: Int?

        var body: some View {
            Text(UserText.dataImportSummaryPasswordsSubtitle)
                .daxSubheadRegular()
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textSecondary))
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                StatRow(isSuccess: true,
                        label: UserText.dataImportSummaryPasswordsSuccess,
                        count: passwordsSuccessCount,
                        showSeparator: true)

                StatRow(isSuccess: true,
                        label: UserText.dataImportSummaryBookmarksSuccess,
                        count: bookmarksSuccessCount,
                        showSeparator: creditCardsSuccessCount != nil ? true : false)

                if let creditCardsSuccessCount = creditCardsSuccessCount {
                    StatRow(isSuccess: true,
                            label: UserText.dataImportSummaryCreditCardsSuccess,
                            count: creditCardsSuccessCount,
                            showSeparator: false)
                }
            }
            .padding(.vertical, 12)
            .background(Color(designSystemColor: .panel))
            .cornerRadius(10)
        }
    }

    private struct StatsContainer: View {
        var successString: String
        var successCount: Int
        var failureCount: Int
        var duplicatesCount: Int

        var body: some View {
            VStack(spacing: 12) {
                StatRow(isSuccess: true,
                        label: successString,
                        count: successCount,
                        showSeparator: failureCount != 0 || duplicatesCount != 0)

                if failureCount > 0 {
                    StatRow(isSuccess: false,
                            label: UserText.dataImportSummaryFailed,
                            count: failureCount,
                            showSeparator: duplicatesCount != 0)
                }

                if duplicatesCount > 0 {
                    StatRow(isSuccess: false,
                            label: UserText.dataImportSummaryDuplicates,
                            count: duplicatesCount,
                            showSeparator: false)
                }
            }
            .padding(.vertical, 12)
            .background(Color(designSystemColor: .panel))
            .cornerRadius(10)
        }
    }

    private struct StatRow: View {
        let isSuccess: Bool
        let label: String
        let count: Int
        let showSeparator: Bool

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 12) {
                        if isSuccess {
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.checkRecolorable).renderingMode(.template)
                                .resizable()
                                .frame(width: 21, height: 21)
                                .foregroundStyle(Color(designSystemColor: .alertGreen))
                                .padding(.leading, 2)
                        } else {
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
                .padding(.horizontal, 16)

                if showSeparator {
                    Divider()
                        .padding(.top, 12)
                        .padding(.leading, 54)
                        .padding(.trailing, 0)
                        .foregroundStyle(Color(designSystemColor: .lines))
                }
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
                    .fill(Color(designSystemColor: .panel))
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
