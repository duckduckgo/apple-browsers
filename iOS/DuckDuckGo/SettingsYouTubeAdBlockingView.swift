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

    @State private var showDuckPlayer = false

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

                if viewModel.isYouTubeAdBlockingDisclosureHidden {
                    Section {
                        SettingsCellView(
                            label: UserText.youTubeAdBlockingToggle,
                            accessory: .toggle(isOn: viewModel.youTubeAdBlockingEnabled)
                        )
                    }
                } else {
                    Section(footer: Text(footerAttributedString)) {
                        SettingsCellView(
                            label: UserText.youTubeAdBlockingToggle,
                            accessory: .toggle(isOn: viewModel.youTubeAdBlockingEnabled)
                        )
                    }
                }
            }

            Section(footer: Text(UserText.duckPlayerEnableFooter)) {
                NavigationLink(
                    destination: SettingsDuckPlayerView().environmentObject(viewModel),
                    isActive: $showDuckPlayer
                ) {
                    SettingsCellView(label: UserText.duckPlayerFeatureName)
                }
                .listRowBackground(Color(designSystemColor: .surface))
                .disabled(viewModel.shouldDisplayDuckPlayerContingencyMessage)
            }
        }
        .applySettingsListModifiers(title: UserText.youTubeAdBlockingTitle,
                                    displayMode: .inline,
                                    viewModel: viewModel)
        .onAppear {
            viewModel.markYouTubeAdBlockingDisclosureHiddenIfExistingUser()
            DailyPixel.fireDailyAndCount(pixel: .webExtensionAdBlockingSettingsOpen,
                                         pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes)
        }
        .onFirstAppear {
            if viewModel.deepLinkTarget == .duckPlayer,
               !viewModel.shouldDisplayDuckPlayerContingencyMessage {
                DispatchQueue.main.async {
                    showDuckPlayer = true
                }
            }
        }
    }

    private static let learnMoreURL = URL(string: "ddgQuickLink://duckduckgo.com/duckduckgo-help-pages/privacy/detecting-ad-blocking-interference-anonymously")

    private var footerAttributedString: AttributedString {
        var base = AttributedString(UserText.youTubeAdBlockingToggleFooter)
        base.append(AttributedString(" "))
        var link = AttributedString(UserText.youTubeAdBlockingLearnMoreButton)
        link.foregroundColor = Color(designSystemColor: .accent)
        link.link = Self.learnMoreURL
        base.append(link)
        return base
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
