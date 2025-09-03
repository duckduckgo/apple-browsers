//
//  DDGError.swift
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

/// Base protocol defining the standard structure and behaviour for all errors in DuckDuckGo applications.
///
/// This protocol establishes a consistent error handling pattern across the entire codebase,
/// providing standardized error information, debugging capabilities, and seamless integration
/// with Apple's NSError system.
///
/// ## Core Features
/// - **Standardized Structure**: All DDG errors follow the same pattern with domain, code, and description
/// - **Error Chain Traversal**: Automatic traversal and inspection of nested error hierarchies  
/// - **NSError Integration**: Seamless conversion to NSError with proper userInfo dictionaries
/// - **Debugging Support**: Rich debug information and error chain visualization
/// - **Type Safety**: Strong typing while maintaining protocol flexibility
///
/// ## Usage Example
/// ```swift
/// enum NetworkError: DDGError {
///     case connectionFailed
///     case invalidResponse(underlying: Error?)
///     
///     static var errorDomain: String { "com.duckduckgo.networkErrorDomain" }
///
///     var errorCode: Int {
///         switch self {
///         case .connectionFailed: return 1001
///         case .invalidResponse: return 1002
///         }
///     }
///     
///     var underlyingError: Error? {
///         switch self {
///         case .connectionFailed: return nil
///         case .invalidResponse(let underlying): return underlying
///         }
///     }
///     
///     var description: String {
///         switch self {
///         case .connectionFailed: return "Network connection failed"
///         case .invalidResponse: return "Invalid network response received"
///         }
///     }
/// }
/// ```
///
/// ## Error Chain Inspection
/// ```swift
/// let rootError = SimpleError(message: "Database unavailable")
/// let networkError = NetworkError.invalidResponse(underlying: rootError)
/// 
/// // Inspect the complete error chain
/// print(networkError.errorsChain) // [NetworkError, SimpleError]
/// print(networkError.errorsChainDescription)
/// // Output:
/// // - Invalid network response received
/// // - Database unavailable
/// ```
///
/// ## Privacy & Security Considerations
/// - Error descriptions should not contain sensitive user data
/// - Use `errorsChainDescription` only for debugging/logging purposes
/// - Consider implementing privacy-safe descriptions for user-facing errors
///
/// ## Thread Safety
/// This protocol and its extensions are thread-safe and can be used from any queue.
public protocol DDGError: Error, Equatable, CustomNSError {
    // MARK: - Core Error Properties

    /// The error domain identifying the error's origin or category.
    ///
    /// This should be a unique string identifier that groups related errors together.
    /// Convention: Use reverse DNS notation (e.g., "com.duckduckgo.network")
    ///
    var errorDomain: String { get }

    /// A unique numeric identifier for this specific error within its domain.
    ///
    /// Error codes should be:
    /// - Unique within the error domain
    /// - Stable across app versions (don't change existing codes)
    /// - Meaningful and well-documented
    ///
    /// Example:
    /// ```swift
    /// var errorCode: Int {
    ///     switch self {
    ///     case .connectionTimeout: return 1001
    ///     case .invalidCredentials: return 1002
    ///     case .serverUnavailable: return 1003
    ///     }
    /// }
    /// ```
    var errorCode: Int { get }

    /// The underlying error that caused this error, if any.
    ///
    /// This creates a chain of errors that can be traversed for debugging and logging.
    /// Set to `nil` if this is a root error with no underlying cause.
    ///
    /// Example:
    /// ```swift
    /// enum DatabaseError: DDGError {
    ///     case connectionFailed(underlying: Error?)
    ///     
    ///     var underlyingError: Error? {
    ///         switch self {
    ///         case .connectionFailed(let underlying): return underlying
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Important: Avoid circular references in error chains.
    var underlyingError: Error? { get }

    /// A human-readable description of the error for debugging purposes.
    ///
    /// This description should be:
    /// - Clear and concise
    /// - Suitable for developers/debugging (not user-facing)
    /// - Free of sensitive information (passwords, tokens, etc.)
    /// - Consistent in format and terminology
    ///
    /// Example:
    /// ```swift
    /// var description: String {
    ///     switch self {
    ///     case .connectionTimeout: return "Network request timed out after 30 seconds"
    ///     case .invalidCredentials: return "Authentication failed - invalid credentials"
    ///     }
    /// }
    /// ```
    ///
    /// - Note: For user-facing error messages, implement `LocalizedError`.
    var description: String { get }
}

/// Default implementations
public extension DDGError {

    var underlyingError: Error? { nil }

    var localizedDescription: String { description }
}

// MARK: - Error Chain Traversal

/// Extensions providing error chain traversal and debugging capabilities.
public extension DDGError {

    /// Returns an array containing this error and all underlying errors in the chain.
    ///
    /// This property traverses the complete error chain, starting from the current error
    /// and following the `underlyingError` links until reaching an error with no underlying cause.
    ///
    /// ## Chain Traversal Rules
    /// - The first element is always the current error (self)
    /// - Subsequent elements are underlying errors in order
    /// - Traversal stops when an error has no `underlyingError`
    /// - Traversal stops when encountering a non-DDGError (for safety)
    ///
    /// ## Performance
    /// This is computed each time it's accessed. For repeated access, consider caching the result.
    ///
    /// - Returns: An array of errors representing the complete error chain.
    /// - Complexity: O(n) where n is the depth of the error chain.
    var errorsChain: [Error] {
        var errors: [Error] = []
        var currentError: Error? = self

        while let error = currentError {
            errors.append(error)

            if let ddgError = error as? any DDGError {
                currentError = ddgError.underlyingError
            } else {
                break
            }
        }

        return errors
    }

    /// Returns a formatted string representation of the complete error chain.
    ///
    /// This property creates a multi-line string showing all errors in the chain,
    /// with each error on its own line prefixed with a dash. It's designed for
    /// debugging and logging purposes.
    ///
    /// ## Output Format
    /// ```
    /// - Primary error description
    /// - Underlying error description
    /// - Root cause description
    /// ```
    ///
    /// ## Description Selection
    /// - For DDGError instances: Uses the `description` property
    /// - For other Error types: Uses Swift's default string representation
    ///
    /// - Returns: A formatted multi-line string representing the error chain.
    var errorsChainDescription: String {
        let errorsDescriptions = errorsChain.map({ error in
            if let ddgError = error as? (any DDGError) {
                return ddgError.description
            } else {
                return String(describing: error)
            }
        })
        return "- \(errorsDescriptions.joined(separator: "\n- "))"
    }
}

// MARK: - NSError Integration

/// Extension providing seamless integration with Apple's NSError system.
public extension DDGError /*CustomNSError*/ {

    /// Creates a userInfo dictionary compatible with NSError for DDGError instances.
    ///
    /// This property provides the standard NSError userInfo keys populated with
    /// appropriate values from the DDGError properties. It enables seamless
    /// integration with Cocoa error handling patterns.
    ///
    /// ## Included Keys
    /// - `NSDebugDescriptionErrorKey`: The error's description
    /// - `NSUnderlyingErrorKey`: The underlying error (optional)
    ///
    /// It also provides additional localized information suitable for display to users. It includes all standard NSError
    /// keys that the system uses for error presentation.
    ///
    /// ## Included Keys
    /// - `NSLocalizedDescriptionKey`: Localized error description
    /// - `NSLocalizedFailureErrorKey`: Localized failure reason (optional)
    /// - `NSLocalizedRecoverySuggestionErrorKey`: Recovery suggestion (optional)
    ///
    /// ## Usage
    /// ```swift
    /// let ddgError = MyError.someFailure
    /// let nsError = NSError(domain: MyError.errorDomain,
    ///                      code: ddgError.errorCode,
    ///                      userInfo: ddgError.errorUserInfo)
    /// ```
    ///
    /// ## Integration with CustomNSError
    /// When a DDGError conforms to CustomNSError, this userInfo is automatically
    /// used when the error is bridged to NSError.
    ///
    /// - Returns: A dictionary suitable for use as NSError userInfo.
    var errorUserInfo: [String: Any] {
        var result: [String: Any] = [
            NSDebugDescriptionErrorKey: description
        ]
        if let underlying = underlyingError {
            result[NSUnderlyingErrorKey] = underlying
        }
        if let localisedError = self as? LocalizedError {
            result[NSLocalizedDescriptionKey] = localisedError.errorDescription
            if let failureReason = localisedError.failureReason {
                result[NSLocalizedFailureErrorKey] = failureReason
            }
            if let recoverySuggestion = localisedError.recoverySuggestion {
                result[NSLocalizedRecoverySuggestionErrorKey] = recoverySuggestion
            }
        }
        return result
    }
}
