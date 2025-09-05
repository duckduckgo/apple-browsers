//
//  WidePixelError.swift
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

public enum WidePixelError: DDGError, LocalizedError {
    case flowNotFound(pixelName: String)
    case typeMismatch(expected: String, actual: String)
    case serializationFailed(Error)
    case invalidFlowState
    case storageError(Error)
    case invalidParameters(String)

    public var description: String {
        switch self {
        case .flowNotFound(let pixelName):
            return "Wide pixel flow not found: \(pixelName)"
        case .typeMismatch(let expected, let actual):
            return "Type mismatch: expected \(expected), got \(actual)"
        case .serializationFailed(let error):
            return "Serialization failed: \(error.localizedDescription)"
        case .invalidFlowState:
            return "Invalid flow state"
        case .storageError(let error):
            return "Storage error: \(error.localizedDescription)"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        }
    }

    public var errorDescription: String? {
        return description
    }

    public var errorDomain: String { "com.duckduckgo.widePixel" }

    public var errorCode: Int {
        switch self {
        case .flowNotFound:
            return 0
        case .typeMismatch:
            return 1
        case .serializationFailed:
            return 2
        case .invalidFlowState:
            return 3
        case .storageError:
            return 4
        case .invalidParameters:
            return 5
        }
    }

    public var underlyingError: Error? {
        switch self {
        case .flowNotFound, .typeMismatch, .invalidFlowState, .invalidParameters:
            return nil
        case .serializationFailed(let error), .storageError(let error):
            return error
        }
    }

    public var failureReason: String? {
        switch self {
        case .flowNotFound:
            return "The specified wide pixel flow has not been started or has been completed/cleared"
        case .typeMismatch:
            return "The stored feature data type does not match the requested type"
        case .serializationFailed:
            return "Failed to encode or decode wide pixel data"
        case .invalidFlowState:
            return "The flow is in an invalid state for the requested operation"
        case .storageError:
            return "Failed to read from or write to UserDefaults storage"
        case .invalidParameters:
            return "The provided parameters are invalid or incomplete"
        }
    }

    public static func == (lhs: WidePixelError, rhs: WidePixelError) -> Bool {
        switch (lhs, rhs) {
        case (.flowNotFound(let lhsPixelName), .flowNotFound(let rhsPixelName)):
            return lhsPixelName == rhsPixelName
        case (.typeMismatch(let lhsExpected, let lhsActual), .typeMismatch(let rhsExpected, let rhsActual)):
            return lhsExpected == rhsExpected && lhsActual == rhsActual
        case (.serializationFailed(let lhsError), .serializationFailed(let rhsError)):
            return (lhsError as NSError) == (rhsError as NSError)
        case (.invalidFlowState, .invalidFlowState):
            return true
        case (.storageError(let lhsError), .storageError(let rhsError)):
            return (lhsError as NSError) == (rhsError as NSError)
        case (.invalidParameters(let lhsMessage), .invalidParameters(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
