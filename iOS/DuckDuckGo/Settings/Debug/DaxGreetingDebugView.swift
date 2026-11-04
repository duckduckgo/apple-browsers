//
//  DaxGreetingDebugView.swift
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

struct DaxGreetingDebugView: View {

    let greeting: DaxGreetingDebugging
    @State private var clockOffset: TimeInterval = 0

    private var lifetimeHours: Int {
        Int(DaxGreetingService.greetingLifetime / 3600)
    }

    var body: some View {
        List {
            Section(header: Text(verbatim: "Status")) {
                Text(verbatim: "Time override: +\(Int(clockOffset / 3600)) h")
                Text(verbatim: "Greeting time: \(Date().addingTimeInterval(clockOffset).formatted(date: .abbreviated, time: .shortened))")
            }

            Section(footer: Text(verbatim: "Skipping moves the greeting clock forward by one greeting lifetime (\(lifetimeHours) h), so time-based greetings change too.")) {
                Button {
                    greeting.skipToNextGreeting()
                    clockOffset = greeting.clockOffset
                } label: {
                    Text(verbatim: "Skip to Next Greeting")
                }
            }

            Section(footer: Text(verbatim: "Clears the current greeting, the recently shown ones and the time override.")) {
                Button(role: .destructive) {
                    greeting.resetGreetingState()
                    clockOffset = greeting.clockOffset
                } label: {
                    Text(verbatim: "Reset History")
                }
            }
        }
        .navigationTitle(Text(verbatim: "NTP Greeting"))
        .onAppear { clockOffset = greeting.clockOffset }
    }
}
