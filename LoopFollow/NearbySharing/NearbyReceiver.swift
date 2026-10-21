import SwiftUI

enum NearbyReceiver {
    static let shared = NearbyBluetooth(sender: false)
}

struct NearbyReceiverView: View {
    @State private var scanning = false
    var body: some View {
        NearbySharingView(link: NearbyReceiver.shared, scan: { scanning = true })
            .sheet(isPresented: $scanning) {
                SimpleQRCodeScannerView { result in
                    scanning = false
                    if case let .success(code) = result { NearbyReceiver.shared.pair(code) }
                }
            }
    }
}
