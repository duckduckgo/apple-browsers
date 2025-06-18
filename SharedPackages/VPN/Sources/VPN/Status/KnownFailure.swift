//
//  KnownFailure.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public protocol SilentErrorConvertible: Error {
    var asSilentError: KnownFailure.SilentError? { get }
}

@objc
final public class KnownFailure: NSObject, Codable {
    public typealias SilentErrorCode = Int

    public enum SilentError: SilentErrorCode {
        case operationNotPermitted
        case loginItemVersionMismatched
        case registeredServerFetchingFailed
    }

    public let error: SilentErrorCode

    public init?(_ error: Error?) {
        if let nsError = error as? NSError, nsError.domain == "SMAppServiceErrorDomain", nsError.code == 1 {
            self.error = SilentError.operationNotPermitted.rawValue
            return
        }

        if let error = error as? SilentErrorConvertible, let silentError = error.asSilentError {
            self.error = silentError.rawValue
            return
        }

        return nil
    }
}
