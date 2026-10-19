// LoopFollow
// TrioRemoteControlView.swift

import SwiftUI

struct TrioRemoteControlView: View {
    @ObservedObject var viewModel: TrioRemoteControlViewModel
    @ObservedObject private var activeOverrideNote = Observable.shared.override
    @ObservedObject private var activeTempTarget = Observable.shared.tempTarget
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("remoteUnverifiedCommandKind") private var unverifiedCommandKind = ""
    @AppStorage("remoteUnverifiedCommandAt") private var unverifiedCommandAt = 0.0

    var body: some View {
        NavigationView {
            VStack {
                let columns = [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    CommandButtonView(command: "Meal", iconName: "fork.knife", destination: MealView())
                    CommandButtonView(command: "Bolus", iconName: "syringe", destination: BolusView())
                    CommandButtonView(command: "Temp Target", iconName: "scope", destination: TempTargetView(), isActive: activeTempTarget.value != nil)
                    CommandButtonView(command: "Overrides", iconName: "slider.horizontal.3", destination: OverrideView(), isActive: activeOverrideNote.value != nil)
                }
                .padding(.horizontal)

                if unverifiedCommandAt > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("REMOTE DELIVERY NOT VERIFIED", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text("\(unverifiedCommandKind.capitalized) request at \(Date(timeIntervalSince1970: unverifiedCommandAt).formatted(date: .omitted, time: .shortened)).")
                        Text("Apple accepting a push does not prove Trio received it, that carbs were stored, or that insulin was delivered. Verify actual Trio pump/meal history before relying on or repeating this request.")
                            .font(.footnote)
                        Button("I've checked actual Trio history — dismiss") {
                            unverifiedCommandAt = 0
                            unverifiedCommandKind = ""
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                Spacer()
            }
            .navigationBarTitle("Trio Remote Control", displayMode: .inline)
        }
    }
}

struct CommandButtonView<Destination: View>: View {
    let command: String
    let iconName: String
    let destination: Destination
    /// Lights the button up with a glow while the corresponding override /
    /// temp target is active.
    var isActive: Bool = false

    var body: some View {
        NavigationLink(destination: destination) {
            VStack {
                Image(systemName: iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                Text(command)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green, lineWidth: 2.5)
                }
            }
            .shadow(color: isActive ? Color.green.opacity(0.7) : .clear, radius: isActive ? 9 : 0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Local reminder only. Never interpret this as proof that a remote command was
// executed. It remains visible until the caregiver checks the actual history.
// This does not replace authenticated receiver/pump-history acknowledgment.
enum RemoteDeliveryUnverified {
    static func record(kind: String) {
        UserDefaults.standard.set(kind, forKey: "remoteUnverifiedCommandKind")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "remoteUnverifiedCommandAt")
    }
}
