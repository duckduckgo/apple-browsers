//
//  IdleReturnNTPDebugView.swift
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
import Core
import Persistence

/// Debug view to override the idle-return NTP threshold (in seconds) for testing.
struct IdleReturnNTPDebugView: View {

    @StateObject private var storage = ObservableKeyedStorage<IdleReturnDebugOverridesKeys>(storage: UserDefaults.app)
    @State private var overrideSecondsText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private var currentOverride: Int? {
        guard let value: Int = storage.thresholdSecondsOverride, value > 0 else { return nil }
        return value
    }

    var body: some View {
        List {
            Section(header: Text(verbatim: "Status")) {
                if let seconds = currentOverride {
                    Text(verbatim: "Effective threshold: \(seconds) s (override)")
                } else {
                    Text(verbatim: "Effective threshold: config default (no override)")
                }
            }

            Section(header: Text(verbatim: "Override")) {
                TextField(text: $overrideSecondsText) {
                    Text(verbatim: "Seconds (e.g. 60)")
                }
                    .keyboardType(.numberPad)
                    .focused($isTextFieldFocused)
                Button(action: {
                    setOverrideFromText()
                    isTextFieldFocused = false
                }) {
                    Text(verbatim: "Set")
                }
                .disabled(overrideSecondsText.isEmpty)
                if currentOverride != nil {
                    Button(action: {
                        clearOverride()
                    }) {
                        Text(verbatim: "Clear override")
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: "Idle Return NTP"))
        .onAppear {
            if let s = currentOverride {
                overrideSecondsText = "\(s)"
            }
        }
    }

    private func setOverrideFromText() {
        guard let seconds = Int(overrideSecondsText), seconds > 0 else { return }
        storage.thresholdSecondsOverride = seconds
    }

    private func clearOverride() {
        storage.thresholdSecondsOverride = nil
        overrideSecondsText = ""
    }
}
