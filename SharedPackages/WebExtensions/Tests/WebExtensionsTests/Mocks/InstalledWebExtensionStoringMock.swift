//
//  InstalledWebExtensionStoringMock.swift
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

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
final class InstalledWebExtensionStoringMock: InstalledWebExtensionStoring {

    var installedExtensions: [InstalledWebExtension] = []

    var addCalled = false
    var addedExtension: InstalledWebExtension?
    func add(_ extension: InstalledWebExtension) {
        addCalled = true
        addedExtension = `extension`
        installedExtensions.append(`extension`)
    }

    var removeCalled = false
    var removedIdentifier: String?
    func remove(uniqueIdentifier: String) {
        removeCalled = true
        removedIdentifier = uniqueIdentifier
        installedExtensions.removeAll { $0.uniqueIdentifier == uniqueIdentifier }
    }

    func installedExtension(withUniqueIdentifier uniqueIdentifier: String) -> InstalledWebExtension? {
        installedExtensions.first { $0.uniqueIdentifier == uniqueIdentifier }
    }
}
