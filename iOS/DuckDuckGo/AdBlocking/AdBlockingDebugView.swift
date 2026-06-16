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
    private let appGroupDefaults: UserDefaults?
    private let featureFlagger = AppDependencyProvider.shared.featureFlagger
    private let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    @State private var youTubeAdBlockingEnabled: TriState = .unset
    @State private var duckPlayerMode: DuckPlayerModeOption = .unset
    @State private var duckPlayerNativeYoutubeMode: DuckPlayerNativeYoutubeModeOption = .unset
    @State private var youTubeAnalyticsEnabled: TriState = .unset
    @State private var shouldHideDisclosure: TriState = .unset
    @State private var unavailableNoticeShown: Bool?

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.storage = keyValueStore.throwingKeyedStoring()
        self.appGroupDefaults = UserDefaults(suiteName: "group.com.duckduckgo.app")
    }

    private var rolloutDefaultsActive: Bool {
        featureFlagger.isFeatureOn(.adBlockingExtensionEnabledByDefault)
    }

    var body: some View {
        List {
            Section {
                triStatePicker(title: "youTubeAdBlockingEnabled",
                               selection: $youTubeAdBlockingEnabled,
                               key: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled,
                               defaultLabel: rolloutDefaultsActive ? "true" : "false")
                if isPhone {
                    duckPlayerNativeYoutubeModePicker
                } else {
                    duckPlayerModePicker
                }
            } header: {
                Text(verbatim: "Settings")
            } footer: {
                Text(verbatim: "Raw stored values. Pick `nil` to clear so the rollout-aware defaults apply. Showing the picker for the active UI on this device.")
            }

            Section {
                triStatePicker(title: "youTubeAnalyticsEnabled",
                               selection: $youTubeAnalyticsEnabled,
                               key: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
                triStatePicker(title: "shouldHideDisclosure",
                               selection: $shouldHideDisclosure,
                               key: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
                resettableStatusRow(title: "Unavailable notice shown",
                                    value: unavailableNoticeShown,
                                    key: \YouTubeAdBlockingKeys.youTubeAdBlockUnavailableNoticeShown)
            } header: {
                Text(verbatim: "Flags")
            } footer: {
                Text(verbatim: "Override the `adBlockingExtension` feature flag from the Feature Flags debug screen to simulate the YouTube Ad Blocking remote-disable contingency state.")
            }

            Section {
                Button {
                    clearDetectionPixelDailyStamps()
                } label: {
                    Text(verbatim: "Clear today's detection-pixel stamps")
                }
            } header: {
                Text(verbatim: "Detection pixels")
            } footer: {
                Text(verbatim: "Clears today's last-fired stamps for the five m_web_extension_adblocking_detected_*_daily pixels so they can fire again today.")
            }
        }
        .navigationTitle(Text(verbatim: "Ad Blocking"))
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
                                key: KeyPath<YouTubeAdBlockingKeys, StorageKey<Bool>>,
                                defaultLabel: String? = nil) -> some View {
        Picker(selection: Binding(
            get: { selection.wrappedValue },
            set: { newValue in
                selection.wrappedValue = newValue
                apply(newValue, to: key)
            }
        )) {
            ForEach(TriState.allCases) { state in
                Text(state.label).tag(state)
            }
        } label: {
            pickerLabel(title: title,
                        isUnset: selection.wrappedValue == .unset,
                        defaultLabel: defaultLabel)
        }
        .pickerStyle(.menu)
    }

    private var duckPlayerModePicker: some View {
        Picker(selection: Binding(
            get: { duckPlayerMode },
            set: { newValue in
                duckPlayerMode = newValue
                applyDuckPlayerMode(newValue)
            }
        )) {
            ForEach(DuckPlayerModeOption.allCases) { option in
                Text(option.label).tag(option)
            }
        } label: {
            pickerLabel(title: "duckPlayerMode",
                        isUnset: duckPlayerMode == .unset,
                        defaultLabel: "alwaysAsk")
        }
        .pickerStyle(.menu)
    }

    private func applyDuckPlayerMode(_ option: DuckPlayerModeOption) {
        if let value = option.stringValue {
            appGroupDefaults?.set(value, forKey: "com.duckduckgo.ios.duckPlayerMode")
        } else {
            appGroupDefaults?.removeObject(forKey: "com.duckduckgo.ios.duckPlayerMode")
        }
        refresh()
    }

    private var duckPlayerNativeYoutubeModePicker: some View {
        Picker(selection: Binding(
            get: { duckPlayerNativeYoutubeMode },
            set: { newValue in
                duckPlayerNativeYoutubeMode = newValue
                applyDuckPlayerNativeYoutubeMode(newValue)
            }
        )) {
            ForEach(DuckPlayerNativeYoutubeModeOption.allCases) { option in
                Text(option.label).tag(option)
            }
        } label: {
            pickerLabel(title: "duckPlayerNativeYoutubeMode",
                        isUnset: duckPlayerNativeYoutubeMode == .unset,
                        defaultLabel: "ask")
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func pickerLabel(title: String, isUnset: Bool, defaultLabel: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if isUnset, let defaultLabel {
                Text(verbatim: "Default: \(defaultLabel)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func applyDuckPlayerNativeYoutubeMode(_ option: DuckPlayerNativeYoutubeModeOption) {
        if let value = option.stringValue {
            appGroupDefaults?.set(value, forKey: "com.duckduckgo.ios.duckPlayerNativeYoutubeMode")
        } else {
            appGroupDefaults?.removeObject(forKey: "com.duckduckgo.ios.duckPlayerNativeYoutubeMode")
        }
        refresh()
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
            Button {
                try? storage.removeValue(for: key)
                refresh()
            } label: {
                Text(verbatim: "Reset")
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
        youTubeAdBlockingEnabled = TriState.from(try? storage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled))
        duckPlayerMode = DuckPlayerModeOption.from(appGroupDefaults?.string(forKey: "com.duckduckgo.ios.duckPlayerMode"))
        duckPlayerNativeYoutubeMode = DuckPlayerNativeYoutubeModeOption.from(appGroupDefaults?.string(forKey: "com.duckduckgo.ios.duckPlayerNativeYoutubeMode"))
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

    enum DuckPlayerModeOption: Hashable, CaseIterable, Identifiable {
        case unset
        case enabled
        case alwaysAsk
        case disabled

        var id: String { label }
        var label: String {
            switch self {
            case .unset: return "nil"
            case .enabled: return "enabled"
            case .alwaysAsk: return "alwaysAsk"
            case .disabled: return "disabled"
            }
        }
        var stringValue: String? {
            switch self {
            case .unset: return nil
            case .enabled: return "enabled"
            case .alwaysAsk: return "alwaysAsk"
            case .disabled: return "disabled"
            }
        }
        static func from(_ value: String?) -> DuckPlayerModeOption {
            switch value {
            case "enabled": return .enabled
            case "alwaysAsk": return .alwaysAsk
            case "disabled": return .disabled
            default: return .unset
            }
        }
    }

    enum DuckPlayerNativeYoutubeModeOption: Hashable, CaseIterable, Identifiable {
        case unset
        case auto
        case ask
        case never

        var id: String { label }
        var label: String {
            switch self {
            case .unset: return "nil"
            case .auto: return "auto"
            case .ask: return "ask"
            case .never: return "never"
            }
        }
        var stringValue: String? {
            switch self {
            case .unset: return nil
            case .auto: return "auto"
            case .ask: return "ask"
            case .never: return "never"
            }
        }
        static func from(_ value: String?) -> DuckPlayerNativeYoutubeModeOption {
            switch value {
            case "auto": return .auto
            case "ask": return .ask
            case "never": return .never
            default: return .unset
            }
        }
    }
}
