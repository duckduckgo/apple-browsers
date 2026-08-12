//
//  BookmarkReorder.swift
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

enum BookmarkReorder {
    struct State {
        let objectUUIDs: [String]
        let sortMode: BookmarksSortMode
    }

    @MainActor
    final class OperationContext {
        struct Transition {
            let state: BookmarkReorder.State
            let inverse: BookmarkReorder.State
        }

        enum State {
            case idle
            case persisting(pending: Transition?)
        }

        var state: State = .idle
    }
}
