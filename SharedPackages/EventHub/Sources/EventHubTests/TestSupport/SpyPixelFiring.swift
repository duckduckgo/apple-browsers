//
//  SpyPixelFiring.swift
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
@testable import EventHub

/// Test double for `EventHubPixelFiring`: records every fired pixel. `EventHubFixture` and
/// `EventHubFunctionalTests.Harness` expose this recording as `.fired`/`.count(of:)`.
final class SpyPixelFiring: EventHubPixelFiring {
    private(set) var fired: [FiredPixel] = []

    func enqueueFirePixel(named name: String, parameters: [String: String]) {
        fired.append(FiredPixel(name: name, parameters: parameters))
    }
}
