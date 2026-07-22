import Foundation
import Combine

/// The EventHub view of remote config: feature enablement plus the telemetry settings JSON with any
/// consent-gated entries already removed. EventHub consumes this instead of talking to remote config or
/// consent directly, keeping the manager consent-agnostic.
public protocol EventHubSettingsProviding {
    var enabledPublisher: AnyPublisher<Bool, Never> { get }
    var settingsPublisher: AnyPublisher<Data?, Never> { get }
}

/// Combines the raw feature settings with the live consent state of every `EventHubConsentRequirement`,
/// removing the `telemetry` entries for any consent group that is not currently granted.
public final class EventHubSettings: EventHubSettingsProviding {
    private static let telemetryKey = "telemetry"

    public let enabledPublisher: AnyPublisher<Bool, Never>
    public let settingsPublisher: AnyPublisher<Data?, Never>

    public init(
        featureEnabledPublisher: AnyPublisher<Bool, Never>,
        featureSettingsPublisher: AnyPublisher<Data?, Never>,
        consentRequirements: [EventHubConsentRequirement]
    ) {
        self.enabledPublisher = featureEnabledPublisher
        self.settingsPublisher = Publishers.CombineLatest(featureSettingsPublisher, Self.suppressedNames(consentRequirements))
            .map(Self.strip)
            .eraseToAnyPublisher()
    }

    private static func suppressedNames(_ requirements: [EventHubConsentRequirement]) -> AnyPublisher<Set<String>, Never> {
        guard !requirements.isEmpty else {
            return Just(Set<String>()).eraseToAnyPublisher()
        }
        let perRequirement = requirements.map { requirement in
            requirement.isGrantedPublisher.map { (requirement.configNames, $0) }.eraseToAnyPublisher()
        }
        let combined = perRequirement.dropFirst().reduce(perRequirement[0].map { [$0] }.eraseToAnyPublisher()) { accumulated, next in
            accumulated.combineLatest(next).map { $0 + [$1] }.eraseToAnyPublisher()
        }
        return combined
            .map { states in Set(states.filter { !$0.1 }.flatMap(\.0)) }
            .eraseToAnyPublisher()
    }

    private static func strip(_ settings: Data?, suppressed: Set<String>) -> Data? {
        guard !suppressed.isEmpty, let settings else { return settings }
        do {
            // Fail closed: if we cannot verify the settings JSON shape when suppressed is non-empty,
            // expose no telemetry at all rather than risk collecting without consent.
            guard var object = try JSONSerialization.jsonObject(with: settings) as? [String: Any],
                  var telemetry = object[telemetryKey] as? [String: Any] else {
                return nil
            }
            for name in suppressed { telemetry.removeValue(forKey: name) }
            object[telemetryKey] = telemetry
            return try JSONSerialization.data(withJSONObject: object)
        } catch {
            // Fail closed: if we cannot reliably strip a gated entry, expose no telemetry at all
            // rather than risk collecting without consent.
            return nil
        }
    }
}
