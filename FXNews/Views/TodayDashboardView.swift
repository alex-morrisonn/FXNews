import SwiftUI

@MainActor
struct TodayDashboardView: View {
    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences
    @Bindable var subscriptionStore: SubscriptionStore
    @Bindable private var navigationState = AppNavigationState.shared

    private static let activityService: any MarketActivityService = EstimatedMarketActivityService()

    private var displayTimeZone: TimeZone {
        preferences.effectiveTimeZone
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let snapshot = Self.activityService.snapshot(at: now, events: viewModel.events)

            ScrollView {
                FXNewsScreen {
                    VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                        FXNewsSectionHeader(
                            eyebrow: "Today",
                            title: "Market Brief",
                            subtitle: briefSubtitle(now: now)
                        )

                        dataFreshnessBanner
                        marketStatusCard(snapshot: snapshot, now: now)
                        nextRiskCard(now: now)
                        watchedPairsCard(now: now)
                        sessionCard(now: now)
                    }
                }
            }
            .background(Color.clear)
        }
        .overlay {
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView("Loading brief...")
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(FXNewsPalette.surfaceStrong)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(FXNewsPalette.stroke, lineWidth: 1)
                            }
                    )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("FX News")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)
            }
        }
        .task {
            guard viewModel.events.isEmpty else { return }
            await viewModel.loadCurrentWeek(timeZone: displayTimeZone)
        }
        .refreshable {
            await viewModel.refresh()
            FXNewsHaptics.success()
        }
    }

    private var todaysEvents: [EconomicEvent] {
        let calendar = localCalendar
        return viewModel.events
            .filter { calendar.isDate($0.timestamp, inSameDayAs: Date()) }
            .sorted(by: EconomicEvent.calendarDayDisplayOrder)
    }

    private var upcomingEvents: [EconomicEvent] {
        viewModel.events
            .filter { $0.timestamp >= Date() }
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.title < rhs.title
            }
    }

    private var watchedPairEventsToday: [EconomicEvent] {
        todaysEvents.filter { event in
            event.isHoliday || preferences.matchesWatchedPair(event)
        }
    }

    private var highImpactEventsToday: [EconomicEvent] {
        todaysEvents.filter { !$0.isHoliday && $0.impactLevel == .high }
    }

    private var nextMarketMovingEvent: EconomicEvent? {
        upcomingEvents.first { event in
            event.isHoliday || event.impactLevel.rank >= ImpactLevel.medium.rank
        }
    }

    private var activeSessions: [ForexSessionDefinition] {
        ForexSessionDefinition.allCases.filter { definition in
            SessionPresentation.intervalsAroundNow(for: definition, now: Date())
                .contains { $0.contains(Date()) }
        }
    }

    private var nextSession: ForexSessionDefinition? {
        ForexSessionDefinition.allCases.min { lhs, rhs in
            SessionPresentation.nextInterval(for: lhs, after: Date()).start < SessionPresentation.nextInterval(for: rhs, after: Date()).start
        }
    }

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = displayTimeZone
        return calendar
    }

    @ViewBuilder
    private var dataFreshnessBanner: some View {
        if viewModel.isShowingFallbackData || viewModel.errorMessage != nil {
            FXNewsCard {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(FXNewsPalette.warning)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.isShowingFallbackData ? "Showing saved calendar data" : "Calendar refresh failed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FXNewsPalette.text)

                        Text(dataFreshnessMessage)
                            .font(.caption)
                            .foregroundStyle(FXNewsPalette.muted)
                    }
                }
            }
        }
    }

    private var dataFreshnessMessage: String {
        if let lastRefreshDate = viewModel.lastRefreshDate {
            return "Last verified \(EventDateFormatter.relativeString(for: lastRefreshDate)). Pull to refresh when you are online."
        }

        return viewModel.errorMessage ?? "Pull to refresh when you are online."
    }

    private func marketStatusCard(snapshot: MarketActivitySnapshot, now: Date) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FXNewsPalette.muted)

                        Text(snapshot.statusText)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(FXNewsPalette.text)
                    }

                    Spacer()

                    activityBadge(snapshot.tier)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    FXNewsMetricCard(title: "High Impact", value: "\(highImpactEventsToday.count)")
                    FXNewsMetricCard(title: "Watched Pair Events", value: "\(watchedPairEventsToday.count)")
                }

                Button {
                    navigationState.selectedTab = .calendar
                } label: {
                    actionButton(title: "Open Calendar", systemImage: "calendar")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func nextRiskCard(now: Date) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Next Risk")

                if let event = nextMarketMovingEvent {
                    TodayEventRow(event: event, preferences: preferences, now: now)
                } else {
                    emptyCopy("No upcoming market-moving releases are loaded for this week.")
                }
            }
        }
    }

    private func watchedPairsCard(now: Date) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionTitle("Watched Pairs")
                    Spacer()
                    Button("Manage") {
                        navigationState.selectedTab = .pairs
                    }
                    .font(.caption.weight(.semibold))
                    .tint(FXNewsPalette.accent)
                }

                if preferences.watchedPairSymbols.isEmpty {
                    emptyCopy("Add the pairs you trade to make this brief focus on your watchlist.")
                } else if watchedPairEventsToday.isEmpty {
                    emptyCopy("No watched-pair events are scheduled today.")
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(watchedPairEventsToday.prefix(3))) { event in
                            TodayEventRow(event: event, preferences: preferences, now: now)
                        }
                    }
                }
            }
        }
    }

    private func sessionCard(now: Date) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionTitle("Sessions")
                    Spacer()
                    Button("Board") {
                        navigationState.selectedTab = .sessions
                    }
                    .font(.caption.weight(.semibold))
                    .tint(FXNewsPalette.accent)
                }

                if !activeSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(activeSessions) { session in
                            sessionRow(title: session.shortTitle, detail: "Active now", tint: session.color)
                        }
                    }
                } else if let nextSession {
                    let interval = SessionPresentation.nextInterval(for: nextSession, after: now)
                    sessionRow(
                        title: nextSession.shortTitle,
                        detail: "Opens in \(SessionPresentation.relativeCountdown(to: interval.start, from: now))",
                        tint: nextSession.color
                    )
                } else {
                    emptyCopy("No session timing is available right now.")
                }
            }
        }
    }

    private func briefSubtitle(now: Date) -> String {
        let time = EventDateFormatter.timeString(from: now, timeZone: displayTimeZone, use24HourTime: preferences.use24HourTime)
        let zone = EventDateFormatter.timeZoneLabel(for: displayTimeZone)
        return "\(time) \(zone) • \(todaysEvents.count) events today"
    }

    private func activityBadge(_ tier: MarketActivityTier) -> some View {
        Text(tier.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(activityColor(for: tier)))
    }

    private func activityColor(for tier: MarketActivityTier) -> Color {
        switch tier {
        case .low:
            FXNewsPalette.muted
        case .medium:
            FXNewsPalette.warning
        case .high:
            FXNewsPalette.danger
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(FXNewsPalette.text)
    }

    private func emptyCopy(_ copy: String) -> some View {
        Text(copy)
            .font(.subheadline)
            .foregroundStyle(FXNewsPalette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionRow(title: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            Spacer()

            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(FXNewsPalette.muted)
        }
    }

    private func actionButton(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FXNewsPalette.accent)
        )
    }
}

private struct TodayEventRow: View {
    let event: EconomicEvent
    let preferences: UserPreferences
    let now: Date

    private var timeLabel: String {
        if event.isHoliday {
            return "All day"
        }

        return EventDateFormatter.timeString(
            from: event.timestamp,
            timeZone: preferences.effectiveTimeZone,
            use24HourTime: preferences.use24HourTime
        )
    }

    private var timingLabel: String {
        guard !event.isHoliday else {
            return "Holiday"
        }

        if event.timestamp < now {
            return "Released"
        }

        return "In \(SessionPresentation.relativeCountdown(to: event.timestamp, from: now))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(event.isHoliday ? FXNewsPalette.muted : event.impactLevel.color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
                    .multilineTextAlignment(.leading)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        metadataPill(event.currencyCode)
                        metadataPill(timeLabel)
                        metadataPill(timingLabel)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        metadataPill(event.currencyCode)
                        metadataPill("\(timeLabel) • \(timingLabel)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(FXNewsPalette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

#Preview("Today") {
    NavigationStack {
        TodayDashboardView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences(),
            subscriptionStore: SubscriptionStore()
        )
    }
}
