//
//  WebExtensionUpdatePixelFiringMock.swift
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

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class WebExtensionUpdatePixelFiringMock: WebExtensionPixelFiring {
    enum Event: Equatable {
        case applied(WebExtensionPixelExtension)
        case failed(WebExtensionPixelExtension, WebExtensionUpdateInstallFailure, WebExtensionUpdateRollback)
    }

    private(set) var events: [Event] = []

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .updateApplied(let value): events.append(.applied(value))
        case .updateInstallFailed(let value, let outcome, let rollback): events.append(.failed(value, outcome, rollback))
        default: break
        }
    }

    func reset() { events.removeAll() }
}
