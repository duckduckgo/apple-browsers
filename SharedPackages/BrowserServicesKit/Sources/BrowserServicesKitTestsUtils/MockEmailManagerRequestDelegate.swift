//
//  MockEmailManagerRequestDelegate.swift
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

@testable import BrowserServicesKit
import Foundation

public class MockEmailManagerRequestDelegate: EmailManagerRequestDelegate {

    public init(didSendMockAliasRequest: @escaping () -> Void = {}) {
        self.didSendMockAliasRequest = didSendMockAliasRequest
    }

    public var activeTask: URLSessionTask?
    public var mockAliases: [String] = []
    public var waitlistTimestamp: Int = 1
    public var didSendMockAliasRequest: () -> Void

    public func emailManager(_ emailManager: EmailManager, requested url: URL, method: String, headers: [String: String], parameters: [String: String]?, httpBody: Data?, timeoutInterval: TimeInterval) async throws -> Data {
        switch url.absoluteString {
        case EmailUrls.Url.emailAlias: return try processMockAliasRequest().get()
        default: fatalError("\(#file): Unsupported URL passed to mock request delegate: \(url)")
        }
    }

    public var keychainAccessErrorAccessType: EmailKeychainAccessType?
    public var keychainAccessError: EmailKeychainAccessError?

    public func emailManagerKeychainAccessFailed(_ emailManager: EmailManager,
                                                 accessType: EmailKeychainAccessType,
                                                 error: EmailKeychainAccessError) {
        keychainAccessErrorAccessType = accessType
        keychainAccessError = error
    }

    private func processMockAliasRequest() -> Result<Data, Error> {
        didSendMockAliasRequest()

        if mockAliases.first != nil {
            let alias = mockAliases.removeFirst()
            let jsonString = "{\"address\":\"\(alias)\"}"
            let data = jsonString.data(using: .utf8)!
            return .success(data)
        } else {
            return .failure(AliasRequestError.noDataError)
        }
    }

}
