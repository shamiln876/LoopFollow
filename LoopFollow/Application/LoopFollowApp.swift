// LoopFollow
// LoopFollowApp.swift

import SwiftUI

@main
struct LoopFollowApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @ObservedObject private var storageReady = StorageReadiness.ready

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
                if SmartMealUITestFixture.enabled {
                    SmartMealUITestFixture()
                } else {
                    appContent
                }
            #else
                appContent
            #endif
        }
    }

    @ViewBuilder private var appContent: some View {
        // Gate the UI on storage readiness so nothing (bootstrap, telemetry
        // consent, onboarding) is built against a poisoned cache. True
        // synchronously on a normal launch; only false briefly while a BFU
        // background launch is foregrounded mid-hydration.
        if storageReady.value {
            MainTabView()
                .onAppear { MealReviewSettingsImport.consumePending() }
                .onOpenURL { url in
                    guard url.scheme == AppGroupID.urlScheme, url.host == "la-tap" else { return }
                    #if !targetEnvironment(macCatalyst)
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .liveActivityDidForeground, object: nil)
                        }
                    #endif
                }
        } else {
            StorageLoadingView()
        }
    }
}
