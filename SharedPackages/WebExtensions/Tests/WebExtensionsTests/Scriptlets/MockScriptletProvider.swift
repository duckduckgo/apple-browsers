//
//  MockScriptletProvider.swift
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
import Foundation
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class MockScriptletProvider: ScriptletProviding {

    var startCallCount = 0
    var startedTypes: [DuckDuckGoWebExtensionType] = []
    var stopCallCount = 0
    var stoppedTypes: [DuckDuckGoWebExtensionType] = []

    var scriptletsMap: [DuckDuckGoWebExtensionType: [Scriptlet]] = [:]
    var versionMap: [DuckDuckGoWebExtensionType: String] = [:]
    var availabilitySubjects: [DuckDuckGoWebExtensionType: CurrentValueSubject<ScriptletAvailability, Never>] = [:]

    func start(for extensionType: DuckDuckGoWebExtensionType) async {
        startCallCount += 1
        startedTypes.append(extensionType)
    }

    func stop(for extensionType: DuckDuckGoWebExtensionType) {
        stopCallCount += 1
        stoppedTypes.append(extensionType)
    }

    func availability(for extensionType: DuckDuckGoWebExtensionType) -> ScriptletAvailability {
        availabilitySubjects[extensionType]?.value ?? .notAvailable
    }

    func availabilityPublisher(for extensionType: DuckDuckGoWebExtensionType) -> AnyPublisher<ScriptletAvailability, Never> {
        let subject = availabilitySubjects[extensionType] ?? CurrentValueSubject(.notAvailable)
        availabilitySubjects[extensionType] = subject
        return subject.eraseToAnyPublisher()
    }

    func scriptlets(for extensionType: DuckDuckGoWebExtensionType) -> [Scriptlet]? {
        scriptletsMap[extensionType]
    }

    func scriptletVersion(for extensionType: DuckDuckGoWebExtensionType) -> String? {
        versionMap[extensionType]
    }

    func isReady(for extensionType: DuckDuckGoWebExtensionType) -> Bool {
        scriptletsMap[extensionType] != nil
    }

    func refreshIfNeeded(for extensionType: DuckDuckGoWebExtensionType) async {}

    func clearCachedScriptlets() {}
}
