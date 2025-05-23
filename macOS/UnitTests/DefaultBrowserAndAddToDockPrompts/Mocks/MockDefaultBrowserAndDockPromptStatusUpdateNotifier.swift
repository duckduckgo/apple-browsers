//
//  MockDefaultBrowserAndDockPromptStatusUpdateNotifier.swift
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
import Combine
@testable import DuckDuckGo_Privacy_Browser

final class MockDefaultBrowserAndDockPromptStatusUpdateNotifier: DefaultBrowserAndDockPromptStatusNotifying {
    private let subject = PassthroughSubject<DefaultBrowserAndDockPromptStatusInfo, Never>()
    private(set) var didCallStartNotifyingStatus = false
    private(set) var didCallStopNotifyingStatus = false

    var statusPublisher: AnyPublisher<DefaultBrowserAndDockPromptStatusInfo, Never> {
        subject.eraseToAnyPublisher()
    }

    func startNotifyingStatus(interval: TimeInterval) {
        didCallStartNotifyingStatus = true
    }

    func stopNotifyingStatus() {
        didCallStopNotifyingStatus = true
    }

    func sendValue(_ value: DefaultBrowserAndDockPromptStatusInfo) {
        subject.send(value)
    }
}
