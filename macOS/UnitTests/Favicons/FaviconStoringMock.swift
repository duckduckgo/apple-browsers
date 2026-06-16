//
//  FaviconStoringMock.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import Foundation
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class FaviconStoringMock: FaviconStoring {

    // Seeded return values for tests.
    var faviconsToLoad: [Favicon] = []
    var metadataToLoad: [FaviconMetadata] = []
    var imagesByIdentifier: [UUID: NSImage] = [:]

    // Call recording.
    private(set) var loadFaviconsCallCount = 0
    private(set) var loadFaviconMetadataCallCount = 0
    private(set) var loadImageCallCount = 0
    private(set) var loadImageIdentifiers: [UUID] = []
    private(set) var removedFaviconIdentifiers: [UUID] = []

    func loadFavicons() async throws -> [Favicon] {
        loadFaviconsCallCount += 1
        return faviconsToLoad
    }

    func loadFaviconMetadata() async throws -> [FaviconMetadata] {
        loadFaviconMetadataCallCount += 1
        return metadataToLoad
    }

    func loadImage(for identifier: UUID) async throws -> NSImage? {
        loadImageCallCount += 1
        loadImageIdentifiers.append(identifier)
        return imagesByIdentifier[identifier]
    }

    func save(_ favicons: [Favicon]) async throws {
        ()
    }

    func removeFavicons(_ favicons: [Favicon]) async throws {
        removedFaviconIdentifiers.append(contentsOf: favicons.map(\.identifier))
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) {
        ([], [])
    }

    func save(hostReference: FaviconHostReference) async throws {
        ()
    }

    func save(urlReference: FaviconUrlReference) async throws {
        ()
    }

    func remove(hostReferences: [FaviconHostReference]) async throws {
        ()
    }

    func remove(urlReferences: [FaviconUrlReference]) async throws {
        ()
    }

}
