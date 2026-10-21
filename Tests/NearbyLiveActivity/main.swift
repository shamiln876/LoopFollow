import Foundation

let now = Date(timeIntervalSince1970: 10000)
let packet = NearbyPacket(generatedAt: 9990, glucoseDate: 9980, glucoseMgdl: 180, deltaMgdl: 9, iob: 2, iobDate: 9970, cob: 15, cobDate: 9960)
func cloud(_ date: Double) -> GlucoseSnapshot {
    GlucoseSnapshot(glucose: 90, delta: -2, trend: .down, updatedAt: Date(timeIntervalSince1970: date), iob: 8, cob: 90, projected: 60, recBolus: 3, unit: .mmol, isNotLooping: true)
}
func select(_ cloud: GlucoseSnapshot?, _ enabled: Bool = true, _ date: Date = now) -> GlucoseSnapshot? {
    NearbyLiveActivitySnapshot.select(cloud: cloud, packet: packet, enabled: enabled, unit: .mmol, now: date)
}
let local = select(cloud(9900))!
precondition(local.glucose == 180 && local.updatedAt.timeIntervalSince1970 == 9980)
precondition(local.iob == 2 && local.cob == 15 && local.projected == nil && local.recBolus == nil)
precondition(local.trend == .unknown && !local.isNotLooping)
precondition(local.nearbyExpiresAt == 10320)
precondition(select(cloud(9990)) == cloud(9990))
precondition(select(cloud(9980))?.glucose == 180)
precondition(select(cloud(9900), false) == cloud(9900))
precondition(select(nil)?.glucose == 180)
let stale = select(cloud(9900), true, Date(timeIntervalSince1970: 11000))!
precondition(stale.iob == nil && stale.cob == nil && stale.updatedAt == local.updatedAt)
precondition(stale.nearbyExpiresAt! < 11000)
let roundTrip = try JSONDecoder().decode(GlucoseSnapshot.self, from: JSONEncoder().encode(local))
precondition(roundTrip == local)
precondition(local.withRenewalOverlay(true).nearbyExpiresAt == local.nearbyExpiresAt)
print("PASS: nearby Live Activity selection, original timestamps, expiry, metric isolation, fallback and serialization")
