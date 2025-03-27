//
//  BookmarkUpdate.swift
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

import Foundation

struct BookmarkUpdate: Codable {

    let id: String?
    let next: String?
    let parent: String?
    let title: String?

    let page: Page?
    let favorite: Favorite?
    let folder: Folder?

    let deleted: String?

    struct Page: Codable {
        let url: String?
    }

    struct Favorite: Codable {
        let next: String?
    }

    struct Folder: Codable {
    }
}
