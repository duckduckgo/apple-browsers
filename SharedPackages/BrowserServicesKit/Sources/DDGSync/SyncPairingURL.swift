//
//  SyncPairingURL.swift
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

import Foundation

/// A typed pairing URL destination. Query and fragment data never become part of the destination.
public enum SyncPairingURL: Equatable, Sendable {
    case duckCom
    case duckAI

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              ["/pair", "/pair/"].contains(components.path.lowercased()) else {
            return nil
        }

        switch components.host?.lowercased() {
        case "duck.com", "www.duck.com":
            self = .duckCom
        case "duck.ai", "www.duck.ai":
            self = .duckAI
        default:
            return nil
        }
    }
}
