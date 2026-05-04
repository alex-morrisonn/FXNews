import SwiftUI
import UserNotifications
import UIKit

@MainActor
struct CalendarView: View {
    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences
    @Bindable private var navigationState = AppNavigationState.shared

    @State private var weekOffset = 0
    @State private var collapsedDays: Set<Date> = []
    @State private var expandedPastEventDays: Set<Date> = []
    @State private var scheduledNotificationEventIDs: Set<String> = []
    @State private var todayHeaderOffset: CGFloat?
    @State private var hasPerformedInitialTodayScroll = false
    @State private var shouldScrollToToday = false
    @State private var notificationAlertMessage: String?
    @State private var routedEvent: EconomicEvent?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = displayTimeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private var displayTimeZone: TimeZone {
        preferences.effectiveTimeZone
    }

    private var weekInterval: DateInterval {
        Calendar.tradingWeekInterval(referenceDate: Date(), weekOffset: weekOffset, timeZone: displayTimeZone)
    }

    private var weekdaySections: [DaySection] {
        let weekdayDates = Calendar.tradingWeekdays(referenceDate: Date(), weekOffset: weekOffset, timeZone: displayTimeZone)
        let groupedEvents = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }

        return weekdayDates.map { day in
            let normalizedDay = calendar.startOfDay(for: day)
            return DaySection(
                day: normalizedDay,
                events: (groupedEvents[normalizedDay] ?? []).sorted { $0.timestamp < $1.timestamp },
                isToday: calendar.isDateInToday(normalizedDay)
            )
        }
    }

    private var allWeekEvents: [EconomicEvent] {
        viewModel.events.sorted { $0.timestamp < $1.timestamp }
    }

    private var filteredEvents: [EconomicEvent] {
        allWeekEvents.filter { event in
            let matchesImpact = event.impactLevel.rank >= preferences.minimumImpact.rank
            let matchesCurrency = preferences.selectedCurrencyCode == nil || event.currencyCode == preferences.selectedCurrencyCode
            let matchesCountry = preferences.selectedCountryCode == nil || event.countryCode == preferences.selectedCountryCode
            let matchesCategory = preferences.selectedCategory == nil || event.category == preferences.selectedCategory
            let matchesWatchedPairs = !preferences.showOnlyWatchedPairs
                || preferences.watchedPairSymbols.isEmpty
                || preferences.matchesWatchedPair(event)

            return matchesImpact && matchesCurrency && matchesCountry && matchesCategory && matchesWatchedPairs
        }
    }

    private var availableCurrencies: [String] {
        Array(Set(allWeekEvents.map(\.currencyCode))).sorted()
    }

    private var availableCountries: [String] {
        Array(Set(allWeekEvents.map(\.countryCode))).sorted()
    }

    private var availableCategories: [String] {
        Array(Set(allWeekEvents.compactMap(\.category))).sorted()
    }

    private var activeFilterDescriptions: [String] {
        var filters: [String] = []

        switch preferences.minimumImpact {
        case .high:
            filters.append("High impact")
        case .medium:
            filters.append("Market movers")
        case .low:
            break
        }

        if let currency = preferences.selectedCurrencyCode {
            filters.append("\(currency) events")
        }

        if let country = preferences.selectedCountryCode {
            filters.append(CountryDisplay.name(for: country))
        }

        if let category = preferences.selectedCategory {
            filters.append(category)
        }

        if preferences.showOnlyWatchedPairs {
            filters.append("Watchlist")
        }

        return filters
    }

    private var activeFilterSummary: String {
        let filterCount = activeFilterDescriptions.count

        guard filterCount > 0 else {
            return "All events"
        }

        if filterCount <= 2 {
            return activeFilterDescriptions.joined(separator: " • ")
        }

        return "\(activeFilterDescriptions[0]) + \(filterCount - 1) more"
    }

    private var impactFilterLabel: String {
        switch preferences.minimumImpact {
        case .high:
            "High impact"
        case .medium:
            "Market movers"
        case .low:
            "All events"
        }
    }

    private var selectedCurrencyLabel: String {
        preferences.selectedCurrencyCode ?? "Any"
    }

    private var selectedCountryLabel: String {
        guard let countryCode = preferences.selectedCountryCode else {
            return "Any"
        }

        return CountryDisplay.name(for: countryCode)
    }

    private var selectedCategoryLabel: String {
        preferences.selectedCategory ?? "Any"
    }

    private var watchlistFilterLabel: String {
        preferences.showOnlyWatchedPairs ? "Watchlist only" : "All pairs"
    }

    private var recentEventCutoff: Date {
        Date().addingTimeInterval(-90 * 60)
    }

    private var weekTitle: String {
        guard let friday = calendar.date(byAdding: .day, value: 4, to: weekInterval.start) else {
            return EventDateFormatter.monthDayString(from: weekInterval.start, timeZone: displayTimeZone)
        }

        let start = EventDateFormatter.monthDayString(from: weekInterval.start, timeZone: displayTimeZone)
        let end = EventDateFormatter.monthDayString(from: friday, timeZone: displayTimeZone)
        return "\(start) - \(end)"
    }

    private var emptyState: CalendarEmptyState? {
        guard !viewModel.isLoading else {
            return nil
        }

        if filteredEvents.isEmpty, !allWeekEvents.isEmpty {
            return .filters
        }

        if allWeekEvents.isEmpty, viewModel.errorMessage != nil {
            return .offline
        }

        if allWeekEvents.isEmpty {
            return .noData
        }

        return nil
    }

    private var shouldShowJumpToTodayButton: Bool {
        weekOffset != 0
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                FXNewsScreen {
                    LazyVStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing, pinnedViews: [.sectionHeaders]) {
                        header
                        filterControls

                        freshnessBanner

                        if let emptyState {
                            emptyStateCard(emptyState)
                        } else {
                            ForEach(weekdaySections) { section in
                                Section {
                                    if !collapsedDays.contains(section.day) {
                                        let visibleEvents = visibleEvents(for: section)
                                        let foldedEvents = foldedEvents(for: section)

                                        if visibleEvents.isEmpty && foldedEvents.isEmpty {
                                            FXNewsCard {
                                                Text("No scheduled releases.")
                                                    .font(.subheadline)
                                                    .foregroundStyle(FXNewsPalette.muted)
                                            }
                                        } else {
                                            VStack(spacing: 12) {
                                                eventList(visibleEvents)

                                                if !foldedEvents.isEmpty {
                                                    foldedEventsGroup(for: section, events: foldedEvents)
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    dayHeader(for: section)
                                        .id(section.day)
                                }
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "calendar-scroll")
            .background(Color.clear)
            .overlay {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    ProgressView("Loading events...")
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
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if shouldShowJumpToTodayButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Jump to today") {
                            jumpToToday()
                        }
                        .font(.subheadline.weight(.semibold))
                        .tint(FXNewsPalette.accent)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .task(id: weekOffset) {
                await loadVisibleWeek(using: proxy)
            }
            .task(id: displayTimeZone.identifier) {
                collapsedDays.removeAll()
                expandedPastEventDays.removeAll()
                await loadVisibleWeek(using: proxy)
            }
            .task {
                scheduledNotificationEventIDs = await CalendarNotificationStore.scheduledEventIDs()
            }
            .refreshable {
                await viewModel.refresh()
                FXNewsHaptics.success()
            }
            .simultaneousGesture(weekSwipeGesture, including: .gesture)
            .onPreferenceChange(TodayHeaderOffsetKey.self) { todayHeaderOffset = $0 }
            .onChange(of: viewModel.events) { _, _ in
                guard weekOffset == 0 else {
                    return
                }

                shouldScrollToToday = true
                routeToPendingEventIfNeeded()
            }
            .onChange(of: weekOffset) { _, _ in
                collapsedDays.removeAll()
                expandedPastEventDays.removeAll()
            }
            .onAppear {
                routeToPendingEventIfNeeded()
            }
            .onChange(of: navigationState.pendingEventID) { _, _ in
                routeToPendingEventIfNeeded()
            }
            .alert("Notifications", isPresented: notificationAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(notificationAlertMessage ?? "")
            }
            .sheet(item: $routedEvent) { event in
                NavigationStack {
                    EconomicEventDetailView(event: event, preferences: preferences)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: filteredEvents.map(\.id))
            .animation(.easeInOut(duration: 0.18), value: activeFilterDescriptions)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekOffset == 0 ? "This Week" : "Calendar Week")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(FXNewsPalette.muted)
                Text(weekTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(FXNewsPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer()

            HStack(spacing: 8) {
                weekStepperButton(systemName: "chevron.left") {
                    weekOffset -= 1
                }

                weekStepperButton(systemName: "chevron.right") {
                    weekOffset += 1
                }
            }
        }
    }

    @ViewBuilder
    private var freshnessBanner: some View {
        if let freshness = freshnessStatus {
            FXNewsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: freshness.iconName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(freshness.tint)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(freshness.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FXNewsPalette.text)

                            Text(freshness.timestampLabel)
                                .font(.caption)
                                .foregroundStyle(FXNewsPalette.muted)
                        }
                    }

                    if let message = freshness.message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(FXNewsPalette.text)
                    }
                }
            }
        }
    }

    private var freshnessStatus: FreshnessStatus? {
        guard let lastRefreshDate = viewModel.lastRefreshDate else {
            return nil
        }

        let age = max(0, Date().timeIntervalSince(lastRefreshDate))
        let isStale = age >= 3 * 24 * 60 * 60
        let usesFallbackData = viewModel.isShowingFallbackData

        let title: String
        if usesFallbackData {
            title = isStale ? "Calendar may be outdated" : "Showing fallback calendar data"
        } else {
            title = isStale ? "Calendar data is stale" : "Last checked"
        }

        let message: String?
        if usesFallbackData {
            switch viewModel.dataSource {
            case .cache:
                message = "Couldn’t refresh from the network, so the app is showing cached data."
            case .bundled:
                message = "Couldn’t refresh from the network, so the app is showing bundled backup data."
            case .remote, nil:
                message = nil
            }
        } else if isStale {
            message = "This feed is more than 3 days old. Pull to refresh before trading off these releases."
        } else {
            message = nil
        }

        let tint: Color = usesFallbackData || isStale ? Color.orange.opacity(0.9) : FXNewsPalette.accent
        let iconName = usesFallbackData ? "wifi.slash" : (isStale ? "exclamationmark.triangle" : "clock.arrow.circlepath")
        let absolute = EventDateFormatter.dateTimeString(
            from: lastRefreshDate,
            timeZone: displayTimeZone,
            use24HourTime: preferences.use24HourTime
        )
        let relative = EventDateFormatter.relativeString(for: lastRefreshDate)

        return FreshnessStatus(
            title: title,
            timestampLabel: "\(absolute) • \(relative)",
            message: message,
            tint: tint,
            iconName: iconName
        )
    }

    private var filterControls: some View {
        HStack(spacing: 12) {
            Menu {
                Section("Quick filters") {
                    Button("All events") { clearFilters() }
                    Button("Market movers") { preferences.minimumImpact = .medium }
                    Button("High-impact only") { preferences.minimumImpact = .high }

                    if !preferences.watchedPairSymbols.isEmpty {
                        Button(preferences.showOnlyWatchedPairs ? "Show all pairs" : "Watchlist only") {
                            preferences.showOnlyWatchedPairs.toggle()
                        }
                    }
                }

                Menu("Importance: \(impactFilterLabel)") {
                    Button("All events") { preferences.minimumImpact = .low }
                    Button("Market movers") { preferences.minimumImpact = .medium }
                    Button("High-impact only") { preferences.minimumImpact = .high }
                }

                Menu("Location") {
                    Menu("Currency: \(selectedCurrencyLabel)") {
                        Button("Any currency") { preferences.selectedCurrencyCode = nil }
                        ForEach(availableCurrencies, id: \.self) { currency in
                            Button(currency) { preferences.selectedCurrencyCode = currency }
                        }
                    }

                    Menu("Country: \(selectedCountryLabel)") {
                        Button("Any country") { preferences.selectedCountryCode = nil }
                        ForEach(availableCountries, id: \.self) { country in
                            Button("\(CountryDisplay.flag(for: country)) \(CountryDisplay.name(for: country))") {
                                preferences.selectedCountryCode = country
                            }
                        }
                    }
                }

                if !availableCategories.isEmpty {
                    Menu("Category: \(selectedCategoryLabel)") {
                        Button("Any category") { preferences.selectedCategory = nil }
                        ForEach(availableCategories, id: \.self) { category in
                            Button(category) { preferences.selectedCategory = category }
                        }
                    }
                }

                if !preferences.watchedPairSymbols.isEmpty {
                    Menu("Pairs: \(watchlistFilterLabel)") {
                        Button("All pairs") {
                            preferences.showOnlyWatchedPairs = false
                        }
                        Button("Watchlist only") {
                            preferences.showOnlyWatchedPairs = true
                        }
                    }
                }
            } label: {
                FilterMenuLabel(
                    title: "Filters",
                    value: activeFilterDescriptions.isEmpty ? "All events" : "\(activeFilterDescriptions.count) active"
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activeFilterSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
                    .lineLimit(1)
            }

            Spacer()

            if !activeFilterDescriptions.isEmpty {
                Button("Clear") {
                    clearFilters()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.accent)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    private func dayHeader(for section: DaySection) -> some View {
        Button {
            toggleSection(section.day)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(dayHeaderTitle(for: section.day))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Text("\(section.events.count) event\(section.events.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                }

                if section.isToday {
                    FXNewsPill(text: "Today", tint: FXNewsPalette.accentSoft)
                }

                Spacer()

                Image(systemName: collapsedDays.contains(section.day) ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FXNewsPalette.muted)
            }
            .padding(.vertical, 8)
            .background(todayHeaderOffsetReader(isToday: section.isToday))
        }
        .buttonStyle(.plain)
    }

    private func todayHeaderOffsetReader(isToday: Bool) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TodayHeaderOffsetKey.self,
                value: isToday ? proxy.frame(in: .named("calendar-scroll")).minY : nil
            )
        }
    }

    private func emptyStateCard(_ state: CalendarEmptyState) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(state.title)
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text(state.message)
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)
            }
        }
    }

    private func weekStepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(FXNewsPalette.text)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(FXNewsPalette.surfaceStrong)
                        .overlay {
                            Circle()
                                .stroke(FXNewsPalette.stroke, lineWidth: 1)
                        }
                )
        }
        .buttonStyle(.plain)
    }

    private func dayHeaderTitle(for day: Date) -> String {
        EventDateFormatter.dayString(from: day, timeZone: displayTimeZone)
    }

    private func toggleSection(_ day: Date) {
        if collapsedDays.contains(day) {
            collapsedDays.remove(day)
        } else {
            collapsedDays.insert(day)
        }
    }

    private func clearFilters() {
        preferences.minimumImpact = .low
        preferences.selectedCurrencyCode = nil
        preferences.selectedCountryCode = nil
        preferences.selectedCategory = nil
        preferences.showOnlyWatchedPairs = false
    }

    private func visibleEvents(for section: DaySection) -> [EconomicEvent] {
        section.events.filter { $0.timestamp >= recentEventCutoff }
    }

    private func foldedEvents(for section: DaySection) -> [EconomicEvent] {
        section.events.filter { $0.timestamp < recentEventCutoff }
    }

    @ViewBuilder
    private func eventList(_ events: [EconomicEvent]) -> some View {
        ForEach(events) { event in
            let isNotificationScheduled = scheduledNotificationEventIDs.contains(event.id)
            NavigationLink {
                EconomicEventDetailView(event: event, preferences: preferences)
            } label: {
                EconomicEventRow(
                    event: event,
                    preferences: preferences,
                    isNotificationScheduled: isNotificationScheduled
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(isNotificationScheduled ? "Remove notification" : "Notify me") {
                    Task {
                        await toggleNotification(for: event)
                    }
                }
            }
        }
    }

    private func foldedEventsGroup(for section: DaySection, events: [EconomicEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                toggleFoldedEvents(for: section.day)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isShowingFoldedEvents(for: section.day) ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(FXNewsPalette.muted)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isShowingFoldedEvents(for: section.day) ? "Hide earlier releases" : "Show earlier releases")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FXNewsPalette.text)

                        Text("\(events.count) event\(events.count == 1 ? "" : "s") already passed")
                            .font(.caption)
                            .foregroundStyle(FXNewsPalette.muted)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FXNewsPalette.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(FXNewsPalette.stroke, lineWidth: 1)
                        }
                )
            }
            .buttonStyle(.plain)

            if isShowingFoldedEvents(for: section.day) {
                eventList(events)
            }
        }
    }

    private func isShowingFoldedEvents(for day: Date) -> Bool {
        expandedPastEventDays.contains(day)
    }

    private func toggleFoldedEvents(for day: Date) {
        if expandedPastEventDays.contains(day) {
            expandedPastEventDays.remove(day)
        } else {
            expandedPastEventDays.insert(day)
        }
    }

    private func loadVisibleWeek(using proxy: ScrollViewProxy) async {
        await viewModel.loadWeek(referenceDate: Date(), weekOffset: weekOffset, timeZone: displayTimeZone)

        guard weekOffset == 0 else {
            return
        }

        if !hasPerformedInitialTodayScroll || shouldScrollToToday {
            hasPerformedInitialTodayScroll = true
            shouldScrollToToday = false

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(calendar.startOfDay(for: Date()), anchor: .top)
                }
            }
        }
    }

    private func jumpToToday() {
        shouldScrollToToday = true
        weekOffset = 0
    }

    private func toggleNotification(for event: EconomicEvent) async {
        do {
            let isScheduled = scheduledNotificationEventIDs.contains(event.id)
            let shouldRemainScheduled = try await CalendarNotificationStore.toggleNotification(
                for: event,
                isScheduled: isScheduled,
                preferences: preferences
            )

            if shouldRemainScheduled {
                scheduledNotificationEventIDs.insert(event.id)
                FXNewsHaptics.success()
            } else {
                scheduledNotificationEventIDs.remove(event.id)
                FXNewsHaptics.selection()
            }
        } catch {
            notificationAlertMessage = error.localizedDescription
            FXNewsHaptics.warning()
        }
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 60
                else {
                    return
                }

                if value.translation.width < 0 {
                    weekOffset += 1
                } else {
                    weekOffset -= 1
                }
            }
    }

    private var notificationAlertBinding: Binding<Bool> {
        Binding(
            get: { notificationAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    notificationAlertMessage = nil
                }
            }
        )
    }

    private func routeToPendingEventIfNeeded() {
        guard let eventID = navigationState.pendingEventID else {
            return
        }

        if let matchedEvent = viewModel.events.first(where: { $0.id == eventID }) {
            consumePendingEvent(matchedEvent)
            return
        }

        Task {
            await viewModel.loadCurrentWeek(timeZone: displayTimeZone)
            if let matchedEvent = viewModel.events.first(where: { $0.id == eventID }) {
                consumePendingEvent(matchedEvent)
            }
        }
    }

    private func consumePendingEvent(_ event: EconomicEvent) {
        navigationState.selectedTab = .calendar
        navigationState.pendingEventID = nil
        routedEvent = event
    }
}

private struct FreshnessStatus {
    let title: String
    let timestampLabel: String
    let message: String?
    let tint: Color
    let iconName: String
}

private struct EconomicEventRow: View {
    let event: EconomicEvent
    let preferences: UserPreferences
    let isNotificationScheduled: Bool

    private var isPastEvent: Bool {
        event.timestamp < Date()
    }

    private var eventTypeLabel: String {
        event.isHoliday ? "Holiday" : event.impactLevel.label
    }

    private var eventTypeColor: Color {
        if isPastEvent {
            return FXNewsPalette.muted
        }

        return event.isHoliday ? .gray : event.impactLevel.color
    }

    private var eventDotColor: Color {
        if isPastEvent {
            return FXNewsPalette.muted
        }

        return event.isHoliday ? .gray : event.impactLevel.color
    }

    private var primaryTextColor: Color {
        isPastEvent ? FXNewsPalette.muted : FXNewsPalette.text
    }

    private var secondaryTextColor: Color {
        isPastEvent ? FXNewsPalette.muted.opacity(0.82) : FXNewsPalette.muted
    }

    var body: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(
                        EventDateFormatter.timeString(
                            from: event.timestamp,
                            timeZone: preferences.effectiveTimeZone,
                            use24HourTime: preferences.use24HourTime
                        )
                    )
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(primaryTextColor)
                    .frame(width: 72, alignment: .leading)

                    Circle()
                        .fill(eventDotColor)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                FXNewsPill(
                                    text: "Affects \(event.currencyCode)",
                                    tint: isPastEvent ? FXNewsPalette.surfaceStrong : FXNewsPalette.accentSoft
                                )

                                Text(event.title)
                                    .font(.headline)
                                    .foregroundStyle(primaryTextColor)
                                    .multilineTextAlignment(.leading)

                                rowMetadata
                            }

                            Spacer(minLength: 8)

                            if isNotificationScheduled {
                                Image(systemName: "bell.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(isPastEvent ? FXNewsPalette.muted : FXNewsPalette.accent)
                            }
                        }

                        eventMetricsSummary
                    }
                }
            }
        }
        .opacity(isPastEvent ? 0.58 : 1)
    }

    private var rowMetadata: some View {
        HStack(spacing: 8) {
            Text(eventTypeLabel)
                .font(.caption)
                .foregroundStyle(eventTypeColor)

            if let category = event.category {
                Text(category)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
        }
    }

    private var eventMetricsSummary: some View {
        let metrics = metricItems

        return Group {
            if !metrics.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        ForEach(metrics, id: \.label) { metric in
                            compactMetric(label: metric.label, value: metric.value)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(metrics, id: \.label) { metric in
                            compactMetric(label: metric.label, value: metric.value)
                        }
                    }
                }
            }
        }
    }

    private var metricItems: [(label: String, value: String)] {
        var items: [(label: String, value: String)] = []

        if let forecast = event.forecast {
            items.append((label: "Forecast", value: forecast))
        }

        if let previous = event.previous {
            items.append((label: "Previous", value: previous))
        }

        if !event.isHoliday, let actual = event.actual {
            items.append((label: "Actual", value: actual))
        }

        return items
    }

    private func compactMetric(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
        }
    }
}

private struct EconomicEventDetailView: View {
    @Environment(\.displayScale) private var displayScale
    let event: EconomicEvent
    let preferences: UserPreferences
    @State private var reminderMessage: String?
    @State private var isShowingReminderOptions = false
    @State private var isShowingCustomReminderSheet = false
    @State private var customReminderMinutes = 90
    @State private var shareImage: ShareableImage?

    private var eventDateString: String {
        let timeZone = preferences.effectiveTimeZone
        let day = EventDateFormatter.dayString(from: event.timestamp, timeZone: timeZone)
        let time = EventDateFormatter.timeString(
            from: event.timestamp,
            timeZone: timeZone,
            use24HourTime: preferences.use24HourTime
        )
        let timezoneLabel = EventDateFormatter.timeZoneLabel(for: timeZone)
        return "\(day) at \(time) \(timezoneLabel)"
    }

    private var categoryDisplayName: String {
        EventPresentation.categoryLabel(for: event.category)
    }

    private var sourceAttribution: String {
        "Source: FX News calendar feed"
    }

    private var eventTypeLabel: String {
        event.isHoliday ? "Holiday" : event.impactLevel.label
    }

    private var eventTypeTint: Color {
        event.isHoliday ? FXNewsPalette.surfaceStrong : event.impactLevel.color.opacity(0.18)
    }

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    detailHeader
                    marketSnapshotSection
                    contextSection
                }
            }
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Set Reminder", isPresented: $isShowingReminderOptions, titleVisibility: .visible) {
            reminderOptionButton(title: "15 minutes before", minutesBefore: 15)
            reminderOptionButton(title: "30 minutes before", minutesBefore: 30)
            reminderOptionButton(title: "1 hour before", minutesBefore: 60)
            Button("Custom") {
                isShowingCustomReminderSheet = true
            }
        }
        .sheet(isPresented: $isShowingCustomReminderSheet) {
            CustomReminderSheet(
                event: event,
                minutesBefore: $customReminderMinutes
            ) { minutes in
                Task {
                    await scheduleReminder(minutesBefore: minutes)
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $shareImage) { shareImage in
            ActivityViewController(activityItems: [shareImage.image])
        }
        .alert("Reminder", isPresented: reminderAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reminderMessage ?? "")
        }
    }

    private var detailHeader: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(event.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)

                HStack(spacing: 10) {
                    FXNewsPill(text: "Affects \(event.currencyCode)", tint: FXNewsPalette.accentSoft)
                    FXNewsPill(text: eventTypeLabel, tint: eventTypeTint)
                }

                if categoryDisplayName != "Macroeconomic" || event.category != nil {
                    Text(categoryDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(FXNewsPalette.muted)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(eventDateString)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FXNewsPalette.text)

                    if event.timestamp > Date() {
                        Text("•")
                            .foregroundStyle(FXNewsPalette.muted)

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(EventPresentation.countdownString(to: event.timestamp, now: context.date))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(FXNewsPalette.accent)
                        }
                    }
                }
            }
        }
    }

    private var marketSnapshotSection: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Market Snapshot")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                ViewThatFits(in: .horizontal) {
                    if event.hasNumericContext {
                        HStack(spacing: 12) {
                            detailMetrics
                        }

                        VStack(spacing: 12) {
                            detailMetrics
                        }
                    } else {
                        metricEmptyState
                    }
                }

                if event.hasNumericContext {
                    Divider()
                        .overlay(FXNewsPalette.stroke)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Affected Pairs")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    if event.relatedPairs.isEmpty {
                        Text("No pair mapping is available for this event yet.")
                            .font(.subheadline)
                            .foregroundStyle(FXNewsPalette.muted)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(event.relatedPairs, id: \.self) { pair in
                                FXNewsPill(
                                    text: preferences.isPairWatched(pair) ? "\(pair) Watchlist" : pair,
                                    tint: preferences.isPairWatched(pair) ? FXNewsPalette.accentSoft : FXNewsPalette.surfaceStrong
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var contextSection: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Why It Matters")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text(EventPresentation.explainer(for: event))
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                HStack(spacing: 12) {
                    Button {
                        isShowingReminderOptions = true
                    } label: {
                        actionButtonLabel(title: "Set Reminder", systemImage: "bell.badge")
                    }
                    .buttonStyle(.plain)

                    Button {
                        shareImage = ShareableImage(image: makeShareImage())
                    } label: {
                        actionButtonLabel(title: "Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }

                Text(sourceAttribution)
                    .font(.caption)
                    .foregroundStyle(FXNewsPalette.muted)
            }
        }
    }

    private func actionButtonLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FXNewsPalette.accent)
        )
    }

    private func reminderOptionButton(title: String, minutesBefore: Int) -> some View {
        Button(title) {
            Task {
                await scheduleReminder(minutesBefore: minutesBefore)
            }
        }
    }

    private func scheduleReminder(minutesBefore: Int) async {
        do {
            try await CalendarNotificationStore.scheduleNotification(
                for: event,
                minutesBefore: minutesBefore,
                preferences: preferences
            )
            reminderMessage = "Reminder set for \(EventPresentation.reminderLabel(minutesBefore: minutesBefore))."
        } catch {
            reminderMessage = error.localizedDescription
        }
    }

    private func makeShareImage() -> UIImage {
        let renderer = ImageRenderer(
            content: EventShareCard(event: event, preferences: preferences, categoryDisplayName: categoryDisplayName)
        )
        renderer.scale = displayScale
        return renderer.uiImage ?? UIImage()
    }

    private var reminderAlertBinding: Binding<Bool> {
        Binding(
            get: { reminderMessage != nil },
            set: { isPresented in
                if !isPresented {
                    reminderMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private var detailMetrics: some View {
        if let forecast = event.forecast {
            DetailValueColumn(title: "Forecast", primaryValue: forecast)
        }

        if let previous = event.previous {
            DetailValueColumn(title: "Previous", primaryValue: previous)
        }

        if !event.isHoliday {
            DetailValueColumn(
                title: "Actual",
                primaryValue: event.actual ?? EventPresentation.actualResultsPlaceholderShort,
                secondaryValue: event.actual == nil ? EventPresentation.actualResultsPlaceholderLong : nil
            )
        }
    }

    private var metricEmptyState: some View {
        Text(event.isHoliday ? "Market holidays do not have forecast or previous values." : "No forecast, previous, or actual values are available for this event.")
            .font(.subheadline)
            .foregroundStyle(FXNewsPalette.muted)
    }
}

private struct EventMetric: View {
    let label: String
    let value: String?
    var animateUpdates = false
    @State private var flashOpacity: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(FXNewsPalette.muted)

            Text(value ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(FXNewsPalette.text)
                .contentTransition(.opacity)
                .animation(animateUpdates ? .easeInOut(duration: 0.25) : nil, value: value ?? "—")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(flashColor.opacity(flashOpacity))
                }
        )
        .onAppear {
            triggerFlash()
        }
        .onChange(of: value ?? "—") { _, _ in
            triggerFlash()
        }
    }

    private var flashColor: Color {
        if label == "Actual", value != nil {
            return FXNewsPalette.success
        }

        return FXNewsPalette.accent
    }

    private func triggerFlash() {
        guard animateUpdates else { return }

        flashOpacity = 0.18
        withAnimation(.easeOut(duration: 0.45)) {
            flashOpacity = 0
        }
    }
}

private struct DetailValueColumn: View {
    let title: String
    let primaryValue: String
    var secondaryValue: String?
    var accentColor: Color = FXNewsPalette.text

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(FXNewsPalette.muted)

            Text(primaryValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let secondaryValue {
                Text(secondaryValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor == FXNewsPalette.text ? FXNewsPalette.muted : accentColor)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }
}

enum EventPresentation {
    static func categoryLabel(for rawCategory: String?) -> String {
        guard let rawCategory, !rawCategory.isEmpty else {
            return "Macroeconomic"
        }

        return rawCategory
            .split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    static func countdownString(to date: Date, now: Date) -> String {
        let remaining = max(Int(date.timeIntervalSince(now)), 0)
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return "Releases in \(hours)h \(minutes)m"
    }

    static func reminderLabel(minutesBefore: Int) -> String {
        switch minutesBefore {
        case 60:
            "1 hour before"
        case 1:
            "1 minute before"
        default:
            "\(minutesBefore) minutes before"
        }
    }

    static let actualResultsPlaceholderShort = "Pending"
    static let actualResultsPlaceholderLong = "The official result has not been published here yet."

    static func actualResultLabel(for event: EconomicEvent) -> String {
        switch actualComparison(for: event) {
        case .better:
            "Better than forecast"
        case .worse:
            "Worse than forecast"
        case .neutral:
            "In line with forecast"
        case .unknown:
            "Released"
        }
    }

    static func actualResultColor(for event: EconomicEvent) -> Color {
        switch actualComparison(for: event) {
        case .better:
            .green
        case .worse:
            .red
        case .neutral, .unknown:
            FXNewsPalette.text
        }
    }

    static func explainer(for event: EconomicEvent) -> String {
        let currency = event.currencyCode
        let title = event.title.localizedLowercase

        if event.isHoliday {
            return "Holiday closures reduce participation from \(currency)-linked banks and desks, which can thin liquidity and distort normal session behavior. Price action may be slower for part of the day and then become jumpier when liquidity returns. Treat these sessions differently from standard low-impact data releases because the main effect is market availability, not a forecast miss."
        }

        if title.contains("cpi") || title.contains("inflation") {
            return "The Consumer Price Index tracks how quickly consumer prices are rising across the economy. A hotter reading than expected usually pushes rate expectations higher and can move \(currency) pairs sharply. This is one of the most market-moving inflation releases on the calendar."
        }

        if title.contains("payroll") || title.contains("earnings") || title.contains("claimant") || title.contains("jobless") {
            return "Labor-market releases show how tight employment conditions are and how much wage pressure is building. Stronger-than-expected employment data often supports \(currency) by reinforcing growth and policy expectations. Traders watch these prints closely because they can reprice rate cuts or hikes very quickly."
        }

        if title.contains("rate") || title.contains("policy") || title.contains("fomc") || title.contains("ecb") || title.contains("boj") || title.contains("rba") || title.contains("minutes") || title.contains("speaks") {
            return "Central-bank events matter because they shift the expected path of interest rates and liquidity. Hawkish surprises are typically supportive for \(currency), while dovish guidance can weigh on it. These releases often trigger the cleanest moves when the market is leaning the wrong way."
        }

        if title.contains("gdp") || title.contains("retail sales") || title.contains("pmi") || title.contains("sentiment") {
            return "This release gives traders a fast read on economic momentum and domestic demand. Stronger-than-expected growth data is usually supportive for \(currency) because it can lift yields and policy expectations. It tends to matter most when the market is already focused on growth risk."
        }

        if title.contains("trade balance") {
            return "Trade-balance data shows whether an economy is importing more than it exports or vice versa. A stronger balance can be supportive for \(currency) because it implies steadier external demand. The impact is usually cleaner when it materially misses expectations."
        }

        return "This release helps traders judge the current economic backdrop and how central banks may react next. Surprises versus forecast tend to matter more than the absolute number, especially when positioning is crowded. Expect the biggest reaction in the pairs listed below if the print materially deviates from consensus."
    }

    private static func actualComparison(for event: EconomicEvent) -> ActualComparison {
        guard
            let actualValue = numericValue(from: event.actual),
            let forecastValue = numericValue(from: event.forecast)
        else {
            return event.actual == nil ? .unknown : .neutral
        }

        if abs(actualValue - forecastValue) < 0.0001 {
            return .neutral
        }

        let higherIsBetter = directionalBias(for: event) == .higherIsBetter
        if actualValue > forecastValue {
            return higherIsBetter ? .better : .worse
        } else {
            return higherIsBetter ? .worse : .better
        }
    }

    private static func directionalBias(for event: EconomicEvent) -> DirectionalBias {
        let title = event.title.localizedLowercase
        let category = (event.category ?? "").localizedLowercase

        if title.contains("cpi")
            || title.contains("inflation")
            || title.contains("jobless")
            || title.contains("claimant")
            || title.contains("unemployment")
        {
            return .lowerIsBetter
        }

        if category.contains("labor"), title.contains("earnings") == false {
            return .lowerIsBetter
        }

        return .higherIsBetter
    }

    private static func numericValue(from string: String?) -> Double? {
        guard let string else {
            return nil
        }

        let filtered = string
            .replacingOccurrences(of: ",", with: "")
            .filter { "-.0123456789".contains($0) }

        return Double(filtered)
    }

    private enum DirectionalBias {
        case higherIsBetter
        case lowerIsBetter
    }

    private enum ActualComparison {
        case better
        case worse
        case neutral
        case unknown
    }
}

private struct CustomReminderSheet: View {
    let event: EconomicEvent
    @Binding var minutesBefore: Int
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose when you want the reminder before \(event.title).")
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                Picker("Reminder lead time", selection: $minutesBefore) {
                    ForEach([5, 10, 15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                        Text(EventPresentation.reminderLabel(minutesBefore: minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.wheel)

                Button("Set Reminder") {
                    onConfirm(minutesBefore)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(FXNewsPalette.accent)
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Custom Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct EventShareCard: View {
    let event: EconomicEvent
    let preferences: UserPreferences
    let categoryDisplayName: String

    var body: some View {
        ZStack {
            FXNewsPalette.backgroundTop

            VStack(alignment: .leading, spacing: 20) {
                Text("FX News")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(FXNewsPalette.muted)

                Text(event.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)

                HStack(spacing: 10) {
                    FXNewsPill(text: "Affects \(event.currencyCode)", tint: FXNewsPalette.accentSoft)
                    FXNewsPill(
                        text: event.isHoliday ? "Holiday" : event.impactLevel.label,
                        tint: event.isHoliday ? FXNewsPalette.surfaceStrong : event.impactLevel.color.opacity(0.18)
                    )
                    FXNewsPill(text: categoryDisplayName)
                }

                Text(EventDateFormatter.dayString(from: event.timestamp, timeZone: preferences.effectiveTimeZone))
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text(EventDateFormatter.timeString(from: event.timestamp, timeZone: preferences.effectiveTimeZone, use24HourTime: preferences.use24HourTime))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.accent)

                if shareMetricItems.isEmpty {
                    Text(event.isHoliday ? "Market holiday" : "No forecast or previous data")
                        .font(.headline)
                        .foregroundStyle(FXNewsPalette.muted)
                } else {
                    HStack(spacing: 12) {
                        ForEach(shareMetricItems, id: \.title) { metric in
                            shareMetric(title: metric.title, value: metric.value)
                        }
                    }
                }
            }
            .padding(28)
        }
        .frame(width: 1080, height: 1350)
    }

    private var shareMetricItems: [(title: String, value: String)] {
        var items: [(title: String, value: String)] = []

        if let forecast = event.forecast {
            items.append((title: "Forecast", value: forecast))
        }

        if let previous = event.previous {
            items.append((title: "Previous", value: previous))
        }

        if !event.isHoliday {
            items.append((title: "Actual", value: event.actual ?? EventPresentation.actualResultsPlaceholderShort))
        }

        return items
    }

    private func shareMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(FXNewsPalette.muted)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(FXNewsPalette.text)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(FXNewsPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct FilterMenuLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FXNewsPalette.muted)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(FXNewsPalette.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }
}

private struct DaySection: Identifiable {
    let day: Date
    let events: [EconomicEvent]
    let isToday: Bool

    var id: Date { day }
}

private enum CalendarEmptyState {
    case filters
    case noData
    case offline

    var title: String {
        switch self {
        case .filters:
            "No matching events"
        case .noData:
            "No calendar data"
        case .offline:
            "You're offline"
        }
    }

    var message: String {
        switch self {
        case .filters:
            "No events match your filters this week. Try showing more impact levels."
        case .noData:
            "Pull down to refresh the calendar."
        case .offline:
            "You're offline. Connect to load this week's events."
        }
    }
}

enum CalendarNotificationStore {
    private static let identifierPrefix = "fxnews.calendar-event."
    private static let defaultIdentifierPrefix = "fxnews.calendar-default."

    static func scheduledEventIDs() async -> Set<String> {
        let requests = await pendingRequests()
        return Set(requests.compactMap { request in
            guard request.identifier.hasPrefix(identifierPrefix) else {
                return nil
            }

            let suffix = String(request.identifier.dropFirst(identifierPrefix.count))
            return suffix.components(separatedBy: ".").first
        })
    }

    static func syncDefaultNotifications(for events: [EconomicEvent], preferences: UserPreferences) async {
        guard await NotificationAuthorizationStore.canScheduleNotificationsWithoutPrompt() else {
            return
        }

        let requests = await pendingRequests()
        let existingDefaultIdentifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(defaultIdentifierPrefix) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: existingDefaultIdentifiers)

        let upcomingSchedules = events.compactMap { event -> EventNotificationSchedule? in
            guard let leadTime = defaultLeadTime(for: event.impactLevel, preferences: preferences), leadTime > 0 else {
                return nil
            }

            let fireDate = event.timestamp.addingTimeInterval(TimeInterval(-leadTime * 60))
            guard event.timestamp > Date(), fireDate > Date(), !preferences.isWithinQuietHours(on: fireDate) else {
                return nil
            }

            return EventNotificationSchedule(event: event, leadTimeMinutes: leadTime, fireDate: fireDate)
        }

        guard !upcomingSchedules.isEmpty else {
            return
        }

        let groupedSchedules = Dictionary(grouping: upcomingSchedules) { schedule in
            Calendar.current.dateInterval(of: .hour, for: schedule.fireDate)?.start ?? schedule.fireDate
        }

        for (_, schedules) in groupedSchedules {
            if schedules.count > 1 {
                try? await scheduleGroupedNotification(for: schedules, preferences: preferences)
            } else if let schedule = schedules.first {
                try? await scheduleDefaultNotification(for: schedule, preferences: preferences)
            }
        }
    }

    static func toggleNotification(for event: EconomicEvent, isScheduled: Bool, preferences: UserPreferences) async throws -> Bool {
        if isScheduled {
            await removeNotification(for: event)
            return false
        }

        try await scheduleNotification(for: event, minutesBefore: 0, preferences: preferences)
        return true
    }

    static func scheduleNotification(for event: EconomicEvent, minutesBefore: Int, preferences: UserPreferences) async throws {
        let center = UNUserNotificationCenter.current()
        let reminderDate = event.timestamp.addingTimeInterval(TimeInterval(-minutesBefore * 60))

        guard event.timestamp > Date() else {
            throw CalendarNotificationError.eventAlreadyStarted
        }

        guard reminderDate > Date() else {
            throw CalendarNotificationError.reminderTimePassed
        }

        guard !preferences.isWithinQuietHours(on: reminderDate) else {
            throw CalendarNotificationError.quietHoursBlocked
        }

        let granted = try await requestAuthorization()
        guard granted else {
            throw CalendarNotificationError.authorizationDenied
        }

        await removeNotification(for: event)

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = reminderBody(for: event, minutesBefore: minutesBefore)
        content.sound = preferences.notificationSoundOption.unNotificationSound

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(reminderDate.timeIntervalSinceNow, 1),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: identifier(for: event.id, minutesBefore: minutesBefore),
            content: content,
            trigger: trigger
        )
        try await add(request, to: center)
    }

    static func removeNotification(for event: EconomicEvent) async {
        let requests = await pendingRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix + event.id) }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    private static func requestAuthorization() async throws -> Bool {
        try await NotificationAuthorizationStore.requestAuthorizationIfNeeded()
    }

    private static func add(_ request: UNNotificationRequest, to center: UNUserNotificationCenter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func identifier(for eventID: String, minutesBefore: Int) -> String {
        "\(identifierPrefix)\(eventID).\(minutesBefore)"
    }

    private static func reminderBody(for event: EconomicEvent, minutesBefore: Int) -> String {
        if minutesBefore == 0 {
            return "\(event.currencyCode) releases now."
        }

        return "\(event.currencyCode) releases in \(EventPresentation.reminderLabel(minutesBefore: minutesBefore).replacingOccurrences(of: " before", with: ""))."
    }

    private static func defaultLeadTime(for impactLevel: ImpactLevel, preferences: UserPreferences) -> Int? {
        switch impactLevel {
        case .high:
            preferences.highImpactNotificationLeadTimeMinutes
        case .medium:
            preferences.mediumImpactNotificationLeadTimeMinutes
        case .low:
            preferences.lowImpactNotificationLeadTimeMinutes
        }
    }

    private static func scheduleDefaultNotification(for schedule: EventNotificationSchedule, preferences: UserPreferences) async throws {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "\(CountryDisplay.flag(for: schedule.event.countryCode)) \(schedule.event.title) in \(schedule.leadTimeMinutes) min"
        content.body = defaultBody(for: schedule.event, leadTimeMinutes: schedule.leadTimeMinutes, preferences: preferences)
        content.sound = preferences.notificationSoundOption.unNotificationSound
        content.threadIdentifier = "fxnews.default.event"
        content.userInfo = [
            "eventID": schedule.event.id,
            "targetTab": AppTab.calendar.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "\(defaultIdentifierPrefix)\(schedule.event.id).\(schedule.leadTimeMinutes)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(schedule.fireDate.timeIntervalSinceNow, 1), repeats: false)
        )
        try await add(request, to: center)
    }

    private static func scheduleGroupedNotification(for schedules: [EventNotificationSchedule], preferences: UserPreferences) async throws {
        guard let earliest = schedules.min(by: { $0.fireDate < $1.fireDate }) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        let sorted = schedules.sorted { $0.event.timestamp < $1.event.timestamp }
        let content = UNMutableNotificationContent()
        content.title = groupedTitle(for: sorted, preferences: preferences)
        content.body = groupedBody(for: sorted)
        content.sound = preferences.notificationSoundOption.unNotificationSound
        content.threadIdentifier = "fxnews.default.group"
        content.userInfo = [
            "eventID": earliest.event.id,
            "targetTab": AppTab.calendar.rawValue
        ]

        let hourBucket = Calendar.current.dateInterval(of: .hour, for: earliest.fireDate)?.start.timeIntervalSince1970 ?? earliest.fireDate.timeIntervalSince1970
        let request = UNNotificationRequest(
            identifier: "\(defaultIdentifierPrefix)group.\(Int(hourBucket))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(earliest.fireDate.timeIntervalSinceNow, 1), repeats: false)
        )
        try await add(request, to: center)
    }

    private static func defaultBody(for event: EconomicEvent, leadTimeMinutes: Int, preferences: UserPreferences) -> String {
        let watchedPairs = event.relatedPairs.filter { preferences.watchedPairSymbols.contains($0) }

        if event.isHoliday {
            if watchedPairs.isEmpty {
                return "Liquidity may be thinner around this market holiday."
            }

            let pairList = watchedPairs.prefix(2).joined(separator: " and ")
            return "Your \(pairList) pairs may be affected by thinner holiday liquidity."
        }

        let forecast = event.forecast ?? "—"
        let previous = event.previous ?? "—"

        if watchedPairs.isEmpty {
            return "Forecast: \(forecast) | Previous: \(previous)"
        }

        let pairList = watchedPairs.prefix(2).joined(separator: " and ")
        return "Your \(pairList) pairs may be affected. Forecast: \(forecast) | Previous: \(previous)"
    }

    private static func groupedTitle(for schedules: [EventNotificationSchedule], preferences: UserPreferences) -> String {
        let highImpactCount = schedules.filter { $0.event.impactLevel == .high }.count
        let titlePrefix = highImpactCount == schedules.count ? "\(schedules.count) high-impact events" : "\(schedules.count) events"
        let start = EventDateFormatter.timeString(from: schedules.first?.event.timestamp ?? Date(), timeZone: preferences.effectiveTimeZone, use24HourTime: preferences.use24HourTime)
        let end = EventDateFormatter.timeString(from: schedules.last?.event.timestamp ?? Date(), timeZone: preferences.effectiveTimeZone, use24HourTime: preferences.use24HourTime)
        return "\(titlePrefix) between \(start)-\(end)"
    }

    private static func groupedBody(for schedules: [EventNotificationSchedule]) -> String {
        schedules
            .prefix(3)
            .map { $0.event.title }
            .joined(separator: ", ")
    }
}

private struct EventNotificationSchedule {
    let event: EconomicEvent
    let leadTimeMinutes: Int
    let fireDate: Date
}

private enum CalendarNotificationError: LocalizedError {
    case authorizationDenied
    case eventAlreadyStarted
    case reminderTimePassed
    case quietHoursBlocked

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Notifications are disabled for FX News."
        case .eventAlreadyStarted:
            "This event has already started, so a reminder cannot be scheduled."
        case .reminderTimePassed:
            "That reminder time has already passed for this event."
        case .quietHoursBlocked:
            "That reminder falls within your quiet hours."
        }
    }
}

private struct TodayHeaderOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat?

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
