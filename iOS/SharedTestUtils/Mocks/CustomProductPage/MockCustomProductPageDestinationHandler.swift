//
//  MockCustomProductPageDestinationHandler.swift
//  DuckDuckGo
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

import UIKit
@testable import DuckDuckGo

final class MockCustomProductPageDestinationHandler: CustomProductPageDestinationHandling {
    private(set) var handleCalled = false
    private(set) var handleCallCount = 0
    private(set) var capturedURL: URL?
    private(set) var capturedPresenter: AppStoreCustomProductPagePresenter?

    func handle(url: URL, on presenter: AppStoreCustomProductPagePresenter) {
        handleCalled = true
        handleCallCount += 1
        capturedURL = url
        capturedPresenter = presenter
    }
}
