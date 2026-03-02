//
//  TextZoomStorage.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Common
import Persistence

protocol TextZoomStoring {
    func textZoomLevelForDomain(_ domain: String) -> TextZoomLevel?
    func set(textZoomLevel: TextZoomLevel, forDomain domain: String)
    func removeTextZoomLevel(forDomain domain: String)
    func resetTextZoomLevels(excludingDomains: [String])
    func resetTextZoomLevels(forVisitedDomains visitedDomains: [String], excludingDomains: [String])
    func clearAll()
}

class TextZoomStorage: TextZoomStoring {
    
    enum TextZoomStorageKey: String {
        case domainTextZoomStorage = "com.duckduckgo.ios.domainTextZoomStorage"
        case fireModeTextZoomStorage = "com.duckduckgo.ios.fireModeTextZoom"
    }

    private let store: KeyValueStoring
    private let key: String

    init(store: KeyValueStoring = UserDefaults.app, storageKey: String) {
        self.store = store
        self.key = storageKey
    }

    private var textZoomLevels: [String: Int] {
        get {
            store.object(forKey: key) as? [String: Int] ?? [:]
        }
        set {
            store.set(newValue, forKey: key)
        }
    }

    func textZoomLevelForDomain(_ domain: String) -> TextZoomLevel? {
        guard let zoomLevel = textZoomLevels[domain] else {
            return nil
        }
        return TextZoomLevel(rawValue: zoomLevel)
    }
    
    func set(textZoomLevel: TextZoomLevel, forDomain domain: String) {
        textZoomLevels[domain] = textZoomLevel.rawValue
    }

    func removeTextZoomLevel(forDomain domain: String) {
        textZoomLevels.removeValue(forKey: domain)
    }

    func resetTextZoomLevels(excludingDomains: [String]) {
        let tld = TLD()
        textZoomLevels = textZoomLevels.filter { level in
            excludingDomains.contains(where: {
                tld.eTLDplus1($0) == level.key
            })
        }
    }

    /// Iterates through stored text zoom levels, only removes if NOT fireproofed AND was visited.
    func resetTextZoomLevels(forVisitedDomains visitedDomains: [String], excludingDomains: [String]) {
        let tld = TLD()
        let visitedETLDplus1 = Set(visitedDomains.compactMap { tld.eTLDplus1($0) ?? $0 })

        // Keep if fireproofed OR not visited
        textZoomLevels = textZoomLevels.filter { level in
            excludingDomains.contains(where: {
                tld.eTLDplus1($0) == level.key
            })
            || !visitedETLDplus1.contains(level.key)
        }
    }

    func clearAll() {
        store.removeObject(forKey: key)
    }

}
