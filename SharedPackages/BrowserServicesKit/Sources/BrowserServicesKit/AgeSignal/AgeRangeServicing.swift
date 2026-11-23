//
//  AgeRangeServicing.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DeclaredAgeRange
#if os(macOS)
import AppKit
public typealias AgeRangeAnchor = NSWindow
#else
import UIKit
public typealias AgeRangeAnchor = UIViewController
#endif

@MainActor
public protocol AgeRangeServicing {
    func isRequestRequired() async throws -> Bool
    func requestAgeRange(in anchor: AgeRangeAnchor) async throws
}

public extension AgeRangeServicing {

    func isRequestRequired() async throws -> Bool {
        if #available(iOS 26.4, macOS 26.4, *) {
            return try await !AgeRangeService.shared.requiredRegulatoryFeatures.isEmpty
        }
        if #available(iOS 26.2, macOS 26.2, *) {
            return try await AgeRangeService.shared.isEligibleForAgeFeatures
        }
        return false
    }
}

@MainActor
public final class DefaultAgeRangeService: AgeRangeServicing {

    public init() {}

    private let defaultAgeBracket = 16

    public func requestAgeRange(in anchor: AgeRangeAnchor) async throws {
        guard #available(iOS 26.2, macOS 26.2, *) else {
            return
        }

        // Legal requires keeping only the request date, so the response is dropped.
        _ = try await AgeRangeService.shared.requestAgeRange(ageGates: defaultAgeBracket, in: anchor)
    }
}
