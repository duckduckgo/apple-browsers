//
//  FaviconMetadata.swift
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

/**
 * Describes a favicon stored in the database.
 *
 * This struct provides information about a favicon, except for its actual image data.
 * It's used by `FaviconStore` and `FaviconImageCache` to optimize memory when loading
 * favicons.
 */
struct FaviconMetadata: Sendable, Equatable {

    let identifier: UUID
    let url: URL
    let documentUrl: URL
    let dateCreated: Date
    let relation: Favicon.Relation

}
