import Foundation
import Persistence

/// Persists per-pixel EventHub runtime state across app restarts. State survives the fire button and
/// is only cleared by EventHub itself (period fire, config disable). Backed by the key-value store.
public protocol EventHubRepository {
    /// Returns the persisted state for the named pixel, or `nil` if absent or corrupt.
    func pixelState(named name: String) -> PixelState?

    /// Returns all persisted pixel states, skipping any whose stored config cannot be parsed.
    func allPixelStates() -> [PixelState]

    /// Persists (inserts or replaces) the state for a pixel.
    func savePixelState(_ state: PixelState)

    /// Removes the persisted state for the named pixel, if any.
    func deletePixelState(named name: String)

    /// Removes all persisted pixel state.
    func deleteAllPixelStates()
}

/// Stub: every method is a no-op / always-miss. `EventHubRepositoryTests` is expected to fail until a
/// follow-up implementation task fills these in.
public final class EventHubKeyValueRepository: EventHubRepository {
    /// The single key under which the map of pixel-name to `EventHubStoredPixelState` is stored.
    public static let storageKey = "eventhub_pixel_states"

    private let store: KeyValueStoring
    private let parser: EventHubConfigParsing

    public init(store: KeyValueStoring, parser: EventHubConfigParsing) {
        self.store = store
        self.parser = parser
    }

    public func pixelState(named name: String) -> PixelState? {
        nil
    }

    public func allPixelStates() -> [PixelState] {
        []
    }

    public func savePixelState(_ state: PixelState) {
        // no-op
    }

    public func deletePixelState(named name: String) {
        // no-op
    }

    public func deleteAllPixelStates() {
        // no-op
    }
}
