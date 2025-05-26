//
//  NonStandardEvent.swift
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

/// This custom event is used for special cases, like pixels with non-standard names and uses, these pixels are sent as is and the names remain unchanged
public final class NonStandardEvent: PixelKitEventV2 {

    let event: PixelKitEventV2

    public init(_ event: PixelKitEventV2) {
        self.event = event
    }

    public var name: String {
        event.name
    }

    public var parameters: [String: String]? {
        event.parameters
    }

    public var error: Error? {
        event.error
    }
}
