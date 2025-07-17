//
//  SwiftObjectRetainCycleBreakerTests.swift
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
import Testing

@testable import DuckDuckGo_Privacy_Browser

final class SwiftObjectRetainCycleBreakerTests {

    @Test("Break retain cycle between two strongly linked objects")
    func simpleRetainCycleBreak() {
        class A: NSObject {
            var b: B?
            var didDeinit: () -> Void = {}
            deinit { didDeinit() }
        }
        class B: NSObject {
            var a: A?
            var didDeinit: () -> Void = {}
            deinit { didDeinit() }
        }

        var aDeallocated = false
        var bDeallocated = false

        var a: A! = A()
        var b: B! = B()
        a.didDeinit = { aDeallocated = true }
        b.didDeinit = { bDeallocated = true }
        a.b = b
        b.a = a

        ReflectionPropertySetter().breakRetainCycle(in: a, nullifying: "b")

        b = nil
        a = nil

        #expect(aDeallocated)
        #expect(bDeallocated)
    }

    @Test("Break retain cycle between two strongly linked objects with one holding a lazy var")
    func lazyVarRetainCycleBreak() {
        class A: NSObject {
            lazy var b: B = B()
            var didDeinit: () -> Void = {}
            deinit { didDeinit() }
        }
        class B: NSObject {
            var a: A?
            var didDeinit: () -> Void = {}
            deinit { didDeinit() }
        }

        var aDeallocated = false
        var bDeallocated = false

        var a: A! = A()
        var b: B! = a.b
        a.didDeinit = { aDeallocated = true }
        b.didDeinit = { bDeallocated = true }
        b.a = a

        ReflectionPropertySetter().breakRetainCycle(in: a, nullifying: "$__lazy_storage_$_b")

        b = nil
        a = nil

        #expect(aDeallocated)
        #expect(bDeallocated)
    }

    @Test("Validate the lazy var can be reinitialized after the retain cycle break")
    func lazyVarReinitializationAfterRetainCycleBreak() {
        class A: NSObject {
            lazy var b: B = B()
            var didDeinit: () -> Void = {}
            deinit { didDeinit() }
        }
        class B: NSObject {
            var a: A?
            var didDeinit: () -> Void = {}
            deinit { didDeinit() }
        }

        var aDeallocated = false
        var bDeallocated = false

        let a: A! = A()
        var b: B! = a.b
        a.didDeinit = { aDeallocated = true }
        b.didDeinit = { bDeallocated = true }
        b.a = a
        b = nil

        ReflectionPropertySetter().breakRetainCycle(in: a, nullifying: "$__lazy_storage_$_b")
        #expect(bDeallocated)

        b = a.b

        #expect(a.b != nil)
        #expect(b != nil)
        #expect(!aDeallocated)
    }

    @Test("Field not found should not crash or affect unrelated state")
    func missingFieldName() {
        class A: NSObject {
            var something: NSObject? = NSObject()
        }

        customAssertionFailure = { _, _, _ in }
        let a = A()
        ReflectionPropertySetter().breakRetainCycle(in: a, nullifying: "nonexistent")

        #expect(a.something != nil)
    }

    @Test("Nullify field in object with multiple fields")
    func multipleFieldsObject() {
        class A: NSObject {
            var flag: Bool = false
            var x: NSObject? = NSObject()
            var y: NSObject? = NSObject()
            var z: NSObject? = NSObject()
        }

        let a = A()
        let expected = a.y
        ReflectionPropertySetter().breakRetainCycle(in: a, nullifying: "y")

        #expect(a.y == nil)
        #expect(a.x != nil)
        #expect(a.z != nil)
        #expect(a.x !== expected)
    }

    @Test("Gracefully handle empty class")
    func emptyObject() {
        class A: NSObject {}

        customAssertionFailure = { _, _, _ in }
        let a = A()
        ReflectionPropertySetter().breakRetainCycle(in: a, nullifying: "anything") // should not crash
    }

}
