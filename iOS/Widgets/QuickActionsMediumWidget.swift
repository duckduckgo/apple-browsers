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
struct QuickActionsMediumWidget: Widget {
    let kind: String = "QuickActionsMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: QuickActionsMediumProvider()
        ) { entry in
            QuickActionsMediumWidgetView(entry: entry)
        }
        .configurationDisplayName(UserText.quickActionsMediumWidgetGalleryDisplayName)
        .description(UserText.quickActionsMediumWidgetGalleryDescription)
        .supportedFamilies([.systemMedium])
    }
}

@available(iOS 17.0, *)
struct QuickActionsMediumProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickActionsMediumEntry {
        QuickActionsMediumEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickActionsMediumEntry) -> Void) {
        let entry = QuickActionsMediumEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickActionsMediumEntry>) -> Void) {
        let entry = QuickActionsMediumEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

@available(iOS 17.0, *)
struct QuickActionsMediumEntry: TimelineEntry {
    let date: Date
}

@available(iOS 17.0, *)
struct QuickActionsMediumWidgetView: View {
    var entry: QuickActionsMediumEntry

    private let shortcuts: [ShortcutOption] = [.voiceSearch,
                                               .passwords,
                                               .favorites,
                                               .emailProtection]

    var body: some View {
        ZStack {
            VStack(alignment: .center, spacing: 0) {
                HStack(spacing: 12) {
                    LargeSearchFieldView()
                    if entry.isAIChatEnabled {
                        Link(destination: DeepLinks.openAIChat) {
                            CircleIconView(image: Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat))
                        }
                    }
                }

                HStack {
                    ForEach(shortcuts.indices, id: \.self) { index in
                        let shortcut = shortcuts[index]

                        Link(destination: shortcut.destination) {
                            QuickActionView(shortcut: shortcut)
                        }

                        if index < shortcuts.count - 1 {
                            Spacer()
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .widgetContainerBackground(color: Color(designSystemColor: .backgroundSheets))
    }
}

@available(iOS 17.0, *)
private struct QuickActionView: View {
    let shortcut: ShortcutOption

    var body: some View {
        VStack {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(designSystemColor: .controlsFillPrimary))
                    .frame(width: 60, height: 60)
                
                shortcut.icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .makeAccentable()
            }

        }
    }
}
