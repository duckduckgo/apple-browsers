//
//  QuickActionsSmallWidget.swift
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
    /// LocalizedStringResource requires a string literal
    static var title = LocalizedStringResource("widget.gallery.customshortcuts.edit.title")
    static var description = IntentDescription(LocalizedStringResource("widget.gallery.customshortcuts.edit.description"))

    @Parameter(title: LocalizedStringResource("widget.gallery.customshortcuts.edit.left"), default: .duckAI)
    var leftShortcut: ShortcutOption

    @Parameter(title: LocalizedStringResource("widget.gallery.customshortcuts.edit.right"), default: .passwords)
    var rightShortcut: ShortcutOption

    init(leftShortcut: ShortcutOption, rightShortcut: ShortcutOption) {
        self.leftShortcut = leftShortcut
        self.rightShortcut = rightShortcut
    }

    init() { }
}

@available(iOS 17.0, *)
struct QuickActionsSmallWidget: Widget {
    let kind: String = "QuickActionsWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: QuickActionsProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
        }
        .configurationDisplayName(UserText.quickActionsWidgetGalleryDisplayName)
        .description(UserText.quickActionsWidgetGalleryDescription)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
