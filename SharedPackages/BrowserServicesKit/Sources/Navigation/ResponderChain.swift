//
//  ResponderChain.swift
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

public struct ResponderChain {

    private var responderRefs: [any AnyResponderRef]

    public init(responderRefs: [any AnyResponderRef] = []) {
        self.responderRefs = responderRefs
    }

    public mutating func setResponders(_ refs: [ResponderRefMaker]) {
        dispatchPrecondition(condition: .onQueue(.main))

        let nonnullRefs = refs.compactMap { $0 }
        responderRefs = nonnullRefs.map(\.ref)
        assert(getResponders().count == nonnullRefs.count, "Some NavigationResponders were released right after adding: "
               + "\(Set(nonnullRefs.map(\.ref.responderType)).subtracting(getResponders().map { "\(type(of: $0))" }))")
    }

    public mutating func append(_ ref: ResponderRefMaker) {
        dispatchPrecondition(condition: .onQueue(.main))
        assert(ref.ref.responder != nil)

        responderRefs.append(ref.ref)
    }

    public mutating func prepend(_ ref: ResponderRefMaker) {
        dispatchPrecondition(condition: .onQueue(.main))
        assert(ref.ref.responder != nil)

        responderRefs.insert(ref.ref, at: 0)
    }

    public func getResponders() -> [NavigationResponder] {
        return responderRefs.compactMap(\.responder)
    }

}

extension ResponderChain: Sequence {

    public struct Iterator: IteratorProtocol {
        private var iterator: Array<any AnyResponderRef>.Iterator

        fileprivate init(refs: [any AnyResponderRef]) {
            self.iterator = refs.makeIterator()
        }

        public mutating func next() -> NavigationResponder? {
            while let ref = iterator.next() {
                if let responder = ref.responder {
                    return responder
                }
            }
            return nil
        }
    }

    public var underestimatedCount: Int {
        responderRefs.count
    }

    public func makeIterator() -> Iterator {
        Iterator(refs: responderRefs)
    }

}

public enum ResponderRef: AnyResponderRef {
    case weak(getter: () -> NavigationResponder?, type: NavigationResponder.Type)
    case strong(NavigationResponder)

    public var responder: NavigationResponder? {
        switch self {
        case .weak(getter: let getter, type: _): return getter()
        case .strong(let responder): return responder
        }
    }

    public var responderType: String {
        switch self {
        case .weak(getter: _, type: let type): return "\(type)"
        case .strong(let responder): return "\(type(of: responder))"
        }
    }

}

public struct ResponderRefMaker {
    internal let ref: AnyResponderRef
    private init(_ ref: AnyResponderRef) {
        self.ref = ref
    }
    public static func `weak`(_ responder: (some NavigationResponder & AnyObject)) -> ResponderRefMaker {
        return .init(ResponderRef.weak(getter: { [weak responder] in responder }, type: type(of: responder)))
    }
    public static func `weak`(nullable responder: (any NavigationResponder & AnyObject)?) -> ResponderRefMaker? {
        guard let responder = responder else { return nil }
        return .init(ResponderRef.weak(getter: { [weak responder] in responder }, type: type(of: responder)))
    }
    public static func `strong`(_ responder: any NavigationResponder & AnyObject) -> ResponderRefMaker {
        return .init(ResponderRef.strong(responder))
    }
    public static func `strong`(nullable responder: (any NavigationResponder & AnyObject)?) -> ResponderRefMaker? {
        guard let responder = responder else { return nil }
        return .init(ResponderRef.strong(responder))
    }
    public static func `struct`(_ responder: some NavigationResponder) -> ResponderRefMaker {
        assert(Mirror(reflecting: responder).displayStyle == .struct, "\(type(of: responder)) is not a struct")
        return .init(ResponderRef.strong(responder))
    }
    public static func `struct`(nullable responder: (some NavigationResponder)?) -> ResponderRefMaker? {
        guard let responder = responder else { return nil }
        return .struct(responder)
    }

}

public protocol AnyResponderRef {
    var responder: NavigationResponder? { get }
    var responderType: String { get }
}
