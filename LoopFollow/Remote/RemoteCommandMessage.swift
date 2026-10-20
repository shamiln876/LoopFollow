// LoopFollow
// RemoteCommandMessage.swift

import Foundation

enum RemoteCommandMessage {
    static let sent = "Remote command sent. Waiting for Trio's result; refreshing status automatically."
}

enum RemoteCommandRefresh {
    private static let session = RemoteCommandRefreshSession(
        source: { Storage.shared.url.value },
        schedule: { delay, action in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action) },
        refresh: {
            let now = Date()
            TaskScheduler.shared.rescheduleTask(id: .treatments, to: now)
            TaskScheduler.shared.rescheduleTask(id: .deviceStatus, to: now)
        }
    )

    static func commandAccepted() {
        DispatchQueue.main.async { session.begin() }
    }

    static func receivedResponse(_ userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["command_type"] as? String, TRCCommandType(rawValue: type) != nil,
              let status = userInfo["command_status"] as? String, ["success", "failed"].contains(status) else { return }
        // An "Initiating bolus" response is not proof of delivery. Fetch the
        // actual uploaded data; never insert a synthetic bolus/target locally.
        commandAccepted()
    }
}
