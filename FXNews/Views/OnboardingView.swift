import SwiftUI
import UserNotifications

@MainActor
struct OnboardingView: View {
    @Bindable var preferences: UserPreferences
    @Bindable var navigationState: AppNavigationState
    let onFinish: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var step: OnboardingStep = .welcome
    @State private var selectedPairs: Set<String> = []
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaultPairs: Set<String> = ["EURUSD", "GBPUSD", "USDJPY"]

    var body: some View {
        ZStack {
            FXNewsBackground()

            FXNewsScreen {
                VStack(alignment: .leading, spacing: 18) {
                    progressHeader

                    switch step {
                    case .welcome:
                        welcomeStep
                    case .pairs:
                        pairsStep
                    case .notifications:
                        notificationsStep
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            if selectedPairs.isEmpty {
                if preferences.watchedPairSymbols.isEmpty {
                    selectedPairs = defaultPairs
                } else {
                    selectedPairs = Set(preferences.watchedPairSymbols)
                }
            }
        }
        .task {
            await refreshNotificationAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await refreshNotificationAuthorizationStatus()
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FX News")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(FXNewsPalette.muted)
                Spacer()
                Text("\(step.rawValue)/3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.muted)
            }

            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { currentStep in
                    Capsule(style: .continuous)
                        .fill(currentStep.rawValue <= step.rawValue ? FXNewsPalette.accent : FXNewsPalette.surfaceStrong)
                        .frame(height: 6)
                }
            }
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)

            Text("FX News")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)

            Text("Your market week, at a glance.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)

            Text("Stay ahead of market-moving events with a calendar built for active traders.")
                .font(.headline)
                .foregroundStyle(FXNewsPalette.muted)

            Spacer()

            primaryButton(title: "Get Started") {
                FXNewsHaptics.selection()
                step = .pairs
            }
        }
    }

    private var pairsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which pairs do you follow?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)

            Text("Choose the pairs you want FX News to prioritize. You can change this anytime.")
                .font(.subheadline)
                .foregroundStyle(FXNewsPalette.muted)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(PairCatalogCategory.allCases) { category in
                        FXNewsCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(category.title)
                                    .font(.headline)
                                    .foregroundStyle(FXNewsPalette.text)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                                    ForEach(category.pairs) { pair in
                                        Button {
                                            togglePair(pair.symbol)
                                        } label: {
                                            PairSelectionChip(
                                                pair: pair,
                                                isSelected: selectedPairs.contains(pair.symbol),
                                                hasEvents: false
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            primaryButton(title: "Continue") {
                preferences.watchedPairSymbols = selectedPairs.sorted()
                FXNewsHaptics.selection()
                step = .notifications
            }
        }
    }

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)

            Text("Stay ready for key events")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)

            Text("Turn on alerts to get a heads-up before high-impact events.")
                .font(.headline)
                .foregroundStyle(FXNewsPalette.muted)

            FXNewsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notification access")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Text(notificationStatusCopy)
                        .font(.subheadline)
                        .foregroundStyle(FXNewsPalette.muted)
                }
            }

            Spacer()

            primaryButton(title: primaryNotificationButtonTitle) {
                Task {
                    await handlePrimaryNotificationAction()
                }
            }

            Button {
                finishOnboarding()
            } label: {
                Text("Set Up Later")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
    }

    private func primaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(FXNewsPalette.accent)
                )
        }
        .buttonStyle(.plain)
    }

    private func togglePair(_ symbol: String) {
        if selectedPairs.contains(symbol) {
            selectedPairs.remove(symbol)
        } else {
            selectedPairs.insert(symbol)
        }
        FXNewsHaptics.selection()
    }

    private func finishOnboarding() {
        if selectedPairs.isEmpty {
            selectedPairs = defaultPairs
            preferences.watchedPairSymbols = defaultPairs.sorted()
        }

        preferences.showOnlyWatchedPairs = true
        preferences.hasCompletedOnboarding = true
        navigationState.selectedTab = .calendar
        FXNewsHaptics.success()
        onFinish()
    }

    private func handlePrimaryNotificationAction() async {
        switch notificationAuthorizationStatus {
        case .denied:
            NotificationAuthorizationStore.openSystemSettings()
        case .authorized, .provisional, .ephemeral:
            finishOnboarding()
        case .notDetermined:
            _ = try? await NotificationAuthorizationStore.requestAuthorizationIfNeeded()
            await refreshNotificationAuthorizationStatus()
            finishOnboarding()
        @unknown default:
            finishOnboarding()
        }
    }

    private func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await NotificationAuthorizationStore.authorizationStatus()
    }

    private var primaryNotificationButtonTitle: String {
        switch notificationAuthorizationStatus {
        case .denied:
            "Open Settings"
        case .authorized, .provisional, .ephemeral:
            "Continue"
        case .notDetermined:
            "Enable Notifications"
        @unknown default:
            "Continue"
        }
    }

    private var notificationStatusCopy: String {
        switch notificationAuthorizationStatus {
        case .denied:
            "Notifications are turned off for FX News. Open Settings to allow alerts, then come back to finish setup."
        case .authorized, .provisional, .ephemeral:
            "FX News can send alerts on this device."
        case .notDetermined:
            "FX News will ask for notification permission when you continue."
        @unknown default:
            "FX News will check your notification access when you continue."
        }
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 1
    case pairs = 2
    case notifications = 3
}

#Preview {
    OnboardingView(
        preferences: UserPreferences(),
        navigationState: AppNavigationState.shared
    ) {}
}
