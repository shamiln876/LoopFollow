// LoopFollow
// RemoteCommandRefreshSessionTests.swift

import Foundation
@testable import LoopFollow
import Testing

struct RemoteCommandRefreshSessionTests {
    private final class Harness {
        var time = Date(timeIntervalSince1970: 1_800_000_000)
        var source = "source-a"
        var work: [(TimeInterval, () -> Void)] = []
        var refreshes = 0

        lazy var session = RemoteCommandRefreshSession(
            source: { self.source }, now: { self.time },
            schedule: { self.work.append(($0, $1)) },
            refresh: { self.refreshes += 1 }
        )

        func runDue(after seconds: TimeInterval) {
            time = Date(timeIntervalSince1970: 1_800_000_000 + seconds)
            let due = work.filter { $0.0 <= seconds }
            work.removeAll { $0.0 <= seconds }
            for (_, action) in due { action() }
        }
    }

    @Test func repeatedResponsesCoalesceInsteadOfMultiplyingRequests() {
        let h = Harness()
        h.session.begin()
        h.session.begin()
        h.runDue(after: 0)
        #expect(h.refreshes == 1)
        h.runDue(after: 3)
        #expect(h.refreshes == 2)
    }

    @Test func oldSourceCallbacksCannotRefreshAnotherConnection() {
        let h = Harness()
        h.session.begin()
        h.source = "source-b"
        h.runDue(after: 30)
        #expect(h.refreshes == 0)
    }

    @Test func suspendedTimersDoNotProduceACatchUpRequestStorm() {
        let h = Harness()
        h.session.begin()
        h.runDue(after: 90)
        #expect(h.refreshes == 1)
        h.runDue(after: 126)
        #expect(h.refreshes == 1)
    }

    @Test func emptySourceAndExpiredWorkDoNotFetch() {
        let h = Harness()
        h.source = ""
        h.session.begin()
        #expect(h.work.isEmpty)
        h.source = "source-a"
        h.session.begin()
        h.runDue(after: 300)
        #expect(h.refreshes == 0)
    }
}
