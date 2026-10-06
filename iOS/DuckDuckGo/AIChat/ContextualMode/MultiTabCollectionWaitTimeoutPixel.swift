//
//  MultiTabCollectionWaitTimeoutPixel.swift
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

import PixelKit

struct MultiTabCollectionWaitTimeoutPixel: PixelKit.Event {
    enum Reason: String {
        case sourceCollection = "source_collection"
        case crossTabCollection = "cross_tab_collection"
        case both

        init?(hasSourceCollection: Bool, hasCrossTabCollection: Bool) {
            switch (hasSourceCollection, hasCrossTabCollection) {
            case (true, true): self = .both
            case (true, false): self = .sourceCollection
            case (false, true): self = .crossTabCollection
            case (false, false): return nil
            }
        }
    }

    let reason: Reason

    var name: String { "aichat_contextual_tab_attachment_collection_wait_timeout" }
    var parameters: [String: String]? { ["reason": reason.rawValue] }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}
