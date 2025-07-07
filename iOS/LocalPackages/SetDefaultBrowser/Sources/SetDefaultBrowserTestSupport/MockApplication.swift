//
//  MockApplication.swift
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

import SetDefaultBrowserCore
import class UIKit.UIApplication

@available(iOS 18.2, *)
package class MockApplication: ApplicationDefaultCategoryChecking {
    package init() {}

    package var resultToReturn: Result<Bool, Error> = .success(false)

    package func isDefault(_ category: UIApplication.Category) throws -> Bool {
        switch resultToReturn {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}
