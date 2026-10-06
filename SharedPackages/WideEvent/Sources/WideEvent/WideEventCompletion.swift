//
//  WideEventCompletion.swift
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

public enum WideEventCompletionTrigger {
    case appLaunch
}

public enum WideEventCompletionDecision {
    case keepPending
    case complete(WideEventStatus)
}

// By default, events shouldn't complete automatically - this should be overridden on a per-event basis any
// time that automatic completion is needed.
extension WideEventData {
    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        .keepPending
    }
}
