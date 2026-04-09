import SwiftUI

struct RootShellView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            if settings.onboardingCompleted {
                SettingsRootView()
            } else {
                OnboardingView()
            }
        }
    }
}
