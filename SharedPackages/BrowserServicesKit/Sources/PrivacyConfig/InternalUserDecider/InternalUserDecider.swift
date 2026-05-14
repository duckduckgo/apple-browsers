//
//  InternalUserDecider.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Combine
import Common

public protocol InternalUserDecider {

    var isInternalUser: Bool { get }
    var isInternalUserPublisher: AnyPublisher<Bool, Never> { get }

    @discardableResult
    func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool
}

public protocol InternalUserStoring {
    var isInternalUser: Bool { get set }
}

public class DefaultInternalUserDecider: InternalUserDecider {
    var store: InternalUserStoring
    private static let internalUserVerificationURLHost = "use-login.duckduckgo.com"
    private let isInternalUserSubject: CurrentValueSubject<Bool, Never>

    public init(store: InternalUserStoring) {
        self.store = store
        isInternalUserSubject = CurrentValueSubject(store.isInternalUser)
    }

    public private(set) var isInternalUser: Bool {
        get {
            store.isInternalUser
        }
        set {
            store.isInternalUser = newValue
            isInternalUserSubject.send(newValue)
        }
    }

    public var isInternalUserPublisher: AnyPublisher<Bool, Never> {
        isInternalUserSubject.eraseToAnyPublisher()
    }

    @discardableResult
    public func markUserAsInternalIfNeeded(forUrl url: URL?, response: HTTPURLResponse?) -> Bool {
        if isInternalUser { // If we're already an internal user, we don't need to do anything
            return false
        }

        if shouldMarkUserAsInternal(forUrl: url, statusCode: response?.statusCode) {
            isInternalUser = true
            return true
        }
        return false
    }

    func shouldMarkUserAsInternal(forUrl url: URL?, statusCode: Int?) -> Bool {
        if let statusCode = statusCode,
           statusCode == 200,
           let url = url,
           url.host == DefaultInternalUserDecider.internalUserVerificationURLHost {

            return true
        }
        return false
    }
}

extension DefaultInternalUserDecider {

    // Used to set internal user state from debug menu.
    public func debugSetInternalUserState(_ state: Bool) {
        isInternalUser = state
    }
}
