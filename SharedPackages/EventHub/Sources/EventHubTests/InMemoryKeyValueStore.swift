import Foundation
import Persistence

/// A simple in-memory `KeyValueStoring` for EventHub tests. Holds values by reference (through
/// `set(_:forKey:)`'s `Any?`), and tracks `setCallCount` so persistence-throttling tests can assert
/// that writes are coalesced rather than performed per event.
final class InMemoryKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    private(set) var setCallCount = 0

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        setCallCount += 1
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}
