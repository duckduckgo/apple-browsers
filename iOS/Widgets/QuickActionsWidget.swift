//
//  QuickActionsWidget.swift
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
import WidgetKit
import AppIntents

@available(iOS 17.0, *)
struct QuickActionsProvider: AppIntentTimelineProvider {
    typealias Entry = QuickActionsEntry
    typealias Intent = ConfigurationIntent

    func placeholder(in context: Context) -> QuickActionsEntry {
        QuickActionsEntry(date: Date(), configuration: ConfigurationIntent())
    }

    func snapshot(for configuration: ConfigurationIntent, in context: Context) async -> QuickActionsEntry {
        QuickActionsEntry(date: Date(), configuration: configuration)
    }

    func timeline(for configuration: ConfigurationIntent, in context: Context) async -> Timeline<QuickActionsEntry> {
        let entry = QuickActionsEntry(date: Date(), configuration: configuration)
        return Timeline(entries: [entry], policy: .never)
    }
}

@available(iOS 17.0, *)
struct QuickActionsEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
}

@available(iOS 17.0, *)
struct ConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Shortcuts"
    static var description = IntentDescription("Choose your shortcuts")

    @Parameter(title: "Left Shortcut", default: .duckAI)
    var leftShortcut: ShortcutOption

    @Parameter(title: "Right Shortcut", default: .passwords)
    var rightShortcut: ShortcutOption

    init(leftShortcut: ShortcutOption, rightShortcut: ShortcutOption) {
        self.leftShortcut = leftShortcut
        self.rightShortcut = rightShortcut
    }

    init() { }
}

@available(iOS 17.0, *)
enum ShortcutOption: String, CaseIterable, Identifiable, AppEnum {
    case passwords
    case duckAI
    case voiceSearch
    case favorites
    case emailProtection

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shortcut Option"
    static var caseDisplayRepresentations: [ShortcutOption : DisplayRepresentation] = [
        .passwords: "Passwords",
        .duckAI: "Duck.ai",
        .voiceSearch: "Voice Search",
        .favorites: "Favorites",
        .emailProtection: "Email Protection"
    ]

    var id: String { self.rawValue }

    var icon: Image {
        switch self {
        case .passwords: return Image(.key24)
        case .duckAI: return Image(.aiChat24)
        case .voiceSearch: return Image(.microphone24)
        case .favorites: return Image(.favorite24)
        case .emailProtection: return Image(.email24)
        }
    }

    var destination: URL {
        switch self {
        case .passwords: return DeepLinks.openPasswords
        case .duckAI: return DeepLinks.openAIChat.appendingParameter(name: WidgetSourceType.sourceKey, value: WidgetSourceType.quickActions.rawValue)
        case .voiceSearch: return DeepLinks.voiceSearch
        case .favorites: return DeepLinks.favorites
        case .emailProtection: return DeepLinks.newEmail
        }
    }
}

@available(iOS 17.0, *)
struct QuickActionsWidget: Widget {
    let kind: String = "QuickActionsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: QuickActionsProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
        }
        .configurationDisplayName(UserText.quickActionsWidgetGalleryDisplayName)
        .description(UserText.quickActionsWidgetGalleryDescription)
        .supportedFamilies([.systemSmall])
    }
}

@available(iOS 17.0, *)
struct QuickActionsWidgetView: View {
    var entry: QuickActionsEntry

    var body: some View {
        VStack(spacing: 12) {
            Link(destination: DeepLinks.newSearch) {
                SearchBoxView()
            }
            HStack(spacing: 12) {
                Link(destination: entry.configuration.leftShortcut.destination) {
                    IconView(image: entry.configuration.leftShortcut.icon)
                }
                Link(destination: entry.configuration.rightShortcut.destination) {
                    IconView(image: entry.configuration.rightShortcut.icon)
                }
            }
        }
        .widgetContainerBackground(color: Color(designSystemColor: .backgroundSheets))
    }
}

private struct SearchBoxView: View {
    var body: some View {
        HStack {
            Image(.duckDuckGoColor28)
                .resizable()
                .useFullColorRendering()
                .frame(width: 28, height: 28)
                .padding(.leading, 12)

            Text(UserText.quickActionsSearch)
                .daxBodyRegular()
                .makeAccentable()

            Spacer()
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 46)
                .fill(Color(designSystemColor: .container))
        )
    }
}

private struct IconView: View {
    let image: Image

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(designSystemColor: .container))
            image
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .makeAccentable()
        }
        .frame(width: 60, height: 60)
    }
}
