//
//  MockWKNavigationAction.swift
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

import WebKit

final class MockWKNavigationAction: WKNavigationAction {
    private let mockRequest: URLRequest
    private let mockTargetFrame: WKFrameInfo?
    private let mockSourceFrame: WKFrameInfo
    @objc(isUserInitiated) var _isUserInitiated: Bool

    init(request: URLRequest, targetFrame: WKFrameInfo?, sourceFrame: WKFrameInfo, isUserInitiated: Bool = false) {
        self.mockRequest = request
        self.mockTargetFrame = targetFrame
        self.mockSourceFrame = sourceFrame
        self._isUserInitiated = isUserInitiated
        super.init()
    }

    override var request: URLRequest {
        return mockRequest
    }

    override var targetFrame: WKFrameInfo? {
        return mockTargetFrame
    }

    override var sourceFrame: WKFrameInfo {
        return mockSourceFrame
    }
}
