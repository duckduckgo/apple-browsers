//
//  NavigationState.swift
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
import WebKit

public enum NavigationState: Equatable, Comparable {

    case expected(NavigationType?)
    case navigationActionReceived
    case approved
    case started

    case willPerformClientRedirect(delay: TimeInterval)
    case redirected(RedirectType)

    case responseReceived
    case finished
    case failed(WKError)

    public var isExpected: Bool {
        if case .expected = self { return true }
        return false
    }

    var expectedNavigationType: NavigationType? {
        if case .expected(let navigationType) = self { return navigationType }
        return nil
    }

    public var isResponseReceived: Bool {
        if case .responseReceived = self { return true }
        return false
    }

    public var isFinished: Bool {
        if case .finished = self { return true }
        return false
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public var isCompleted: Bool {
        isFinished || isFailed
    }

    public static func == (lhs: NavigationState, rhs: NavigationState) -> Bool {
        switch lhs {
        case .expected(let navigationType): if case .expected(navigationType) = rhs { return true }
        case .navigationActionReceived: if case .navigationActionReceived = rhs { return true }
        case .approved: if case .approved = rhs { return true }
        case .started: if case .started = rhs { return true }
        case .willPerformClientRedirect(delay: let delay): if case .willPerformClientRedirect(delay: delay) = rhs { return true }
        case .redirected(let type): if case .redirected(type) = rhs { return true }
        case .responseReceived: if case .responseReceived = rhs { return true }
        case .finished: if case .finished = rhs { return true }
        case .failed(let error1): if case .failed(let error2) = rhs { return error1.code == error2.code }
        }
        return false
    }

    private var rawValue: UInt {
        switch self {
        case .expected: 0
        case .navigationActionReceived: 1
        case .approved: 2
        case .started: 3
        case .willPerformClientRedirect: 4
        case .redirected: 5
        case .responseReceived: 6
        case .finished: 7
        case .failed: 8
        }
    }

    public static func < (lhs: NavigationState, rhs: NavigationState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

}

extension NavigationState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .expected(let navigationType): return "expected(\(navigationType?.debugDescription ?? ""))"
        case .navigationActionReceived: return "navigationActionReceived"
        case .approved: return "approved"
        case .started: return "started"
        case .willPerformClientRedirect: return "willPerformClientRedirect"
        case .redirected: return "redirected"
        case .responseReceived: return "responseReceived"
        case .finished: return "finished"
        case .failed(let error): return "failed(\(error.errorDescription ?? error.localizedDescription))"
        }
    }
}
