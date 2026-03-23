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

class MockTabPreviewsSource: TabPreviewsSource {

    var removePreviewsWithIdNotInCalls = [Set<String>]()
    private(set) var removeAllPreviewsCalled = false
    var totalStoredPreviewsReturnValue: Int?

    init(totalStoredPreviews: Int? = nil) {
        self.totalStoredPreviewsReturnValue = totalStoredPreviews
    }

    func prepare() {
    }

    func update(preview: UIImage, forTab tab: DuckDuckGo.Tab) {
    }

    func removePreview(forTab tab: DuckDuckGo.Tab) {
    }

    func removeAllPreviews() -> Result<Void, Error> {
        removeAllPreviewsCalled = true
        return .success(())
    }

    func removePreviewsWithIdNotIn(_ ids: Set<String>) -> Result<Void, Error>  {
        removePreviewsWithIdNotInCalls.append(ids)
        return .success(())
    }

    func totalStoredPreviews() -> Int? {
        return totalStoredPreviewsReturnValue
    }

    func preview(for tab: DuckDuckGo.Tab) -> UIImage? {
        return nil
    }

}
