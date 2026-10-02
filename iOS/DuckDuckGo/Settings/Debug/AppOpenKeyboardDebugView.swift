//
//  AppOpenKeyboardDebugView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

enum AppOpenKeyboardDebugStorageKeys: String, StorageKeyDescribing {
    case thresholdSecondsOverride = "app-open-keyboard-threshold-seconds-debug-override"
}

struct AppOpenKeyboardDebugKeys: StoringKeys {
    let thresholdSecondsOverride = StorageKey<Int>(AppOpenKeyboardDebugStorageKeys.thresholdSecondsOverride)
}

struct AppOpenKeyboardDebugSettings {
    private let storage: any KeyedStoring<AppOpenKeyboardDebugKeys>

    init(storage: any KeyedStoring<AppOpenKeyboardDebugKeys> = UserDefaults.app.keyedStoring()) {
        self.storage = storage
    }

    var thresholdSeconds: TimeInterval {
#if DEBUG
        if let seconds: Int = storage.thresholdSecondsOverride, seconds > 0 {
            return TimeInterval(seconds)
        }
#endif
        return NewTabPageKeyboardPolicy.appOpenBackgroundThreshold
    }
}

#if DEBUG
struct AppOpenKeyboardDebugView: View {
    @StateObject private var storage = ObservableKeyedStorage<AppOpenKeyboardDebugKeys>(storage: UserDefaults.app)

    var body: some View {
        List {
            Section {
                Picker(selection: $storage.thresholdSecondsOverride) {
                    Text(verbatim: "5 seconds").tag(5 as Int?)
                    Text(verbatim: "10 seconds").tag(10 as Int?)
                    Text(verbatim: "20 seconds (default)").tag(nil as Int?)
                } label: {
                    Text(verbatim: "Background threshold")
                }
            } footer: {
                Text(verbatim: "The keyboard can open after more than this time in the background. This does not change the inactivity setting.")
            }
        }
        .navigationTitle(Text(verbatim: "App Open Keyboard"))
    }
}
#endif
