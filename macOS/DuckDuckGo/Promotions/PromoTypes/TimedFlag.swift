//
//  TimedFlag.swift
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

/// A boolean flag that can be set and automatically cleared after a time interval.
/// Supports cancel-and-reschedule semantics: calling set again cancels the previous timer.
final class TimedFlag {
    private(set) var isSet = false
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue
    private let clearAfter: TimeInterval

    init(queue: DispatchQueue, clearAfter: TimeInterval) {
        self.queue = queue
        self.clearAfter = clearAfter
    }

    func set(onClear: (() -> Void)? = nil) {
        isSet = true
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.isSet = false
            onClear?()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + clearAfter, execute: item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
        isSet = false
    }
}
