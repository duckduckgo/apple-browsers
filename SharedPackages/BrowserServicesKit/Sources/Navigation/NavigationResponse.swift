//
//  NavigationResponse.swift
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
import WebKit

public struct NavigationResponse {

    public let response: URLResponse

    public let isForMainFrame: Bool
    public let canShowMIMEType: Bool

    /// Currently active Main Frame Navigation associated with the NavigationResponse
    /// May be non-nil for non-main-frame NavigationResponse
    public internal(set) weak var mainFrameNavigation: Navigation?

    public init(response: URLResponse, isForMainFrame: Bool, canShowMIMEType: Bool, mainFrameNavigation: Navigation?) {
        self.response = response
        self.isForMainFrame = isForMainFrame
        self.canShowMIMEType = canShowMIMEType
        self.mainFrameNavigation = mainFrameNavigation
    }

    init(navigationResponse: WKNavigationResponse, mainFrameNavigation: Navigation?) {
        self.init(response: navigationResponse.response, isForMainFrame: navigationResponse.isForMainFrame, canShowMIMEType: navigationResponse.canShowMIMEType, mainFrameNavigation: mainFrameNavigation)
    }

    public var isSuccessful: Bool? {
        httpResponse?.isSuccessful
    }

}

public extension NavigationResponse {

    var url: URL {
        response.url ?? .empty
    }

    var httpResponse: HTTPURLResponse? {
        response as? HTTPURLResponse
    }

    var httpStatusCode: Int? {
        httpResponse?.statusCode
    }

    var shouldDownload: Bool {
        httpResponse?.shouldDownload ?? false
    }

}

extension NavigationResponse: CustomDebugStringConvertible {
    public var debugDescription: String {
        let statusCode = self.httpStatusCode.map { String($0) } ?? "-"
        return "<Response: \((response.url ?? .empty).absoluteString) status:\(statusCode)\(self.isForMainFrame ? "" : " non-main-frame")\(shouldDownload ? " shouldDownload" : "")>"
    }
}

public enum NavigationResponsePolicy: String, Equatable {
    case allow
    case cancel
    case download
}

extension NavigationResponsePolicy? {
    /// Pass decision making to next responder
    public static let next = NavigationResponsePolicy?.none
}
