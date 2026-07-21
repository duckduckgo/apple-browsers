import Foundation
import Combine

/// The EventHub view of remote config: feature enablement plus the telemetry settings JSON with any
/// consent-gated entries already removed. EventHub consumes this instead of talking to remote config or
/// consent directly, keeping the manager consent-agnostic.
public protocol EventHubSettingsProviding {
    var enabledPublisher: AnyPublisher<Bool, Never> { get }
    var settingsPublisher: AnyPublisher<Data?, Never> { get }
}

/// Stub: `settingsPublisher` passes the raw feature settings straight through, performing no consent
/// stripping. `EventHubSettingsTests` is expected to fail until a follow-up implementation task fills
/// this in.
public final class EventHubSettings: EventHubSettingsProviding {
    public let enabledPublisher: AnyPublisher<Bool, Never>
    public let settingsPublisher: AnyPublisher<Data?, Never>

    public init(
        featureEnabledPublisher: AnyPublisher<Bool, Never>,
        featureSettingsPublisher: AnyPublisher<Data?, Never>,
        consentRequirements: [EventHubConsentRequirement]
    ) {
        self.enabledPublisher = featureEnabledPublisher
        self.settingsPublisher = featureSettingsPublisher
    }
}
