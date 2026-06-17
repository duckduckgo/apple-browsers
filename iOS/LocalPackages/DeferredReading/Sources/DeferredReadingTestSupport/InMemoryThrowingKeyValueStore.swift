import Foundation
import Persistence

public final class InMemoryThrowingKeyValueStore: ThrowingKeyValueStoring {
    private var storage: [String: Any] = [:]

    public init() {}

    public func object(forKey key: String) throws -> Any? {
        storage[key]
    }

    public func set(_ value: Any?, forKey key: String) throws {
        storage[key] = value
    }

    public func removeObject(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }
}
