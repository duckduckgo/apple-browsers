//
//  ShortcutOption.swift
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

import SwiftUI
import AppIntents
import DesignResourcesKitIcons

@available(iOS 17.0, *)
enum ShortcutOption: String, CaseIterable, Identifiable, AppEnum {
    case passwords
    case duckAI
    case duckAIVoice
    case voiceSearch
    case favorites
    case emailProtection
    case vpn
    case bookmarks

    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("widget.shortcut.option.type-name")
    )
    static var caseDisplayRepresentations: [ShortcutOption: DisplayRepresentation] = [
        .passwords: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.passwords")),
        .duckAI: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.duck-ai")),
        .duckAIVoice: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.duck-ai-voice")),
        .voiceSearch: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.voice-search")),
        .favorites: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.favorites")),
        .emailProtection: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.duck-address")),
        .vpn: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.vpn")),
        .bookmarks: DisplayRepresentation(title: LocalizedStringResource("widget.shortcut.option.bookmarks"))
    ]

    var id: String { self.rawValue }

    var icon: Image {
        switch self {
        case .passwords: return Image(uiImage: DesignSystemImages.Glyphs.Size24.key)
        case .duckAI: return Image(uiImage: DesignSystemImages.Glyphs.Size24.aiChat)
        case .duckAIVoice: return Image(uiImage: DesignSystemImages.Glyphs.Size24.voice)
        case .voiceSearch: return Image(uiImage: DesignSystemImages.Glyphs.Size24.microphone)
        case .favorites: return Image(uiImage: DesignSystemImages.Glyphs.Size24.favorite)
        case .emailProtection: return Image(uiImage: DesignSystemImages.Glyphs.Size24.email)
        case .vpn: return Image(uiImage: DesignSystemImages.Glyphs.Size24.vpn)
        case .bookmarks: return Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmarks)
        }
    }

    func destination(for source: WidgetSourceType) -> URL {
        baseURL
            .appendingParameter(name: WidgetSourceType.sourceKey, value: source.rawValue)
            .appendingParameter(name: WidgetSourceType.shortcutKey, value: rawValue)
    }

    private var baseURL: URL {
        switch self {
        case .passwords: return DeepLinks.openPasswords
        case .duckAI: return DeepLinks.openAIChat
        case .duckAIVoice: return DeepLinks.openAIVoiceChat
        case .voiceSearch: return DeepLinks.voiceSearch
        case .favorites: return DeepLinks.favorites
        case .emailProtection: return DeepLinks.newEmail
        case .vpn: return DeepLinks.openVPN
        case .bookmarks: return DeepLinks.openBookmarks
        }
    }
}
