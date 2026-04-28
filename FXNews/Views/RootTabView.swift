import SwiftUI

@MainActor
struct RootTabView: View {
    @State private var viewModel: CalendarViewModel
    @State private var preferences = UserPreferences()
    @Bindable private var navigationState = AppNavigationState.shared
    @State private var isShowingOnboarding = false

    init() {
        _viewModel = State(initialValue: CalendarViewModel(service: RemoteCalendarService()))
    }

    init(calendarService: CalendarService) {
        _viewModel = State(initialValue: CalendarViewModel(service: calendarService))
    }

    var body: some View {
        ZStack {
            FXNewsBackground()

            tabLayer(.calendar) {
                NavigationStack {
                    CalendarView(viewModel: viewModel, preferences: preferences)
                }
            }

            tabLayer(.pairs) {
                NavigationStack {
                    PairsPlaceholderView(viewModel: viewModel, preferences: preferences)
                }
            }

            tabLayer(.sessions) {
                NavigationStack {
                    SessionsKillzonesView(viewModel: viewModel, preferences: preferences)
                }
            }

            tabLayer(.settings) {
                NavigationStack {
                    AppSettingsView(viewModel: viewModel, preferences: preferences)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: navigationState.selectedTab)
        .preferredColorScheme(preferences.effectiveColorScheme)
        .task(id: preferences.effectiveTimeZone.identifier) {
            await viewModel.loadCurrentWeek(timeZone: preferences.effectiveTimeZone)
        }
        .onAppear {
            isShowingOnboarding = !preferences.hasCompletedOnboarding
        }
        .task(id: notificationScheduleKey) {
            guard shouldSyncDefaultNotifications else { return }
            await CalendarNotificationStore.syncDefaultNotifications(for: viewModel.events, preferences: preferences)
            await SessionNotificationStore.resyncEnabledNotifications(preferences: preferences)
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(selectedTab: $navigationState.selectedTab)
                .frame(maxWidth: FXNewsLayout.maxContentWidth)
                .padding(.horizontal, FXNewsLayout.horizontalPadding)
                .padding(.bottom, 8)
        }
        .fullScreenCover(isPresented: $isShowingOnboarding) {
            OnboardingView(
                preferences: preferences,
                navigationState: navigationState
            ) {
                isShowingOnboarding = false
            }
        }
    }

    private func tabLayer<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = navigationState.selectedTab == tab

        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }

    private var shouldSyncDefaultNotifications: Bool {
        guard preferences.hasCompletedOnboarding else {
            return false
        }

        guard let visibleInterval = viewModel.visibleInterval else {
            return false
        }

        let currentWeek = Calendar.tradingWeekInterval()
        return abs(visibleInterval.start.timeIntervalSince(currentWeek.start)) < 1
    }

    private var notificationScheduleKey: String {
        [
            viewModel.events.map(\.id).joined(separator: "|"),
            viewModel.lastRefreshDate?.ISO8601Format() ?? "none",
            "\(preferences.highImpactNotificationLeadTimeMinutes)",
            "\(preferences.mediumImpactNotificationLeadTimeMinutes)",
            "\(preferences.lowImpactNotificationLeadTimeMinutes)",
            preferences.watchedPairSymbols.joined(separator: "|"),
            preferences.notificationSoundOption.rawValue,
            "\(preferences.quietHoursEnabled)",
            "\(preferences.quietHoursStartMinutes)",
            "\(preferences.quietHoursEndMinutes)",
            "\(preferences.asianSessionNotificationsEnabled)",
            "\(preferences.londonSessionNotificationsEnabled)",
            "\(preferences.newYorkSessionNotificationsEnabled)",
            "\(preferences.asianLondonOverlapNotificationsEnabled)",
            "\(preferences.londonNewYorkOverlapNotificationsEnabled)"
        ].joined(separator: "::")
    }
}

enum AppTab: String, Hashable {
    case calendar
    case pairs
    case sessions
    case settings

    var title: String {
        switch self {
        case .calendar:
            "Calendar"
        case .pairs:
            "My Pairs"
        case .sessions:
            "Sessions"
        case .settings:
            "Settings"
        }
    }

    var icon: String {
        switch self {
        case .calendar:
            "calendar"
        case .pairs:
            "chart.line.uptrend.xyaxis"
        case .sessions:
            "clock.badge"
        case .settings:
            "slider.horizontal.3"
        }
    }
}

private struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    private let tabs: [AppTab] = [.calendar, .pairs, .sessions, .settings]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tabButtons
            }

            HStack(spacing: 8) {
                compactTabButtons
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background {
            Capsule(style: .continuous)
                .fill(FXNewsPalette.surface.opacity(0.94))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private var tabButtons: some View {
        ForEach(tabs, id: \.self) { tab in
            tabButton(for: tab, compact: false)
        }
    }

    @ViewBuilder
    private var compactTabButtons: some View {
        ForEach(tabs, id: \.self) { tab in
            tabButton(for: tab, compact: true)
        }
    }

    private func tabButton(for tab: AppTab, compact: Bool) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Group {
                if isSelected {
                    HStack(spacing: compact ? 8 : 10) {
                        Image(systemName: tab.icon)
                            .font(.headline)

                        if compact {
                            Text(tab.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text(tab.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Image(systemName: tab.icon)
                        .font(.headline)
                        .frame(width: 22, height: 22)
                }
            }
            .foregroundStyle(isSelected ? Color.white : FXNewsPalette.muted)
            .padding(.horizontal, isSelected ? (compact ? 12 : 18) : 0)
            .frame(height: compact ? 52 : 56)
            .frame(maxWidth: isSelected ? .infinity : nil)
            .frame(width: isSelected ? nil : (compact ? 52 : 56))
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? FXNewsPalette.accent : FXNewsPalette.surfaceStrong)
            )
            .overlay {
                Capsule(style: .continuous)
                    .stroke(FXNewsPalette.stroke, lineWidth: isSelected ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .layoutPriority(isSelected ? 1 : 0)
    }
}

#Preview {
    RootTabView()
}
