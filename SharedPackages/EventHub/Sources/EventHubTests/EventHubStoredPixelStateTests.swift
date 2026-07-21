import Testing
import Foundation
@testable import EventHub

@Suite("EventHubStoredPixelState")
struct EventHubStoredPixelStateTests {
    @Test("round trips all fields")
    func roundTripsAllFields() throws {
        let original = EventHubStoredPixelState(
            periodStartMillis: 1_700_000_000_000,
            periodEndMillis: 1_700_000_086_400,
            paramsJSON: "{\"count\":3}",
            configJSON: "{\"name\":\"testPixel\"}")

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(EventHubStoredPixelState.self, from: data)

        #expect(restored == original)
    }

    @Test("round trips the stored map shape")
    func roundTripsTheStoredMapShape() throws {
        let original: [String: EventHubStoredPixelState] = [
            "pixelA": EventHubStoredPixelState(periodStartMillis: 0, periodEndMillis: 100, paramsJSON: "{}", configJSON: "{\"name\":\"pixelA\"}"),
            "pixelB": EventHubStoredPixelState(periodStartMillis: 100, periodEndMillis: 200, paramsJSON: "{\"count\":5}", configJSON: "{\"name\":\"pixelB\"}"),
        ]

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode([String: EventHubStoredPixelState].self, from: data)

        #expect(restored == original)
    }
}
