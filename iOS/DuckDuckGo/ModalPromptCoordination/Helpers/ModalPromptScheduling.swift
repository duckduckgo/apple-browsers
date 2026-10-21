//
//  ModalPromptScheduling.swift
//  DuckDuckGo
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

// Used to present modal prompt with a small delay. Used to easily write test by replacing it with an ImmediateScheduler.
protocol ModalPromptScheduling {
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void)
}

final class ModalPromptScheduler: ModalPromptScheduling {
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: execute)
    }
}
