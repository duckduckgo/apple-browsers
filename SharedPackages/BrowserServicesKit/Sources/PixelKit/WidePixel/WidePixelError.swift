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

/// Errors that can occur during wide pixel operations
public enum WidePixelError: Error, LocalizedError {
    /// Flow with the specified pixel name was not found
    case flowNotFound(pixelName: String)
    
    /// Type mismatch when trying to decode feature data
    case typeMismatch(expected: String, actual: String)
    
    /// Failed to serialize or deserialize data
    case serializationFailed(Error)
    
    /// Invalid flow state (e.g., trying to complete a flow that was never started)
    case invalidFlowState
    
    /// UserDefaults storage error
    case storageError(Error)
    
    /// Invalid parameters provided
    case invalidParameters(String)
    
    public var errorDescription: String? {
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
}