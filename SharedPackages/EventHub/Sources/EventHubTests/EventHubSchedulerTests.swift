import Testing
@testable import EventHub

@Suite("ManualEventHubScheduler")
struct EventHubSchedulerTests {
    @Test("fires the armed action once the deadline is reached")
    func firesArmedActionOnceDeadlineReached() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var fired = false
        scheduler.arm(atMillis: 1000) { fired = true }
        scheduler.advance(by: 0.5)
        #expect(!fired)
        scheduler.advance(by: 0.5)
        #expect(fired)
    }

    @Test("re-arming replaces the previously armed action")
    func rearmingReplacesPreviousAction() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var firstFired = false
        var secondFired = false
        scheduler.arm(atMillis: 1000) { firstFired = true }
        scheduler.arm(atMillis: 2000) { secondFired = true }
        scheduler.advance(by: 1.5)
        #expect(!firstFired)
        #expect(!secondFired)
        scheduler.advance(by: 1)
        #expect(!firstFired)
        #expect(secondFired)
    }

    @Test("arming nil cancels without arming a new action")
    func armingNilCancels() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var fired = false
        scheduler.arm(atMillis: 1000) { fired = true }
        scheduler.arm(atMillis: nil) {}
        scheduler.advance(by: 2)
        #expect(!fired)
    }

    @Test("an action that re-arms another already-due action fires it within the same advance")
    func reentrantRearmFiresWithinSameAdvance() {
        let scheduler = ManualEventHubScheduler(startMillis: 0)
        var secondFired = false
        scheduler.arm(atMillis: 1000) {
            scheduler.arm(atMillis: 1000) { secondFired = true }
        }
        scheduler.advance(by: 1)
        #expect(secondFired)
    }
}
