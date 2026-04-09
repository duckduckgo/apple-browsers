//
//  SettingsYouTubeAdBlockingView.swift
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

import Core
import SwiftUI
import DesignResourcesKit
import DuckUI

struct SettingsYouTubeAdBlockingView: View {

    /// The ContingencyMessageView may be redrawn multiple times in the onAppear method if the user scrolls it outside the list bounds.
    /// This property ensures that the associated action is only triggered once per viewing session, preventing redundant executions.
    @State private var hasFiredSettingsDisplayedPixel = false

    @EnvironmentObject var viewModel: SettingsViewModel
    var body: some View {
        List {
            if viewModel.shouldDisplayDuckPlayerContingencyMessage {
                Section {
                    ContingencyMessageView {
                        viewModel.openDuckPlayerContingencyMessageSite()
                    }.onAppear {
                        if !hasFiredSettingsDisplayedPixel {
                            Pixel.fire(pixel: .duckPlayerContingencySettingsDisplayed)
                            hasFiredSettingsDisplayedPixel = true
                        }
                    }
                }
            }

            if !viewModel.shouldDisplayDuckPlayerContingencyMessage {
                Section {
                    VStack(alignment: .center, spacing: 16) {
                        Image(.settingsYoutubeHero)
                            .padding(.top, 8)

                        Text(UserText.youTubeAdBlockingTitle)
                            .daxTitle3()
                            .foregroundColor(Color(designSystemColor: .textPrimary))

                        Text(UserText.youTubeAdBlockingExplanation)
                            .daxBodyRegular()
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(designSystemColor: .textSecondary))
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 8)
                }

                Section {
                    SettingsCellView(
                        label: UserText.youTubeAdBlockingToggle,
                        accessory: .toggle(isOn: viewModel.youTubeAdBlockingEnabled)
                    )
                }
            }

            if !viewModel.duckPlayerNativeUI.wrappedValue {
                Section(header: Text(UserText.duckPlayerFeatureName),
                        footer: Text(UserText.duckPlayerExplanation)) {
                    SettingsCellView(
                        label: UserText.duckPlayerEnableToggle,
                        accessory: .toggle(isOn: viewModel.isDuckPlayerEnabledBinding)
                    )
                    .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)
                }

                if viewModel.state.duckPlayerMode != .disabled {
                    Section {
                        SettingsCellView(
                            label: UserText.duckPlayerAlwaysOpenToggle,
                            accessory: .toggle(isOn: viewModel.isAlwaysOpenBinding)
                        )
                        .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)

                        if viewModel.state.duckPlayerOpenInNewTabEnabled {
                            SettingsCellView(
                                label: UserText.settingsOpenDuckPlayerNewTabLabel,
                                accessory: .toggle(isOn: viewModel.duckPlayerOpenInNewTabBinding)
                            )
                        }
                    }
                }
            } else {
                Section(header: Text(UserText.duckPlayerFeatureName),
                        footer: Text(UserText.duckPlayerEnableFooter)) {
                    SettingsCellView(
                        label: UserText.duckPlayerEnableToggle,
                        accessory: .toggle(isOn: viewModel.isShowDuckPlayerOnYoutubeBinding)
                    )
                    .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)
                }

                if viewModel.state.duckPlayerNativeYoutubeMode != .never {
                    Section(footer: Text(UserText.duckPlayerSearchResultsFooter)) {
                        SettingsCellView(
                            label: UserText.duckPlayerAlwaysOpenToggle,
                            accessory: .toggle(isOn: viewModel.isOpenAutomaticallyBinding)
                        )
                        .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)

                        SettingsCellView(label: UserText.duckPlayerAutoplayLabel,
                                        accessory: .toggle(isOn: viewModel.duckPlayerAutoplay))
                        .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)

                        SettingsCellView(label: UserText.duckPlayerSearchResultsLabel,
                                         accessory: .toggle(isOn: viewModel.duckPlayerNativeUISERPEnabled))
                        .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)
                    }
                }
            }
        }
        .applySettingsListModifiers(title: UserText.youTubeAdBlockingTitle,
                                    displayMode: .inline,
                                    viewModel: viewModel)
        .onAppear {
            DailyPixel.fireDailyAndCount(pixel: .duckPlayerSettingsOpen,
                                         withAdditionalParameters: viewModel.featureDiscovery.addToParams([:], forFeature: .duckPlayer))
        }
    }
}

private struct ContingencyMessageView: View {
    let buttonCallback: () -> Void

    private enum Copy {
        static let title: String = UserText.duckPlayerContingencyMessageTitle
        static let message: String = UserText.duckPlayerContingencyMessageBody
        static let buttonTitle: String = UserText.duckPlayerContingencyMessageCTA
    }
    private enum Constants {
        static let imageName: String = "WarningYoutube"
        static let imageSize: CGSize = CGSize(width: 48, height: 48)
        static let buttonCornerRadius: CGFloat = 8.0
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Image(Constants.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.imageSize.width, height: Constants.imageSize.height)
                .padding(.bottom, 8)

            Text(Copy.title)
                .daxHeadline()
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Text(Copy.message)
                .daxBodyRegular()
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .foregroundColor(Color(designSystemColor: .textPrimary))

            Button {
                buttonCallback()
            } label: {
                Text(Copy.buttonTitle)
                    .bold()
            }
            .buttonStyle(SecondaryFillButtonStyle(compact: true, fullWidth: false))
            .padding(10)
        }
    }
}
