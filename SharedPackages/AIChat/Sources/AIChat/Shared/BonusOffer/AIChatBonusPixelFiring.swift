//
//  AIChatBonusPixelFiring.swift
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

/// Events the bonus offer reports. Each platform maps them to its own pixels.
public enum AIChatBonusEvent {
    /// The store couldn't read or write the record, e.g. a Keychain failure.
    case storeFailed(Error)
}

public protocol AIChatBonusPixelFiring {
    func fire(_ event: AIChatBonusEvent)
}

// TODO: To remove as it will be injected by the client when implementing pixels
public struct NullAIChatBonusPixelFiring: AIChatBonusPixelFiring {
    public init() {}
    public func fire(_ event: AIChatBonusEvent) {}
}
