//
//  AutoClearSettingsViewModel.swift
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

import Foundation
import SwiftUI
import Core
import AIChat

@MainActor
final class AutoClearSettingsViewModel: ObservableObject {
    
    // MARK: - Dependencies
    
    private let appSettings: AppSettings
    private let aiChatSettings: AIChatSettingsProvider
    
    // MARK: - Published State
    
    @Published private(set) var autoClearEnabled: Bool = false
    @Published private(set) var clearTabs: Bool = false
    @Published private(set) var clearCookies: Bool = false
    @Published private(set) var clearDuckAIChats: Bool = false
    @Published private(set) var selectedTiming: AutoClearSettingsModel.Timing = .termination
    
    // MARK: - Computed Properties
    
    var showDuckAIChatsToggle: Bool {
        aiChatSettings.isAIChatEnabled
    }
    
    // MARK: - Bindings
    
    var autoClearEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.autoClearEnabled },
            set: { newValue in
                self.autoClearEnabled = newValue
                if newValue {
                    Pixel.fire(pixel: .settingsAutomaticallyClearDataOn)
                    // Enable with default values if turning on
                    self.clearTabs = true
                    self.clearCookies = true
                    self.clearDuckAIChats = false
                    self.selectedTiming = .termination
                } else {
                    Pixel.fire(pixel: .settingsAutomaticallyClearDataOff)
                }
                self.persistSettings()
            }
        )
    }
    
    var clearTabsBinding: Binding<Bool> {
        Binding(
            get: { self.clearTabs },
            set: { newValue in
                self.clearTabs = newValue
                self.persistSettings()
            }
        )
    }
    
    var clearCookiesBinding: Binding<Bool> {
        Binding(
            get: { self.clearCookies },
            set: { newValue in
                self.clearCookies = newValue
                self.persistSettings()
            }
        )
    }
    
    var clearDuckAIChatsBinding: Binding<Bool> {
        Binding(
            get: { self.clearDuckAIChats },
            set: { newValue in
                self.clearDuckAIChats = newValue
                self.persistSettings()
            }
        )
    }
    
    var selectedTimingBinding: Binding<AutoClearSettingsModel.Timing> {
        Binding(
            get: { self.selectedTiming },
            set: { newValue in
                self.selectedTiming = newValue
                self.persistSettings()
            }
        )
    }
    
    // MARK: - Timing Options
    
    var timingOptions: [AutoClearSettingsModel.Timing] {
        [.termination, .delay5min, .delay15min, .delay30min, .delay60min]
    }
    
    func timingLabel(for timing: AutoClearSettingsModel.Timing) -> String {
        switch timing {
        case .termination:
            return UserText.settingsAutoClearTimingAppExitOnly
        case .delay5min:
            return UserText.settingsAutoClearTimingAppExitInactive5Min
        case .delay15min:
            return UserText.settingsAutoClearTimingAppExitInactive15Min
        case .delay30min:
            return UserText.settingsAutoClearTimingAppExitInactive30Min
        case .delay60min:
            return UserText.settingsAutoClearTimingAppExitInactive1Hour
        }
    }
    
    // MARK: - Initialization
    
    init(appSettings: AppSettings,
         aiChatSettings: AIChatSettingsProvider) {
        self.appSettings = appSettings
        self.aiChatSettings = aiChatSettings
        loadSettings()
    }
    
    // MARK: - Private Methods
    
    private func loadSettings() {
        let action = appSettings.autoClearAction
        autoClearEnabled = !action.isEmpty
        
        if autoClearEnabled {
            clearTabs = action.contains(.tabs)
            clearCookies = action.contains(.data)
            clearDuckAIChats = action.contains(.aiChats)
            selectedTiming = appSettings.autoClearTiming
        }
    }
    
    private func persistSettings() {
        if autoClearEnabled {
            var options = FireOptions()
            if clearTabs {
                options.insert(.tabs)
            }
            if clearCookies {
                options.insert(.data)
            }
            if clearDuckAIChats && showDuckAIChatsToggle {
                options.insert(.aiChats)
            }
            
            // If no options are selected, disable auto clear
            if options.isEmpty {
                appSettings.autoClearAction = FireOptions()
                autoClearEnabled = false
                Pixel.fire(pixel: .settingsAutomaticallyClearDataOff)
            } else {
                appSettings.autoClearAction = options
            }
            appSettings.autoClearTiming = selectedTiming
        } else {
            appSettings.autoClearAction = FireOptions()
            appSettings.autoClearTiming = .termination
        }
    }
}
