//
//  MockInstallationPathResolver.swift
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
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class MockInstallationPathResolver: WebExtensionInstallationPathResolving {

    var paths: [DuckDuckGoWebExtensionType: URL] = [:]
    var reloadCallCount = 0
    var shouldThrowOnReload = false

    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? {
        paths[type]
    }

    @MainActor
    func reloadExtension(for type: DuckDuckGoWebExtensionType) async throws {
        reloadCallCount += 1
        if shouldThrowOnReload {
            throw NSError(domain: "MockInstallationPathResolver", code: 1)
        }
    }
}
