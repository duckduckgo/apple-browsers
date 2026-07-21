import Testing
import Foundation
import Combine
@testable import EventHub

@Suite("EventHubSettings")
struct EventHubSettingsTests {
    static let json = """
    { "telemetry": {
        "gated_pixel":   { "state": "enabled", "trigger": { "type": "period", "period": { "seconds": 60 } } },
        "ungated_pixel": { "state": "enabled", "trigger": { "type": "period", "period": { "seconds": 60 } } }
    } }
    """.data(using: .utf8)!

    private static func telemetryKeys(_ settings: Data?) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: settings ?? Data()) as? [String: Any]
        let telemetry = object?["telemetry"] as? [String: Any] ?? [:]
        return telemetry.keys.sorted()
    }

    private final class FakeConsentRequirement: EventHubConsentRequirement {
        let consentID = "test"
        let configNames: Set<String> = ["gated_pixel"]
        let granted = CurrentValueSubject<Bool, Never>(false)
        var isGrantedPublisher: AnyPublisher<Bool, Never> { granted.eraseToAnyPublisher() }
    }

    @Test("removes the gated config while consent is withheld")
    func removesGatedConfigWhileConsentIsWithheld() throws {
        let requirement = FakeConsentRequirement()
        let subject = EventHubSettings(
            featureEnabledPublisher: Just(true).eraseToAnyPublisher(),
            featureSettingsPublisher: Just(Self.json as Data?).eraseToAnyPublisher(),
            consentRequirements: [requirement])

        var latest: Data?
        let cancellable = subject.settingsPublisher.sink { latest = $0 }
        defer { cancellable.cancel() }

        #expect(try Self.telemetryKeys(latest) == ["ungated_pixel"])

        requirement.granted.send(true)
        #expect(try Self.telemetryKeys(latest) == ["gated_pixel", "ungated_pixel"])
    }
}
