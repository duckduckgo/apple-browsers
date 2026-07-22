import Combine

/// Declares that a set of EventHub telemetry configs are gated behind a user-consent decision. Owning
/// features (which know both their config names and their consent state) implement one of these;
/// EventHub itself stays consent-agnostic and only removes the named configs while consent is withheld.
// TODO(eventhub): This mirrors Windows' IEventHubConsentRequirement design (one requirement per
// consent-gated metric group, combined via combineLatest). Not yet confirmed as the final Apple
// approach — review before this ships. See the requester's note when this file was written
// (2026-07-22): "keep it in tests for now, but I am not sure if I will follow the same path as on
// Windows."
public protocol EventHubConsentRequirement {
    /// Stable identifier for the consent group (e.g. `"adBlockV2Telemetry"`).
    var consentID: String { get }

    /// The EventHub telemetry config names this consent gates (the `telemetry` map keys).
    var configNames: Set<String> { get }

    /// Live consent state. Re-emits whenever the grant changes so EventHub re-filters its config.
    /// Implementations MUST emit an initial value on subscribe (e.g. back it with a
    /// `CurrentValueSubject`): EventHub combines every requirement with `combineLatest`, so a
    /// requirement that never seeds a value would stall telemetry filtering for every feature.
    var isGrantedPublisher: AnyPublisher<Bool, Never> { get }
}
