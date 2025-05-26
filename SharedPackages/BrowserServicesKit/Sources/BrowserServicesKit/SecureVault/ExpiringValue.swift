//
//  ExpiringValue.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public final class ExpiringValue<T> {

    private var workItem: DispatchWorkItem?

    public var value: T? {
        didSet {
            workItem?.cancel()
            if value != nil {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.value = nil
                }
                self.workItem = workItem
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + expiresAfter, execute: workItem)
            }
        }
    }

    public let expiresAfter: TimeInterval

    public init(expiresAfter: TimeInterval) {
        self.expiresAfter = expiresAfter
    }

    deinit {
        workItem?.cancel()
    }

}
