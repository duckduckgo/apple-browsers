//
//  AIChatContextualSidebarKeyboardStyle.swift
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

import Foundation

/// How the iPad Duck.ai sidebar makes room for its suggestions while a software keyboard covers it.
/// Picked in the AI Chat debug screen while the approaches are being compared.
enum AIChatContextualSidebarKeyboardStyle: String, CaseIterable {
    /// Leaves the sidebar's layout as it is.
    case standard
    /// In landscape, folds the suggestions into one row and tightens the input and header.
    case compactInLandscape
    /// Lifts the suggestions out of the sidebar onto the page beside it, in either orientation.
    case floatingSuggestions

    static let `default`: AIChatContextualSidebarKeyboardStyle = .floatingSuggestions

    var title: String {
        switch self {
        case .standard: return "Standard"
        case .compactInLandscape: return "Compact in landscape"
        case .floatingSuggestions: return "Floating suggestions"
        }
    }

    var summary: String {
        switch self {
        case .standard: return "The sidebar keeps its layout; the suggestions list scrolls."
        case .compactInLandscape: return "Suggestions fold into a row; the page chip and header tighten."
        case .floatingSuggestions: return "Suggestions slide out beside the sidebar, over the page."
        }
    }

    /// The adaptation to apply, given whether a keyboard covers the sidebar and the window's orientation.
    func adaptation(isKeyboardCovering: Bool, isLandscape: Bool) -> AIChatContextualSidebarKeyboardAdaptation {
        guard isKeyboardCovering else { return .none }
        switch self {
        case .standard: return .none
        case .compactInLandscape: return isLandscape ? .compact : .none
        case .floatingSuggestions: return .floatingSuggestions
        }
    }
}

enum AIChatContextualSidebarKeyboardAdaptation {
    case none
    case compact
    case floatingSuggestions
}

protocol AIChatContextualSidebarKeyboardStyleStoring: AnyObject {
    var keyboardStyle: AIChatContextualSidebarKeyboardStyle { get set }
}

final class AIChatContextualSidebarKeyboardStyleSetting: AIChatContextualSidebarKeyboardStyleStoring {

    private static let key = "aichat.debug.contextualSidebarKeyboardStyle"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var keyboardStyle: AIChatContextualSidebarKeyboardStyle {
        get {
            userDefaults.string(forKey: Self.key).flatMap(AIChatContextualSidebarKeyboardStyle.init(rawValue:)) ?? .default
        }
        set {
            userDefaults.set(newValue.rawValue, forKey: Self.key)
        }
    }
}
