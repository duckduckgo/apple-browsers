//
//  MockTabPreviewsSource.swift
//  DuckDuckGo
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
import UIKit
@testable import DuckDuckGo

// Can be moved to mocks if needs to be used elsewhere (unlikely so just keep it close for now).
class MockTabPreviewsSource: TabPreviewsSource {

    var _removePreviewsWithIdNotInCalls = [Set<String>]()
    var _totalStoredPreviews: Int?

    init(_totalStoredPreviews: Int? = nil) {
        self._totalStoredPreviews = _totalStoredPreviews
    }

    func prepare() {
    }

    func update(preview: UIImage, forTab tab: DuckDuckGo.Tab) {
    }

    func removePreview(forTab tab: DuckDuckGo.Tab) {
    }

    func removeAllPreviews() {
    }

    func removePreviewsWithIdNotIn(_ ids: Set<String>) async {
        _removePreviewsWithIdNotInCalls.append(ids)
    }

    func totalStoredPreviews() -> Int? {
        return _totalStoredPreviews
    }

    func preview(for tab: DuckDuckGo.Tab) -> UIImage? {
        return nil
    }

}
