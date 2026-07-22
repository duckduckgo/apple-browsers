import Foundation
import Combine

/// A fired telemetry pixel: the config name with the `_<platform>` suffix appended by the app-layer
/// wiring (out of scope for this package — see Global Constraints), plus its query parameters.
public struct FiredPixel: Equatable, Sendable {
    public let name: String
    public let parameters: [String: String]

    public init(name: String, parameters: [String: String]) {
        self.name = name
        self.parameters = parameters
    }
}

/// The EventHub runtime. Receives web events and browser-native signals, routes them to the configured
/// telemetry, maintains aggregation state and period windows, and fires telemetry pixels. Lifecycle and
/// navigation signals are delivered by the (out-of-scope) wiring layer, which calls these methods.
public protocol EventHubManaging: AnyObject {
    var firedPixelsPublisher: AnyPublisher<FiredPixel, Never> { get }

    /// Processes an incoming `webEvent` envelope (`{ "type": ..., "data": ... }`) from the tab
    /// identified by `tabID` against the active telemetry configs.
    func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID)

    /// Fires any enabled immediate-trigger telemetry whose `trigger.source` equals `type`. For
    /// browser-native events (not content-scope-scripts); there is no tab context.
    func handleImmediateEvent(_ type: String, data: Encodable?)

    /// Counts a browser-native event toward any enabled period/aggregated telemetry whose parameter
    /// `source` equals `type`. Unlike web events there is no per-tab dedup: each call is a genuine
    /// occurrence.
    func handleAggregatedEvent(_ type: String, data: Encodable?)

    /// Signals that the given tab has navigated to `url` (clears per-tab dedup on URL change).
    func onNavigationStarted(tabID: EventHubTabID, url: String)

    /// Signals that the given tab has closed (clears its per-tab dedup state).
    func onTabClosed(tabID: EventHubTabID)

    /// Notifies that the remote feature config (state and/or settings) has changed.
    func onConfigChanged()

    /// Returns whether the eventHub feature is currently enabled.
    func isEnabled() -> Bool

    /// Signals that the app has entered the foreground (catches up periods, re-arms timers).
    func onAppForegrounded()

    /// Signals that the app has entered the background (no new periods are started).
    func onAppBackgrounded()
}

public extension EventHubManaging {
    func handleImmediateEvent(_ type: String) { handleImmediateEvent(type, data: nil) }
    func handleAggregatedEvent(_ type: String) { handleAggregatedEvent(type, data: nil) }
}

/// Stub: every method is a no-op; `firedPixelsPublisher` never emits; `isEnabled()` always returns
/// `false`. Every manager test task (7–12) is expected to fail until a follow-up implementation task
/// fills these in.
public final class EventHub: EventHubManaging {
    private let repository: EventHubStore
    private let parser: EventHubConfigParsing
    private let settings: EventHubSettingsProviding
    private let clock: EventHubClock
    private let scheduler: EventHubScheduler
    private let subject = PassthroughSubject<FiredPixel, Never>()

    public var firedPixelsPublisher: AnyPublisher<FiredPixel, Never> { subject.eraseToAnyPublisher() }

    /// `internal`, not `public` — visible to `@testable import EventHub`, mirroring the Windows
    /// `internal IReadOnlyCollection<PixelState> ActivePixelStates` marker (exposed to tests only).
    var activePixelStates: [PixelState] { [] }

    public init(repository: EventHubStore, parser: EventHubConfigParsing, settings: EventHubSettingsProviding, clock: EventHubClock, scheduler: EventHubScheduler) {
        self.repository = repository
        self.parser = parser
        self.settings = settings
        self.clock = clock
        self.scheduler = scheduler
    }

    public func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID) {}
    public func handleImmediateEvent(_ type: String, data: Encodable?) {}
    public func handleAggregatedEvent(_ type: String, data: Encodable?) {}
    public func onNavigationStarted(tabID: EventHubTabID, url: String) {}
    public func onTabClosed(tabID: EventHubTabID) {}
    public func onConfigChanged() {}
    public func isEnabled() -> Bool { false }
    public func onAppForegrounded() {}
    public func onAppBackgrounded() {}
}
