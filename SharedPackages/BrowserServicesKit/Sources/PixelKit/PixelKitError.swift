//
//  PixelKitError.swift
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
import Common

public enum PixelKitError: DDGError {
    case externalError(Error)

    // MARK: - DDGError Conformance

    public static var errorDomain: String { "com.duckduckgo.pixelkit" }

    public var errorCode: Int {
        switch self {
        case .externalError: return 0
        }
    }

    public var underlyingError: Error? {
        switch self {
        case .externalError(let underlyingError): return underlyingError
        }
    }

    public var description: String {
        switch self {
        case .externalError(let underlyingError): return "An external error occurred: \(underlyingError)"
        }
    }

    public static func == (lhs: PixelKitError, rhs: PixelKitError) -> Bool {
        switch (lhs, rhs) {
        case (.externalError(let lhs), .externalError(let rhs)):
            return String(describing: lhs) == String(describing: rhs)
        }
    }
}
