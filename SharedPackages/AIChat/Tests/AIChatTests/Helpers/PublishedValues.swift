//
//  PublishedValues.swift
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

import Combine

/// Collects every value a publisher emits, for tests to assert on.
final class PublishedValues<Value> {
    private(set) var values: [Value] = []
    private var cancellable: AnyCancellable?

    init(_ publisher: AnyPublisher<Value, Never>) {
        cancellable = publisher.sink { [unowned self] value in
            values.append(value)
        }
    }
}
