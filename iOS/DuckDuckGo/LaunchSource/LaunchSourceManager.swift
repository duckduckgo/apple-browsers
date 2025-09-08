//
//  LaunchSourceManager.swift
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

import Core

protocol LaunchSourceManaging {
    var source: LaunchSource { get }
    func setSource(_ source: LaunchSource)
    func handleAppAction(_ appAction: LaunchAction)
}

enum LaunchSource: String {
    case standard
    case shortcut
    case URL
    case notification
}

final class LaunchSourceManager: LaunchSourceManaging {
    var source: LaunchSource = .standard

    public init() { }
    
    func setSource(_ source: LaunchSource) {
        Logger.lifecycle.debug("Setting Source \(source.rawValue, privacy: .public)")
        self.source = source
    }

    func handleAppAction(_ appAction: LaunchAction) {
        switch appAction {
        case .handleShortcutItem:
            setSource(.shortcut)
        case .openURL:
            setSource(.URL)
        case .showKeyboard:
            setSource(.standard)
        }
    }
}
