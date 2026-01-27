//
//  NewTabPageDataModel+Telemetry.swift
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

public extension NewTabPageDataModel {

    enum TelemetryEvent: Equatable {
        case customizerOpened(themePopoverWasOpen: Bool)
        case customizerClosed
    }
}

extension NewTabPageDataModel.TelemetryEvent: Decodable {

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payload = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .payload)
        let eventName = try payload.decode(EventName.self, forKey: .name)
        let parameters = try payload.nestedContainer(keyedBy: CodingKeys.self, forKey: .parameters)

        switch eventName {
        case .customizer:
            self = try Self.decodeCustomizerEvent(from: parameters)
        }
    }
}

private extension NewTabPageDataModel.TelemetryEvent {

    enum CodingKeys: String, CodingKey {
        case payload = "attributes"
        case name
        case parameters = "value"
        case state
        case themeVariantPopoverWasOpen
    }

    enum EventName: String, Decodable {
        case customizer = "customizer_drawer"
    }

    enum CustomizerState: String, Decodable {
        case opened
        case closed
    }

    private static func decodeCustomizerEvent(from container: KeyedDecodingContainer<CodingKeys>) throws -> NewTabPageDataModel.TelemetryEvent {
        let state = try container.decode(CustomizerState.self, forKey: .state)

        switch state {
        case .opened:
            let themePopoverWasOpen = try container.decodeIfPresent(Bool.self, forKey: .themeVariantPopoverWasOpen) ?? false
            return .customizerOpened(themePopoverWasOpen: themePopoverWasOpen)

        case .closed:
            return .customizerClosed
        }
    }
}
