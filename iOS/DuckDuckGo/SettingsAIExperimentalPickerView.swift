//
//  AIExperimentalPickerView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

struct SettingsAIExperimentalPickerView: View {
    // isDuckAISelected maps to AI Chat enabled state
    @Binding var isDuckAISelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Search Only (Default)
            Button {
                isDuckAISelected = false
            } label: {
                VStack(spacing: 8) {
                    Image(isDuckAISelected ? "SearchExperimentalOff" : "SearchExperimentalOn")
                        .resizable()
                        .scaledToFit()
                    Text("Search Only\n(Default)")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    Image(isDuckAISelected ? "AIExperimentalCheckOff" : "AIExperimentalCheckOn")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            // Search & Duck.ai (Experimental)
            Button {
                isDuckAISelected = true
            } label: {
                VStack(spacing: 8) {
                    Image(isDuckAISelected ? "AIExperimentalOn" : "AIExperimentalOff")
                        .resizable()
                        .scaledToFit()
                    Text("Search & Duck.ai\n(Experimental)")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    Image(isDuckAISelected ? "AIExperimentalCheckOn" : "AIExperimentalCheckOff")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }
}
