// LoopFollow
// RemoteCommandRefreshSession.swift

import Foundation

/// Read-only refreshes after a command. Never sends or retries a command.
/// Call on the same serial queue as the injected scheduler (main in the app).
final class RemoteCommandRefreshSession {
    private let source: () -> String
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void
    private let refresh: () -> Void
    private var generation = UUID()
    private var lastRefresh: Date?

    init(source: @escaping () -> String, now: @escaping () -> Date = Date.init,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void,
         refresh: @escaping () -> Void)
    {
        self.source = source
        self.now = now
        self.schedule = schedule
        self.refresh = refresh
    }

    func begin() {
        let selectedSource = source()
        guard !selectedSource.isEmpty else { return }
        generation = UUID()
        let current = generation
        let started = now()
        // Bounded, coalesced burst: ordinary polling resumes unchanged afterward.
        let delays: [TimeInterval] = [0, 3, 8, 15, 30, 60, 90, 120]
        for delay in delays {
            schedule(delay) { [weak self] in
                guard let self, self.generation == current, self.source() == selectedSource else { return }
                let time = self.now()
                let age = time.timeIntervalSince(started)
                guard (0 ... 125).contains(age),
                      self.lastRefresh.map({ time.timeIntervalSince($0) >= 2 }) ?? true else { return }
                // Suspended timers may all resume together: issue only one refresh.
                self.lastRefresh = time
                self.refresh()
            }
        }
    }
}
