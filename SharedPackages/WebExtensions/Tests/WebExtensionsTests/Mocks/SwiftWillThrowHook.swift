//
//  SwiftWillThrowHook.swift
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

import Foundation

/// XCTest installs a `swift_willThrow` hook that, on x86_64, corrupts a thrown
/// `WKNSError` before `catch` sees it. The app has no such hook, so tests of
/// WebKit's thrown errors run the throwing call without it.
enum SwiftWillThrowHook {

    static func disabled<T>(_ body: () throws -> T) rethrows -> T {
        disable()
        defer { restore() }
        return try body()
    }

    /// Keeps the hook disabled across the `await`: WebKit's async APIs throw
    /// after resuming, so the throw happens past the suspension point. Code
    /// that throws elsewhere meanwhile only loses XCTest's throw attribution.
    @MainActor
    static func disabled<T>(
        _ body: @MainActor () async throws -> T
    ) async rethrows -> T {
        disable()
        defer { restore() }
        return try await body()
    }

    private static let hook: UnsafeMutablePointer<UnsafeRawPointer?>? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        let symbol = dlsym(rtldDefault, "_swift_willThrow")
        return symbol?.assumingMemoryBound(to: UnsafeRawPointer?.self)
    }()

    // Overlapping callers share one disable: the first saves and clears the
    // hook, the last restores it.
    private static let lock = NSLock()
    private static var disabledCount = 0
    private static var savedHook: UnsafeRawPointer?

    private static func disable() {
        lock.lock()
        defer { lock.unlock() }
        disabledCount += 1
        guard disabledCount == 1 else { return }
        savedHook = hook?.pointee
        hook?.pointee = nil
    }

    private static func restore() {
        lock.lock()
        defer { lock.unlock() }
        disabledCount -= 1
        guard disabledCount == 0 else { return }
        hook?.pointee = savedHook
        savedHook = nil
    }

}
