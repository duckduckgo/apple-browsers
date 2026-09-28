//
//  UserDefaults+KeyValueStoring.swift
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

extension UserDefaults: KeyValueStoring { }

extension UserDefaults: @retroactive ObservableObject, ObservableKeyValueStoring, ObservableThrowingKeyValueStoring {
    /// Creates a publisher that observes a UserDefaults key using KVO
    ///
    /// - Parameter key: The UserDefaults key to observe
    /// - Returns: A publisher that emits Void when the value changes after subscription
    ///
    /// - Note: The publisher only emits on changes after subscription, not the current value on subscription.
    /// - Note: Dotted keys are supported and with fall back to NotificationCenter-based `UserDefaults.didChangeNotification` observation.
    public func updatesPublisher(forKey key: String) -> AnyPublisher<Void, Never> {
        if !key.contains(".") {
            let publisher: UserDefaultsObservingPublisher<Void> = UserDefaultsObservingPublisher<Void>(observed: self, keyPath: key, options: [])
            return publisher.eraseToAnyPublisher()
        }
        // Fallback to NotificationCenter for dotted keys
        // Track previous value to only emit on actual changes
        var previousValue = self.object(forKey: key)

        return NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: self)
            .compactMap { [weak self] _ -> Void? in
                guard let self = self else { return nil }

                let currentValue = self.object(forKey: key)

                // Compare values to see if this key actually changed
                let hasChanged: Bool
                if let current = currentValue, let previous = previousValue {
                    // Both exist - compare them
                    hasChanged = !areEqual(current, previous)
                } else {
                    // One is nil - changed if they're different
                    hasChanged = (currentValue != nil) != (previousValue != nil)
                }

                previousValue = currentValue

                return hasChanged ? () : nil
            }
            .eraseToAnyPublisher()
    }

    /// Compares two Any values for equality
    private func areEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        func compare<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool {
            guard let rhsValue = rhs as? T else { return false }
            return lhs == rhsValue
        }

        guard let lhsEquatable = lhs as? (any Equatable) else { return false }
        return compare(lhsEquatable, rhs)
    }
}

/// Publisher that observes UserDefaults keys using KVO
private struct UserDefaultsObservingPublisher<Value>: Publisher {
    typealias Output = Value
    typealias Failure = Never

    let observed: UserDefaults
    let keyPath: String
    let options: NSKeyValueObservingOptions

    func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, S.Input == Value {
        let subscription = Subscription(subscriber: subscriber, observed: observed, keyPath: keyPath, options: options)
        subscriber.receive(subscription: subscription)
    }

    private final class Subscription<S: Subscriber>: NSObject, Combine.Subscription where S.Input == Value, S.Failure == Never {
        private var subscriber: S?
        private weak var observed: UserDefaults?
        private let keyPath: String

        init(subscriber: S, observed: UserDefaults, keyPath: String, options: NSKeyValueObservingOptions) {
            self.subscriber = subscriber
            self.observed = observed
            self.keyPath = keyPath
            super.init()

            // Add KVO observation for the specific key
            observed.addObserver(self, forKeyPath: keyPath, options: options, context: nil)
        }

        override func observeValue(forKeyPath keyPath: String?,
                                   of object: Any?,
                                   change: [NSKeyValueChangeKey: Any]?,
                                   context: UnsafeMutableRawPointer?) {
            guard let subscriber, let keyPath, let defaults = observed else { return }

            let receiveValue: (Value) -> Subscribers.Demand = subscriber.receive
            if let receiveValue = receiveValue as? ((()) -> Subscribers.Demand) {
                _ = receiveValue( () )
            } else if let value = defaults.object(forKey: keyPath) as? Value {
                _ = subscriber.receive(value)
            }
        }

        func request(_ demand: Subscribers.Demand) {
            // Ignored - we push values as they change
        }

        func cancel() {
            if let observed = observed {
                observed.removeObserver(self, forKeyPath: keyPath)
            }
            observed = nil
            subscriber = nil
        }

        deinit {
            cancel()
        }
    }
}
