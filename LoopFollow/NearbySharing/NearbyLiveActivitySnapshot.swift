// LoopFollow
// NearbyLiveActivitySnapshot.swift

import Foundation

/// Uses the newest glucose source, preferring authenticated local data on ties.
/// Never combines nearby glucose with unrelated or older cloud therapy metrics.
enum NearbyLiveActivitySnapshot {
    static func select(cloud: GlucoseSnapshot?, packet: NearbyPacket?, enabled: Bool, unit: GlucoseSnapshot.Unit, now: Date) -> GlucoseSnapshot? {
        guard enabled, let packet,
              cloud.map({ packet.glucoseDate >= $0.updatedAt.timeIntervalSince1970 }) ?? true
        else { return cloud }
        let time = now.timeIntervalSince1970
        func fresh(_ date: Double?) -> Bool {
            guard let date else { return false }
            return date <= time + 60 && time - date < 360
        }
        let iob = fresh(packet.iobDate) ? packet.iob : nil
        let cob = fresh(packet.cobDate) ? packet.cob : nil
        var dates = [packet.glucoseDate, packet.generatedAt]
        if iob != nil, let date = packet.iobDate { dates.append(date) }
        if cob != nil, let date = packet.cobDate { dates.append(date) }
        return GlucoseSnapshot(
            glucose: Double(packet.glucoseMgdl), delta: Double(packet.deltaMgdl ?? 0),
            trend: .unknown, updatedAt: Date(timeIntervalSince1970: packet.glucoseDate),
            iob: iob, cob: cob, projected: nil, unit: unit, isNotLooping: false,
            showRenewalOverlay: cloud?.showRenewalOverlay ?? false,
            nearbyExpiresAt: (dates.min() ?? packet.glucoseDate) + 360,
        )
    }
}
