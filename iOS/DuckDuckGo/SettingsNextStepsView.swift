//
//  SettingsNextStepsView.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import UIKit
import DesignResourcesKit
import DesignResourcesKitIcons

struct SettingsNextStepsView: View {

    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        if viewModel.shouldShowNextStepsSection {
            Section(header: header) {
                // Add App to Your Dock — dismisses one day after the user taps it.
                if viewModel.shouldShowAddToDockNextStep {
                    SettingsCellView(label: UserText.settingsAddToDock,
                                     image: Image(uiImage: DesignSystemImages.Color.Size24.addToDock),
                                     action: {
                                         viewModel.recordAddToDockNextStepTapped()
                                         viewModel.presentLegacyView(.addToDock)
                                     },
                                     isButton: true)
                }

                // Add Widget to Home Screen — dismisses one day after the user taps it.
                if viewModel.shouldShowAddWidgetNextStep {
                    NavigationLink(destination: WidgetEducationView().onAppear {
                        viewModel.recordAddWidgetNextStepTapped()
                    }) {
                        SettingsCellView(label: UserText.settingsAddWidget,
                                         image: Image(uiImage: DesignSystemImages.Color.Size24.addWidget))
                    }
                }

                // Set Your Address Bar Position — dismisses once the position is changed from default.
                if viewModel.shouldShowSetAddressBarPositionNextStep {
                    NavigationLink(destination: SettingsAppearanceView().environmentObject(viewModel)
                        .onDisappear { viewModel.refreshNextStepsVisibility(animated: true) }) {
                        SettingsCellView(label: UserText.setYourAddressBarPosition,
                                         image: Image(uiImage: DesignSystemImages.Color.Size24.addressBarBottom))
                    }
                }

                // Enable Voice Search — dismisses once voice search is enabled.
                if viewModel.shouldShowEnableVoiceSearchNextStep {
                    NavigationLink(destination: SettingsAccessibilityView().environmentObject(viewModel)
                        .onDisappear { viewModel.refreshNextStepsVisibility(animated: true) }) {
                        SettingsCellView(label: UserText.enableVoiceSearch,
                                         image: Image(uiImage: AppRebrand.isAppRebranded()
                                                      ? DesignSystemImages.Color.Size24.microphoneAdd
                                                      : DesignSystemImages.Color.Size24.microphone))
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            Text(UserText.nextSteps)
            Spacer()
            if viewModel.shouldShowNextStepsHideButton {
                Button {
                    viewModel.hideNextStepsSection()
                } label: {
                    Text(UserText.nextStepsHide)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .padding(.leading, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .textCase(nil)
            }
        }
    }

}
