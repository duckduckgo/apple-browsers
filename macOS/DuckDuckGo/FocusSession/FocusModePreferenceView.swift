//
//  FocusModePreferenceView.swift
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
import SwiftUI
import SwiftUIExtensions


extension Preferences {

    struct FocusModePreferenceView: View {
        @ObservedObject private var focusModeCoordinator: FocusSessionCoordinator = .shared
        @State var test = false // TODO: This needs to be replaced to a storage var



        var body: some View {
            PreferencePane("Focus Mode", spacing: 4) {

                // SECTION 1: Status Indicator
                if let status = focusModeCoordinator.status {
                    PreferencePaneSection {
                        StatusIndicatorView(status: status, isLarge: true)
                    }
                }

                // SECTION 2: Allowed Sites
                PreferencePaneSection("Allowed Sites", spacing: 4) {
                    Text("Websites you selected to be allowed while in Focus Mode")
                        .foregroundColor(.secondary)
                        .padding(.bottom, 18)

                    PreferencePaneSubSection {
                        Button("Manage Allowed Sites...") {
                            // TODO: Manage allowed sites
                        }
                    }
                }
                .padding(.bottom, 12)

                // SECTION 3: General settings
                PreferencePaneSection("General") {

                    PreferencePaneSubSection {
                        ToggleMenuItem("Play sound when focus session is over", isOn: $focusModeCoordinator.isPlaySoundEnabled)
                    }
                }
            }
        }
    }
}


