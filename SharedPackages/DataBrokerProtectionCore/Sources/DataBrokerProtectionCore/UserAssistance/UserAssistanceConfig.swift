//
//  UserAssistanceConfig.swift
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

/// Whether opt-outs that need the user can be handed to them. Each broker's own definition says whether its opt-out needs the user.
public struct UserAssistanceConfig: Equatable, Sendable {
    public let isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }
}

public extension DataBroker {
    var requiresUserAssistance: Bool {
        optOutStep()?.actions.contains(where: \.requiresUserAssistance) ?? false
    }
}

public extension BrokerProfileJobDependencyProviding {
    var userAssistanceConfig: UserAssistanceConfig {
        UserAssistanceConfig(isEnabled: featureFlagger.isUserAssistanceOn)
    }
}
