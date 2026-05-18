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

import Core
import Persistence
import SwiftUI

struct AdBlockingDebugView: View {

    private let storage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys>

    @State private var youTubeAnalyticsEnabled: Bool?
    @State private var shouldHideDisclosure: Bool?

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.storage = keyValueStore.throwingKeyedStoring()
    }

    var body: some View {
        List {
            Section {
                row(title: "youTubeAnalyticsEnabled", value: youTubeAnalyticsEnabled)
                Button("Reset (delete key)") {
                    try? storage.removeValue(for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
                    refresh()
                }
            } header: {
                Text(verbatim: "Analytics opt-in")
            }

            Section {
                row(title: "shouldHideDisclosure", value: shouldHideDisclosure)
                Button("Set to `true`") {
                    try? storage.set(true, for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
                    refresh()
                }
                Button("Set to `false`") {
                    try? storage.set(false, for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
                    refresh()
                }
                Button("Reset (delete key)") {
                    try? storage.removeValue(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
                    refresh()
                }
            } header: {
                Text(verbatim: "Disclosure visibility")
            }

            Section {
                Button("Clear today's detection-pixel stamps") {
                    clearDetectionPixelDailyStamps()
                }
            } header: {
                Text(verbatim: "Detection pixels")
            } footer: {
                Text(verbatim: "Clears today's last-fired stamps for the five m_web_extension_adblocking_detected_*_daily pixels so they can fire again today.")
            }
        }
        .navigationTitle("Ad Blocking")
        .onAppear(perform: refresh)
    }

    private func clearDetectionPixelDailyStamps() {
        let pixels: [Pixel.Event] = [
            .webExtensionAdBlockingDetectedAdBlockerDaily,
            .webExtensionAdBlockingDetectedPlayabilityErrorDaily,
            .webExtensionAdBlockingDetectedVideoAdDaily,
            .webExtensionAdBlockingDetectedStaticAdDaily,
            .webExtensionAdBlockingDetectedBufferingDaily
        ]
        for pixel in pixels {
            try? DailyPixel.storage.set(nil, forKey: pixel.name)
        }
    }

    @ViewBuilder
    private func row(title: String, value: Bool?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(string(for: value))
                .foregroundColor(.secondary)
        }
    }

    private func string(for value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "nil"
    }

    private func refresh() {
        youTubeAnalyticsEnabled = try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
        shouldHideDisclosure = try? storage.value(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
    }
}
