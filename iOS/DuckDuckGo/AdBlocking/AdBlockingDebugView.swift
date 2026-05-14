//
//  AdBlockingDebugView.swift
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

struct AdBlockingDebugView: View {

    @AppStorage(AdBlockingAvailability.remotelyDisabledOverrideKey) private var isRemotelyDisabled = false

    var body: some View {
        List {
            Section {
                Toggle("Remotely Disabled", isOn: $isRemotelyDisabled)
            } header: {
                Text("Remote Disable Override")
            } footer: {
                Text("Simulates the YouTube Ad Block feature being remotely disabled. Placeholder — replace once the real derivation lands.")
            }
        }
        .navigationTitle("Ad Blocking")
    }
}
