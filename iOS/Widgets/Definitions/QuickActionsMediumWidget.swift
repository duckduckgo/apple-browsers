//
//  QuickActionsMediumWidget.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons

@available(iOS 17.0, *)
struct MediumConfigurationIntent: WidgetConfigurationIntent {
    static var title = LocalizedStringResource("widget.gallery.customshortcuts.edit.title")
    static var description = IntentDescription(LocalizedStringResource("widget.gallery.customshortcuts.edit.description"))

    @Parameter(title: LocalizedStringResource("widget.gallery.medium.customshortcuts.edit.shortcut1"), default: .voiceSearch)
    var shortcut1: ShortcutOption

    @Parameter(title: LocalizedStringResource("widget.gallery.medium.customshortcuts.edit.shortcut2"), default: .passwords)
    var shortcut2: ShortcutOption

    @Parameter(title: LocalizedStringResource("widget.gallery.medium.customshortcuts.edit.shortcut3"), default: .bookmarks)
    var shortcut3: ShortcutOption

    @Parameter(title: LocalizedStringResource("widget.gallery.medium.customshortcuts.edit.shortcut4"), default: .duckAI)
    var shortcut4: ShortcutOption

    init(shortcut1: ShortcutOption, shortcut2: ShortcutOption, shortcut3: ShortcutOption, shortcut4: ShortcutOption) {
        self.shortcut1 = shortcut1
        self.shortcut2 = shortcut2
        self.shortcut3 = shortcut3
        self.shortcut4 = shortcut4
    }

    init() { }
}

@available(iOS 17.0, *)
struct QuickActionsMediumWidget: Widget {
    let kind: String = "QuickActionsMediumWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MediumConfigurationIntent.self,
            provider: QuickActionsMediumProvider()
        ) { entry in
            QuickActionsMediumWidgetView(entry: entry)
        }
        .configurationDisplayName(UserText.quickActionsWidgetGalleryDisplayName)
        .description(UserText.quickActionsWidgetGalleryDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

@available(iOS 17.0, *)
struct QuickActionsMediumProvider: AppIntentTimelineProvider {
    typealias Entry = QuickActionsMediumEntry
    typealias Intent = MediumConfigurationIntent

    func placeholder(in context: Context) -> QuickActionsMediumEntry {
        QuickActionsMediumEntry(date: Date(), configuration: MediumConfigurationIntent())
    }

    func snapshot(for configuration: MediumConfigurationIntent, in context: Context) async -> QuickActionsMediumEntry {
        QuickActionsMediumEntry(date: Date(), configuration: configuration)
    }

    func timeline(for configuration: MediumConfigurationIntent, in context: Context) async -> Timeline<QuickActionsMediumEntry> {
        let entry = QuickActionsMediumEntry(date: Date(), configuration: configuration)
        return Timeline(entries: [entry], policy: .never)
    }
}

@available(iOS 17.0, *)
struct QuickActionsMediumEntry: TimelineEntry {
    let date: Date
    let configuration: MediumConfigurationIntent
}
