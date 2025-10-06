//
//  ControlWidgetConfigurable.swift
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

import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 18, *)
protocol ControlWidgetConfigurable: ControlWidget {
    associatedtype IntentType: AppIntent

    var kind: ControlWidgetKind { get }
    var displayName: LocalizedStringResource { get }
    var labelText: String { get }
    var imageName: String { get }
    var intent: IntentType { get }
}

@available(iOS 18, *)
extension ControlWidgetConfigurable {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: kind.rawValue) {
            ControlWidgetButton(action: intent) {
                Label(labelText, image: imageName)
            }
        }
        .displayName(displayName)
    }
}

@available(iOS 18, *)
struct AIChatControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .aiChat
    let displayName: LocalizedStringResource = "Duck.ai"
    let labelText: String = "Duck.ai"
    let imageName: String = "AI-Chat-Symbol"
    let intent = OpenAIChatIntent()

    struct OpenAIChatIntent: AppIntent {
        static var title: LocalizedStringResource = "Duck.ai"
        static var description: LocalizedStringResource = "Launches Duck.ai from the Control Center."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.openAIChat.appendingParameter(name: WidgetSourceType.sourceKey, value: WidgetSourceType.controlCenter.rawValue))
            return .result()
        }
    }
}

@available(iOS 18, *)
struct FireButtonControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .fireButton
    let displayName: LocalizedStringResource = "Fire Button"
    let labelText: String = "Fire Button"
    let imageName: String = "FireButton-Symbol"
    let intent = FireButtonIntent()

    struct FireButtonIntent: AppIntent {
        static var title: LocalizedStringResource = "Fire Button"
        static var description: LocalizedStringResource = "Instantly delete your browsing history and start a new private search in DuckDuckGo."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.fireButton)
            return .result()
        }
    }
}

@available(iOS 18, *)
struct SearchControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .search
    let displayName: LocalizedStringResource = "Search"
    let labelText: String = "Search"
    let imageName: String = "Search-Symbol"
    let intent = OpenSearchIntent()

    struct OpenSearchIntent: AppIntent {
        static var title: LocalizedStringResource = "Search"
        static var description: LocalizedStringResource = "Start a new search from the Control Center."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.newSearch)
            return .result()
        }
    }
}

@available(iOS 18, *)
struct PasswordsControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .passwords
    let displayName: LocalizedStringResource = "Passwords"
    let labelText: String = "Passwords"
    let imageName: String = "Key-Symbol"
    let intent = OpenPasswordsIntent()

    struct OpenPasswordsIntent: AppIntent {
        static var title: LocalizedStringResource = "Passwords"
        static var description: LocalizedStringResource = "Open your passwords from the Control Center."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.openPasswords)
            return .result()
        }
    }
}

@available(iOS 18, *)
struct FavoritesControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .favorites
    let displayName: LocalizedStringResource = "Favorites"
    let labelText: String = "Favorites"
    let imageName: String = "Favorite-Symbol"
    let intent = OpenFavoritesIntent()

    struct OpenFavoritesIntent: AppIntent {
        static var title: LocalizedStringResource = "Favorites"
        static var description: LocalizedStringResource = "Open your favorites from the Control Center."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.favorites)
            return .result()
        }
    }
}

@available(iOS 18, *)
struct VoiceSearchControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .voiceSearch
    let displayName: LocalizedStringResource = "Voice Search"
    let labelText: String = "Voice Search"
    let imageName: String = "VoiceSearch-Symbol"
    let intent = OpenVoiceSearchIntent()

    struct OpenVoiceSearchIntent: AppIntent {
        static var title: LocalizedStringResource = "Favorites"
        static var description: LocalizedStringResource = "Start a new voice search from the Control Center."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.voiceSearch)
            return .result()
        }
    }
}

@available(iOS 18, *)
struct EmailProtectionControlWidget: ControlWidgetConfigurable {
    let kind: ControlWidgetKind = .email
    let displayName: LocalizedStringResource = "Duck Address"
    let labelText: String = "Duck Address"
    let imageName: String = "Email-New-Symbol"
    let intent = EmailProtectionIntent()

    struct EmailProtectionIntent: AppIntent {
        static var title: LocalizedStringResource = "Duck Address"
        static var description: LocalizedStringResource = "Instantly generate a new private Duck Address from the Control Center."
        static var openAppWhenRun: Bool = true

        func perform() async throws -> some IntentResult & OpensIntent {
            await EnvironmentValues().openURL(DeepLinks.newEmail)
            return .result()
        }
    }
}
