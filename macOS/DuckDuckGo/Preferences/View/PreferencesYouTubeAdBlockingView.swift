//
//  PreferencesYouTubeAdBlockingView.swift
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

import PreferencesUI_macOS
 import PixelKit
import SwiftUI
import SwiftUIExtensions

extension Preferences {

    struct YouTubeAdBlockingView: View {
        @ObservedObject var model: YouTubeAdBlockingPreferences
        @State private var hasFiredSettingsDisplayedPixel = false
        @State private var previousDuckPlayerMode: DuckPlayerMode?

        private var resolvedPreviousMode: DuckPlayerMode {
            if let previousDuckPlayerMode {
                return previousDuckPlayerMode
            }
            let current = model.duckPlayerMode
            return current != .disabled ? current : .alwaysAsk
        }

        var youTubeAdBlockingEnabledBinding: Binding<Bool> {
            .init {
                model.youTubeAdBlockingEnabled
            } set: { newValue in
                let isTurningOn = newValue && !model.youTubeAdBlockingEnabled
                let disclosureVisibleAtToggle = !model.isDisclosureHidden
                model.youTubeAdBlockingEnabled = newValue
                if isTurningOn, disclosureVisibleAtToggle {
                    model.youTubeAnalyticsEnabled = true
                }
            }
        }

        var isDuckPlayerEnabledBinding: Binding<Bool> {
            .init {
                model.duckPlayerMode != .disabled
            } set: { newValue in
                let oldMode = model.duckPlayerMode
                if newValue {
                    model.duckPlayerMode = resolvedPreviousMode
                } else {
                    if oldMode != .disabled {
                        previousDuckPlayerMode = oldMode
                    }
                    model.duckPlayerMode = .disabled
                }
                firePixelIfNeeded(oldMode: oldMode, newMode: model.duckPlayerMode)
            }
        }

        var isAlwaysOpenBinding: Binding<Bool> {
            .init {
                model.duckPlayerMode == .enabled
            } set: { newValue in
                let oldMode = model.duckPlayerMode
                if newValue {
                    model.duckPlayerMode = .enabled
                } else {
                    model.duckPlayerMode = .alwaysAsk
                }
                firePixelIfNeeded(oldMode: oldMode, newMode: model.duckPlayerMode)
            }
        }

        private func firePixelIfNeeded(oldMode: DuckPlayerMode, newMode: DuckPlayerMode) {
            guard oldMode != newMode else { return }

            switch newMode {
            case .enabled:
                PixelKit.fire(GeneralPixel.duckPlayerSettingAlwaysSettings)
            case .alwaysAsk:
                PixelKit.fire(GeneralPixel.duckPlayerSettingBackToDefault)
            case .disabled:
                PixelKit.fire(GeneralPixel.duckPlayerSettingNeverSettings)
            }
        }

        var body: some View {
            PreferencePane {

                // TITLE
                TextMenuTitle(UserText.youTubeAdBlocking)

                // YouTube Ad Blocking Section
                PreferencePaneSection {
                    TextMenuItemCaption(UserText.youTubeAdBlockingExplanation)

                    Spacer().frame(height: 4)

                    ToggleMenuItem(UserText.youTubeAdBlockingToggle, isOn: youTubeAdBlockingEnabledBinding)

                    if !model.isDisclosureHidden {
                        VStack(alignment: .leading, spacing: 1) {
                            TextMenuItemCaption(UserText.youTubeAdBlockingToggleFooter)
                            TextButton(UserText.youTubeAdBlockingLearnMoreButton) {
                                model.openLearnMoreURL()
                            }
                        }
                        .padding(.leading, 19)
                    }
                }

                // Duck Player Section
                PreferencePaneSection(UserText.duckPlayer) {
                    TextMenuItemCaption(UserText.duckPlayerYouTubeAdBlockingExplanation)

                    Spacer().frame(height: 4)

                    if model.shouldDisplayContingencyMessage {
                        ContingencyMessageView {
                            model.openLearnMoreContingencyURL()
                        }
                        .frame(width: 512)
                        .onAppear {
                            if !hasFiredSettingsDisplayedPixel {
                                PixelKit.fire(GeneralPixel.duckPlayerContingencySettingsDisplayed, doNotEnforcePrefix: true)
                                hasFiredSettingsDisplayedPixel = true
                            }
                        }
                    }

                    ToggleMenuItem(UserText.duckPlayerEnableToggle, isOn: isDuckPlayerEnabledBinding)
                        .accessibilityIdentifier("DuckPlayer.enableToggle")

                    if model.duckPlayerMode != .disabled {
                        ToggleMenuItem(UserText.duckPlayerAlwaysOpenToggle, isOn: isAlwaysOpenBinding)
                            .padding(.leading, 19)
                            .accessibilityIdentifier("DuckPlayer.alwaysOpenToggle")

                        if model.shouldDisplayAutoPlaySettings {
                            ToggleMenuItem(UserText.duckPlayerAutoplayToggle, isOn: $model.duckPlayerAutoplay)
                            .padding(.leading, 19)
                        }

                        if model.isOpenInNewTabSettingsAvailable {
                            ToggleMenuItem(UserText.duckPlayerNewTabToggle, isOn: $model.duckPlayerOpenInNewTab)
                                .padding(.leading, 19)
                                .disabled(!model.isNewTabSettingsAvailable)
                        }
                    }
                }.disabled(model.shouldDisplayContingencyMessage)
            }
            .onAppear {
                model.markDisclosureHiddenIfExistingUser()
            }
        }
    }
}

private struct ContingencyMessageView: View {
    private enum Copy {
        static let title: String = UserText.duckPlayerContingencyMessageTitle
        static let message: String = UserText.duckPlayerContingencyMessageBody
        static let buttonTitle: String = UserText.duckPlayerContingencyMessageCTA
    }

    private enum Constants {
        static let cornerRadius: CGFloat = 8
        static let imageName: String = "WarningYoutube"
        static let imageSize: CGSize = CGSize(width: 64, height: 48)
    }

    let buttonCallback: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(Constants.imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.imageSize.width, height: Constants.imageSize.height)

            VStack (alignment: .leading, spacing: 3) {
                Text(Copy.title)
                    .bold()
                Text(Copy.message)
                    .foregroundColor(Color(.blackWhite60))
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    buttonCallback()
                } label: {
                    Text(Copy.buttonTitle)
                }.padding(.top, 15)
            }
        }
        .padding()
          .background(
            ZStack {
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .stroke(Color(.blackWhite10), lineWidth: 1)
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(Color(.blackWhite1))
            }
          )
    }
}

#Preview {
    Group {
        ContingencyMessageView { }
    }.frame(height: 300)
}
