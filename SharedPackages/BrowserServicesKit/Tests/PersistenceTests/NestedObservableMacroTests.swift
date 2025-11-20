//
//  NestedObservableMacroTests.swift
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

import Combine
import Foundation
import Macros
import Testing

/// Tests for the @NestedObservable macro which forwards child ObservableObject changes to parent
final class NestedObservableMacroTests {

    class ChildModel: ObservableObject {
        @Published var value: Int = 0
    }

    class ParentModel: ObservableObject {
        @NestedObservable var child: ChildModel = ChildModel()
    }

    @Test("Nested observable forwards child changes")
    func forwardsChildChanges() {
        let parent = ParentModel()
        var parentChangeCount = 0
        let cancellable = parent.objectWillChange.sink { _ in
            parentChangeCount += 1
        }

        // Given - no changes yet
        #expect(parentChangeCount == 0)

        // When - child property changes
        parent.child.value = 42

        // Then - parent objectWillChange fires
        #expect(parentChangeCount == 1)

        cancellable.cancel()
    }

    @Test("Resubscribes on child replacement")
    func resubscribesOnChildReplacement() {
        let parent = ParentModel()
        var parentChangeCount = 0
        let cancellable = parent.objectWillChange.sink { _ in
            parentChangeCount += 1
        }

        // Given - initial state
        #expect(parentChangeCount == 0)

        // When - replace child
        let newChild = ChildModel()
        parent.child = newChild

        // Then - parent objectWillChange fired for replacement
        let countAfterReplacement = parentChangeCount
        #expect(countAfterReplacement >= 1)

        // When - new child property changes
        newChild.value = 100

        // Then - parent objectWillChange fires again
        #expect(parentChangeCount > countAfterReplacement)

        cancellable.cancel()
    }

    @Test("Old child changes do not propagate")
    func oldChildChangesDoNotPropagate() {
        let parent = ParentModel()
        let oldChild = parent.child
        var parentChangeCount = 0

        // Given - replace child
        parent.child = ChildModel()

        let cancellable = parent.objectWillChange.sink { _ in
            parentChangeCount += 1
        }

        // When - old child changes
        oldChild.value = 999

        // Then - parent does NOT receive notification
        #expect(parentChangeCount == 0)

        // When - new child changes
        parent.child.value = 42

        // Then - parent DOES receive notification
        #expect(parentChangeCount == 1)

        cancellable.cancel()
    }

    @Test("Multiple nested observables work independently")
    func multipleChildren() {
        class ParentWithMultipleChildren: ObservableObject {
            @NestedObservable var child1: ChildModel = ChildModel()
            @NestedObservable var child2: ChildModel = ChildModel()
        }

        let parent = ParentWithMultipleChildren()
        var parentChangeCount = 0
        let cancellable = parent.objectWillChange.sink { _ in
            parentChangeCount += 1
        }

        // When - first child changes
        parent.child1.value = 1
        #expect(parentChangeCount == 1)

        // When - second child changes
        parent.child2.value = 2
        #expect(parentChangeCount == 2)

        // When - first child changes again
        parent.child1.value = 3
        #expect(parentChangeCount == 3)

        cancellable.cancel()
    }
}
