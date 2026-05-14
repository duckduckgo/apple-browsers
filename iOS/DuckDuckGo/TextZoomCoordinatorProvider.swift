//
//  TextZoomCoordinatorProvider.swift
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
import Core

enum TextZoomContext: Hashable {
    case normal
    case fireMode
    
    var storageKey: String {
        switch self {
        case .normal:
            return "com.duckduckgo.ios.domainTextZoomStorage"
        case .fireMode:
            return "com.duckduckgo.ios.fireModeTextZoom"
        }
    }
}

protocol TextZoomCoordinatorProviding {
    func coordinator(for context: TextZoomContext) -> TextZoomCoordinating
}

final class TextZoomCoordinatorProvider: TextZoomCoordinatorProviding {

    private let appSettings: AppSettings
    private let lock = NSLock()
    private var coordinators: [TextZoomContext: TextZoomCoordinating] = [:]

    init(appSettings: AppSettings) {
        self.appSettings = appSettings
    }

    func coordinator(for context: TextZoomContext) -> TextZoomCoordinating {
        lock.lock()
        defer { lock.unlock() }

        if let existing = coordinators[context] {
            return existing
        }

        let storage = TextZoomStorage(storageKey: context.storageKey)
        let coordinator = TextZoomCoordinator(appSettings: appSettings, storage: storage)
        coordinators[context] = coordinator
        return coordinator
    }

}

extension Tab {
    var textZoomContext: TextZoomContext {
        self.fireTab ? .fireMode : .normal
    }
}
