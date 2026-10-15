//
//  MainViewController+DuckAIDirectNavigation.swift
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

import AIChat
import Core
import PixelKit

/// How the user reached a duck.ai address without using a Duck.ai entry point, spelled as on macOS.
enum DuckAINavigationVia: String {
    case typed
    case suggestion
    case bookmark
    case favorite
    case history
    /// Another app opened the link.
    case external
    case link
    case drop

    /// The door the entry pixel reports. As on Android, a link from another app is a deep link.
    var entrySource: AIChatEntryPointSource {
        self == .external ? .deepLinkOther : .directURL
    }
}

extension MainViewController {

    /// A user-initiated load of a duck.ai address. Returns the door to stamp on the tab that loads it.
    func reportDuckAIDirectNavigation(to url: URL, via: DuckAINavigationVia, opensNewTab: Bool) -> AIChatEntryPointSource? {
        guard url.isDuckAIURL else { return nil }
        fireDuckAIDirectNavigationPixel(via: via)
        fireAIChatEntryPointPixel(source: via.entrySource, opensNewTab: opensNewTab, hasPrompt: url.carriesDuckAIPrompt)
        return via.entrySource
    }

    func fireDuckAIDirectNavigationPixel(via: DuckAINavigationVia) {
        PixelKit.fire(Pixel.Event.aiChatDuckAIDirectNavigation, frequency: .dailyAndCount, options: .parameters([
            "duckai_enabled": String(aiChatSettings.isAIChatEnabled),
            "toggle_enabled": String(aiChatSettings.isAIChatSearchInputUserSettingsEnabled),
            "via": via.rawValue
        ]))
    }
}

extension URL {

    /// A duck.ai address that brings its own prompt.
    var carriesDuckAIPrompt: Bool {
        getParameter(named: AIChatURLParameters.promptQueryName)?.isEmpty == false
    }
}
