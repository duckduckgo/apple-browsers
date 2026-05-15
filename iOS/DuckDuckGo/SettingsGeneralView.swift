//
//  SettingsGeneralView.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

enum AfterInactivityOption: String, CaseIterable, CustomStringConvertible {
    case newTab
    case lastUsedTab

    var description: String {
        switch self {
        case .newTab: return UserText.settingsAfterInactivityOptionNewTab
        case .lastUsedTab: return UserText.settingsAfterInactivityOptionLastUsedTab
        }
    }
}

enum AfterInactivityIdleInterval: Int, CaseIterable, CustomStringConvertible {
    case none = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600
    case twelveHours = 43200

    static let `default`: AfterInactivityIdleInterval = .thirtyMinutes

    var seconds: Int { rawValue }

    var description: String {
        switch self {
        case .none: return UserText.settingsAfterInactivityIdleIntervalNone
        case .oneMinute: return UserText.settingsAfterInactivityIdleIntervalMinuteSingular
        case .fiveMinutes: return String(format: UserText.settingsAfterInactivityIdleIntervalMinutesFormat, 5)
        case .tenMinutes: return String(format: UserText.settingsAfterInactivityIdleIntervalMinutesFormat, 10)
        case .thirtyMinutes: return String(format: UserText.settingsAfterInactivityIdleIntervalMinutesFormat, 30)
        case .oneHour: return UserText.settingsAfterInactivityIdleIntervalHourSingular
        case .twelveHours: return String(format: UserText.settingsAfterInactivityIdleIntervalHoursFormat, 12)
        }
    }
}

struct SettingsGeneralView: View {

    @EnvironmentObject var viewModel: SettingsViewModel
    @State var shouldShowNoMicrophonePermissionAlert = false

    var body: some View {
        List {
            // Application Lock
            Section(footer: Text(UserText.settingsAutoLockDescription)) {
                SettingsCellView(label: UserText.settingsAutolock,
                                 accessory: .toggle(isOn: viewModel.applicationLockBinding))

            }
            // NTP after idle time
            if viewModel.shouldShowNTPAfterIdleSetting {
                Section(footer: Text(viewModel.afterInactivityFooterText)) {
                    SettingsPickerCellView(label: UserText.settingsAfterInactivityLabel,
                                           options: AfterInactivityOption.allCases,
                                           selectedOption: viewModel.afterInactivityOptionBinding)

                    if viewModel.afterInactivityOption == .newTab {
                        SettingsPickerCellView(label: UserText.settingsAfterInactivityIntervalLabel,
                                               options: AfterInactivityIdleInterval.allCases,
                                               selectedOption: viewModel.afterInactivityIdleIntervalBinding)
                    }
                }
            }

            Section(header: Text(showChatSuggestions ? UserText.privateSearchAndChat : UserText.privateSearch),
                    footer: Text(showChatSuggestions ? UserText.settingsAutocompleteWithChatSubtitle : UserText.settingsAutocompleteSubtitle)) {
                // Autocomplete Suggestions
                SettingsCellView(label: UserText.settingsAutocompleteLabel,
                                 accessory: .toggle(isOn: viewModel.autocompleteGeneralBinding))

                if showChatSuggestions {
                    SettingsCellView(label: UserText.settingsChatSuggestionsTitle,
                                     accessory: .toggle(isOn: viewModel.isChatSuggestionsEnabled))
                }
            }

            if viewModel.shouldShowRecentlyVisitedSites {
                Section(footer: Text(UserText.settingsAutocompleteRecentlyVisitedSubtitle)) {
                    SettingsCellView(label: UserText.settingsAutocompleteRecentlyVisitedLabel,
                                     accessory: .toggle(isOn: viewModel.autocompleteRecentlyVisitedSitesBinding))
                }
            }

            if viewModel.state.speechRecognitionAvailable {
                Section(footer: Text(UserText.voiceSearchFooter)) {
                    // Private Voice Search
                    SettingsCellView(label: UserText.settingsVoiceSearch,
                                     accessory: .toggle(isOn: viewModel.voiceSearchEnabledBinding))
                }
                .alert(isPresented: $shouldShowNoMicrophonePermissionAlert) {
                    Alert(title: Text(UserText.noVoicePermissionAlertTitle),
                          message: Text(UserText.noVoicePermissionAlertMessage),
                          dismissButton: .default(Text(UserText.noVoicePermissionAlertOKbutton),
                                                  action: {
                        viewModel.shouldShowNoMicrophonePermissionAlert = false
                    })
                    )
                }
                .onChange(of: viewModel.shouldShowNoMicrophonePermissionAlert) { value in
                    shouldShowNoMicrophonePermissionAlert = value
                }
            }

            Section(header: Text(UserText.settingsCustomizeSection),
                    footer: Text(UserText.settingsAssociatedAppsDescription)) {
                // Keyboard
                SettingsCellView(label: UserText.settingsKeyboard,
                                 action: { viewModel.presentLegacyView(.keyboard) },
                                 disclosureIndicator: true,
                                 isButton: true)

                // Long-Press Previews
                SettingsCellView(label: UserText.settingsPreviews,
                                 accessory: .toggle(isOn: viewModel.longPressBinding))

                // Open Links in Associated Apps
                SettingsCellView(label: UserText.settingsAssociatedApps,
                                 accessory: .toggle(isOn: viewModel.universalLinksBinding))
            }

            // Media
            Section(header: Text(UserText.settingsMediaSection)) {
                NavigationLink(destination: SettingsAutoplayView().environmentObject(viewModel)) {
                    SettingsCellView(label: UserText.settingsAutoplayLabel,
                                     accessory: .rightDetail(viewModel.state.autoplayBlockingMode.description))
                }
            }

        }
        .applySettingsListModifiers(title: UserText.general,
                                    displayMode: .inline,
                                    viewModel: viewModel)
        .onFirstAppear {
            Pixel.fire(pixel: .settingsGeneralOpen)
        }
    }

    private var showChatSuggestions: Bool {
        viewModel.featureFlagger.isFeatureOn(.aiChatSuggestions)
            && viewModel.isAIChatEnabled
            && viewModel.aiChatSettings.isAIChatSearchInputUserSettingsEnabled
    }
}
