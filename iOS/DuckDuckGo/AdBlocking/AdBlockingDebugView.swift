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

    @AppStorage(AdBlockingAvailability.remotelyDisabledOverrideKey) private var isRemotelyDisabled = false
    @State private var youTubeAnalyticsEnabled: TriState = .unset
    @State private var shouldHideDisclosure: TriState = .unset
    @State private var unavailableNoticeShown: Bool?

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.storage = keyValueStore.throwingKeyedStoring()
    }

    var body: some View {
        List {
            Section {
                triStatePicker(title: "youTubeAnalyticsEnabled",
                               selection: $youTubeAnalyticsEnabled,
                               key: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
                triStatePicker(title: "shouldHideDisclosure",
                               selection: $shouldHideDisclosure,
                               key: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
            } header: {
                Text(verbatim: "Flags")
            }

            Section {
                Toggle("Remotely Disabled", isOn: $isRemotelyDisabled)
                resettableStatusRow(title: "Unavailable notice shown",
                                    value: unavailableNoticeShown,
                                    key: \YouTubeAdBlockingKeys.youTubeAdBlockUnavailableNoticeShown)
            } header: {
                Text("Remote Disable Override")
            } footer: {
                Text("Simulates the YouTube Ad Block feature being remotely disabled. Placeholder — replace once the real derivation lands.")
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

    private func triStatePicker(title: String,
                                selection: Binding<TriState>,
                                key: KeyPath<YouTubeAdBlockingKeys, StorageKey<Bool>>) -> some View {
        Picker(title, selection: Binding(
            get: { selection.wrappedValue },
            set: { newValue in
                selection.wrappedValue = newValue
                apply(newValue, to: key)
            }
        )) {
            ForEach(TriState.allCases) { state in
                Text(state.label).tag(state)
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func resettableStatusRow(title: String,
                                     value: Bool?,
                                     key: KeyPath<YouTubeAdBlockingKeys, StorageKey<Bool>>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(string(for: value))
                .foregroundColor(.secondary)
            Button("Reset") {
                try? storage.removeValue(for: key)
                refresh()
            }
            .buttonStyle(.borderless)
        }
    }

    private func apply(_ state: TriState, to key: KeyPath<YouTubeAdBlockingKeys, StorageKey<Bool>>) {
        switch state.value {
        case nil:
            try? storage.removeValue(for: key)
        case let bool?:
            try? storage.set(bool, for: key)
        }
        refresh()
    }

    private func string(for value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "nil"
    }

    private func refresh() {
        youTubeAnalyticsEnabled = TriState.from(try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled))
        shouldHideDisclosure = TriState.from(try? storage.value(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure))
        unavailableNoticeShown = try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockUnavailableNoticeShown)
    }
}

private extension AdBlockingDebugView {
    enum TriState: Int, CaseIterable, Identifiable {
        case unset
        case on
        case off

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .unset: return "nil"
            case .on: return "true"
            case .off: return "false"
            }
        }
        var value: Bool? {
            switch self {
            case .unset: return nil
            case .on: return true
            case .off: return false
            }
        }
        static func from(_ value: Bool?) -> TriState {
            switch value {
            case nil: return .unset
            case true?: return .on
            case false?: return .off
            }
        }
    }
}
