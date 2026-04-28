import SwiftUI

@MainActor
struct PairsPlaceholderView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences

    @State private var isShowingWatchlistEditor = false

    private let pairCategories = PairCatalogCategory.allCases

    private var selectedPairs: [String] {
        preferences.watchedPairSymbols.sorted()
    }

    private var watchedPairSummaries: [PairDashboardSummary] {
        selectedPairs
            .map { symbol in
                PairDashboardSummary(
                    symbol: symbol,
                    events: viewModel.events(forPair: symbol).sorted { $0.timestamp < $1.timestamp }
                )
            }
            .sorted(by: PairDashboardSummary.priorityOrder)
    }

    private var upcomingCatalysts: [PairCatalyst] {
        watchedPairSummaries
            .flatMap { summary in
                summary.upcomingEvents.map { event in
                    PairCatalyst(symbol: summary.symbol, event: event)
                }
            }
            .sorted { lhs, rhs in
                if lhs.event.timestamp != rhs.event.timestamp {
                    return lhs.event.timestamp < rhs.event.timestamp
                }

                return lhs.symbol < rhs.symbol
            }
    }

    private var nextCatalyst: PairCatalyst? {
        upcomingCatalysts.first
    }

    private var highImpactEventsForSelectedPairs: Int {
        Set(watchedPairSummaries.flatMap { summary in
            summary.events.filter { $0.impactLevel == .high }.map(\.id)
        }).count
    }

    private var activePairCount: Int {
        watchedPairSummaries.filter { !$0.events.isEmpty }.count
    }

    private var totalEventsForSelectedPairs: Int {
        watchedPairSummaries.reduce(0) { $0 + $1.events.count }
    }

    private var bodySubtitle: String {
        if selectedPairs.isEmpty {
            return "Track the pairs you trade and see which catalysts matter most this week."
        }

        if nextCatalyst != nil {
            return "See which scheduled events matter most for the pairs you trade."
        }

        return "Your watchlist is set. This week is quiet across the pairs you follow."
    }

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Pair Impact",
                        title: "My Pairs",
                        subtitle: bodySubtitle
                    )

                    weeklySummaryCard
                    focusSection
                    catalystsSection
                    watchlistSection
                }
            }
        }
        .background(Color.clear)
        .overlay {
            if viewModel.isLoading && viewModel.events.isEmpty {
                ProgressView("Loading pair impact...")
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
                Text("FXNews")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(manageWatchlistButtonTitle) {
                    isShowingWatchlistEditor = true
                }
                .tint(FXNewsPalette.accent)
            }
        }
        .task {
            guard viewModel.events.isEmpty else { return }
            await viewModel.refresh()
        }
        .refreshable {
            await viewModel.refresh()
            FXNewsHaptics.success()
        }
        .sheet(isPresented: $isShowingWatchlistEditor) {
            NavigationStack {
                WatchlistEditorView(
                    preferences: preferences,
                    pairCategories: pairCategories,
                    pairEvents: { symbol in
                        viewModel.events(forPair: symbol)
                    }
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .animation(.easeInOut(duration: 0.18), value: selectedPairs)
        .animation(.easeInOut(duration: 0.18), value: watchedPairSummaries.map(\.id))
    }

    private var weeklySummaryCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 18) {
                Text(summaryTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)

                Text(summarySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                PairExposureOverviewBar(summaries: watchedPairSummaries)

                if let nextCatalyst {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(FXNewsPalette.accent)

                        Text("Next: \(nextCatalyst.symbol) • \(nextCatalyst.event.title) • \(nextCatalystValue)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FXNewsPalette.text)
                            .lineLimit(2)
                    }
                } else {
                    Text("Add a few pairs to turn the calendar into a personalized catalyst view.")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                }
            }
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if watchedPairSummaries.isEmpty {
                FXNewsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No watched pairs yet")
                            .font(.headline)
                            .foregroundStyle(FXNewsPalette.text)

                        Text("Select the pairs you trade and FXNews will surface the events that matter most this week.")
                            .font(.subheadline)
                            .foregroundStyle(FXNewsPalette.muted)

                        Button("Build watchlist") {
                            isShowingWatchlistEditor = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FXNewsPalette.accent)
                        )
                    }
                }
            } else {
                FXNewsCard {
                    VStack(spacing: 4) {
                        ForEach(Array(watchedPairSummaries.enumerated()), id: \.element.id) { index, summary in
                            NavigationLink {
                                PairEventsView(summary: summary, preferences: preferences)
                            } label: {
                                PairExposureRow(summary: summary, preferences: preferences)
                            }
                            .buttonStyle(.plain)

                            if index < watchedPairSummaries.count - 1 {
                                Divider()
                                    .overlay(FXNewsPalette.stroke)
                                    .padding(.leading, 66)
                            }
                        }
                    }
                }
            }
        }
    }

    private var catalystsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Calendar Impact Ahead",
                subtitle: selectedPairs.isEmpty
                    ? "Your upcoming event feed will appear here once you start following pairs."
                    : "Upcoming releases affecting your watchlist."
            )

            if upcomingCatalysts.isEmpty {
                FXNewsCard {
                    Text(selectedPairs.isEmpty
                        ? "Start with a few pairs to see a timeline of upcoming catalysts."
                        : "No scheduled releases are affecting your watched pairs right now.")
                        .font(.subheadline)
                        .foregroundStyle(FXNewsPalette.muted)
                }
            } else {
                FXNewsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(upcomingCatalysts.prefix(6).enumerated()), id: \.element.id) { index, catalyst in
                            PairCatalystTimelineRow(
                                catalyst: catalyst,
                                preferences: preferences,
                                showsConnector: index < min(upcomingCatalysts.count, 6) - 1
                            )

                            if index < min(upcomingCatalysts.count, 6) - 1 {
                                Divider()
                                    .overlay(FXNewsPalette.stroke)
                                    .padding(.leading, 78)
                            }
                        }
                    }
                }
            }
        }
    }

    private var watchlistSection: some View {
        FXNewsCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Watchlist")
                        .font(.headline)
                        .foregroundStyle(FXNewsPalette.text)

                    Text(watchlistSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(FXNewsPalette.muted)
                }

                Spacer()

                Button(selectedPairs.isEmpty ? "Add pairs" : "Manage") {
                    isShowingWatchlistEditor = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(FXNewsPalette.accent)
                )
            }
        }
    }

    private var summaryTitle: String {
        if selectedPairs.isEmpty {
            return "Turn the calendar into a pair-focused trading view"
        }

        if highImpactEventsForSelectedPairs > 0 {
            return "\(highImpactEventsForSelectedPairs) high-impact catalysts are lined up for your pairs"
        }

        if activePairCount > 0 {
            return "\(activePairCount) of your pairs have scheduled releases this week"
        }

        return "Your watched pairs are quiet this week"
    }

    private var summarySubtitle: String {
        if selectedPairs.isEmpty {
            return "Build a watchlist to see which events matter most to the instruments you trade."
        }

        if let nextCatalyst {
            return "\(selectedPairs.count) pairs watched, \(highImpactEventsForSelectedPairs) high-impact catalysts this week. Next is \(nextCatalyst.symbol) \(EventDateFormatter.relativeString(for: nextCatalyst.event.timestamp))."
        }

        if totalEventsForSelectedPairs == 0 {
            return "No scheduled events in the current feed affect your watched pairs."
        }

        return "\(totalEventsForSelectedPairs) total events are mapped across your watchlist this week."
    }

    private var nextCatalystValue: String {
        guard let nextCatalyst else {
            return "None"
        }

        return EventDateFormatter.relativeString(for: nextCatalyst.event.timestamp)
    }

    private var watchlistSummaryText: String {
        if selectedPairs.isEmpty {
            return "No pairs selected yet."
        }

        return "\(selectedPairs.count) watched • feeds calendar filters, alerts, and this impact view."
    }

    private var manageWatchlistButtonTitle: String {
        horizontalSizeClass == .regular ? "Manage Watchlists" : "Manage"
    }

    private func sectionHeader<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)
            }

            Spacer()

            accessory()
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        sectionHeader(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

private struct PairExposureRow: View {
    let summary: PairDashboardSummary
    let preferences: UserPreferences

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(summary.symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ImpactDotsRow(summary: summary)
                    Text(summary.exposureLabelShort)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.primaryImpactColor)
                }

                PairExposureBar(summary: summary)

                if let event = summary.nextEvent {
                    Text("\(event.title) • \(eventMetadata(for: event))")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                        .lineLimit(1)
                } else {
                    Text("No upcoming catalysts scheduled.")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(summary.nextEventRelativeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)

                if let event = summary.nextEvent {
                    Text(EventDateFormatter.timeString(
                        from: event.timestamp,
                        timeZone: preferences.effectiveTimeZone,
                        use24HourTime: preferences.use24HourTime
                    ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(FXNewsPalette.muted)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FXNewsPalette.muted)
            }
        }
        .padding(.vertical, 12)
    }

    private func eventMetadata(for event: EconomicEvent) -> String {
        let day = EventDateFormatter.dayString(from: event.timestamp, timeZone: preferences.effectiveTimeZone)
        let category = EventPresentation.categoryLabel(for: event.category)
        return "\(day) • \(category) • \(event.currencyCode)"
    }
}

private struct PairExposureOverviewBar: View {
    let summaries: [PairDashboardSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(summaries) { summary in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(summary.primaryImpactColor.opacity(summary.events.isEmpty ? 0.18 : 0.82))
                        .frame(maxWidth: .infinity)
                        .frame(height: 10)
                        .layoutPriority(summary.visualWeight)
                }
            }
            .frame(maxWidth: .infinity)

            if !summaries.isEmpty {
                HStack(spacing: 10) {
                    ForEach(summaries.prefix(4)) { summary in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(summary.primaryImpactColor)
                                .frame(width: 8, height: 8)

                            Text(summary.symbol)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(FXNewsPalette.muted)
                        }
                    }
                }
            }
        }
    }
}

private struct PairExposureBar: View {
    let summary: PairDashboardSummary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(FXNewsPalette.surfaceStrong)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [summary.primaryImpactColor.opacity(0.55), summary.primaryImpactColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * summary.normalizedIntensity, 8))
            }
        }
        .frame(height: 8)
    }
}

private struct ImpactDotsRow: View {
    let summary: PairDashboardSummary

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func color(for index: Int) -> Color {
        if index < summary.highImpactCount {
            return ImpactLevel.high.color
        }

        if index < summary.highImpactCount + min(summary.mediumImpactCount, max(0, 3 - summary.highImpactCount)) {
            return ImpactLevel.medium.color
        }

        if !summary.events.isEmpty {
            return ImpactLevel.low.color.opacity(0.85)
        }

        return FXNewsPalette.stroke
    }
}

private struct PairCatalystTimelineRow: View {
    let catalyst: PairCatalyst
    let preferences: UserPreferences
    let showsConnector: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(EventDateFormatter.timeString(
                    from: catalyst.event.timestamp,
                    timeZone: preferences.effectiveTimeZone,
                    use24HourTime: preferences.use24HourTime
                ))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

                Text(EventDateFormatter.relativeString(for: catalyst.event.timestamp))
                    .font(.caption2)
                    .foregroundStyle(FXNewsPalette.muted)
            }
            .frame(width: 56, alignment: .trailing)

            VStack(spacing: 0) {
                Circle()
                    .fill(catalyst.event.impactLevel.color)
                    .frame(width: 12, height: 12)

                if showsConnector {
                    Rectangle()
                        .fill(FXNewsPalette.stroke)
                        .frame(width: 1, height: 44)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(catalyst.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Text(catalyst.event.impactLevel.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(catalyst.event.impactLevel.color)
                }

                Text(catalyst.event.title)
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.text)

                Text("\(EventDateFormatter.dayString(from: catalyst.event.timestamp, timeZone: preferences.effectiveTimeZone)) • \(catalyst.event.currencyCode)")
                    .font(.caption)
                    .foregroundStyle(FXNewsPalette.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

private struct WatchlistEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let preferences: UserPreferences
    let pairCategories: [PairCatalogCategory]
    let pairEvents: (String) -> [EconomicEvent]

    private var selectedPairs: [String] {
        preferences.watchedPairSymbols.sorted()
    }

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Watchlist",
                        title: "Manage Pairs",
                        subtitle: "Choose the instruments that should shape your calendar, catalysts, and notifications."
                    )

                    FXNewsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Current watchlist")
                                    .font(.headline)
                                    .foregroundStyle(FXNewsPalette.text)

                                Spacer()

                                if !selectedPairs.isEmpty {
                                    Button("Clear all") {
                                        preferences.watchedPairSymbols = []
                                        FXNewsHaptics.selection()
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FXNewsPalette.accent)
                                }
                            }

                            if selectedPairs.isEmpty {
                                Text("No pairs selected yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(FXNewsPalette.muted)
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], alignment: .leading, spacing: 10) {
                                    ForEach(selectedPairs, id: \.self) { symbol in
                                        FXNewsPill(text: symbol)
                                    }
                                }
                            }
                        }
                    }

                    ForEach(pairCategories) { category in
                        FXNewsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(category.title)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(FXNewsPalette.text)

                                    Spacer()

                                    FXNewsPill(text: "\(category.pairs.count) pairs")
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], alignment: .leading, spacing: 10) {
                                    ForEach(category.pairs) { pair in
                                        Button {
                                            preferences.toggleWatch(for: pair.symbol)
                                            FXNewsHaptics.selection()
                                        } label: {
                                            PairSelectionChip(
                                                pair: pair,
                                                isSelected: preferences.isPairWatched(pair.symbol),
                                                hasEvents: !pairEvents(pair.symbol).isEmpty
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
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    dismiss()
                }
                .tint(FXNewsPalette.accent)
            }
        }
    }
}

struct PairSelectionChip: View {
    let pair: PairCatalogPair
    let isSelected: Bool
    let hasEvents: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pair.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white : FXNewsPalette.text)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.white : FXNewsPalette.muted)
            }

            Text(pair.description)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.white.opacity(0.84) : FXNewsPalette.muted)
                .lineLimit(1)

            if hasEvents {
                Text("This week")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.84) : FXNewsPalette.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? FXNewsPalette.accent : FXNewsPalette.surfaceStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: isSelected ? 0 : 1)
                }
        )
    }
}

private struct PairEventsView: View {
    let summary: PairDashboardSummary
    let preferences: UserPreferences

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Impact Detail",
                        title: summary.symbol,
                        subtitle: "\(summary.highImpactCount) high-impact event\(summary.highImpactCount == 1 ? "" : "s") this week"
                    )

                    FXNewsCard {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: FXNewsLayout.compactItemSpacing) {
                                FXNewsMetricCard(title: "Upcoming", value: "\(summary.upcomingEvents.count)")
                                FXNewsMetricCard(title: "High impact", value: "\(summary.highImpactCount)")
                                FXNewsMetricCard(title: "This week", value: "\(summary.events.count)")
                            }

                            VStack(spacing: FXNewsLayout.compactItemSpacing) {
                                FXNewsMetricCard(title: "Upcoming", value: "\(summary.upcomingEvents.count)")
                                FXNewsMetricCard(title: "High impact", value: "\(summary.highImpactCount)")
                                FXNewsMetricCard(title: "This week", value: "\(summary.events.count)")
                            }
                        }
                    }

                    FXNewsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Events Affecting \(summary.symbol)")
                                .font(.headline)
                                .foregroundStyle(FXNewsPalette.text)

                            if summary.events.isEmpty {
                                Text("No events in the current calendar feed affect this pair.")
                                    .font(.subheadline)
                                    .foregroundStyle(FXNewsPalette.muted)
                            } else {
                                ForEach(summary.events) { event in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Circle()
                                                .fill(event.impactLevel.color)
                                                .frame(width: 10, height: 10)
                                                .padding(.top, 4)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(event.title)
                                                    .font(.headline)
                                                    .foregroundStyle(FXNewsPalette.text)

                                                Text("\(CountryDisplay.flag(for: event.countryCode)) \(event.currencyCode) • \(EventPresentation.categoryLabel(for: event.category))")
                                                    .font(.caption)
                                                    .foregroundStyle(FXNewsPalette.muted)
                                            }

                                            Spacer()

                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text(EventDateFormatter.dayString(from: event.timestamp, timeZone: preferences.effectiveTimeZone))
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(FXNewsPalette.muted)

                                                Text(EventDateFormatter.timeString(
                                                    from: event.timestamp,
                                                    timeZone: preferences.effectiveTimeZone,
                                                    use24HourTime: preferences.use24HourTime
                                                ))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(FXNewsPalette.text)
                                            }
                                        }

                                        if event.actual != nil || event.forecast != nil || event.previous != nil {
                                            HStack(spacing: 8) {
                                                PairEventValuePill(label: "Forecast", value: event.forecast ?? "—")
                                                PairEventValuePill(label: "Previous", value: event.previous ?? "—")
                                                PairEventValuePill(label: "Actual", value: event.actual ?? "—")
                                            }
                                        }

                                        if event.id != summary.events.last?.id {
                                            Divider()
                                                .overlay(FXNewsPalette.stroke)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PairEventValuePill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(FXNewsPalette.muted)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FXNewsPalette.surfaceStrong)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }
}

private struct PairCatalyst: Identifiable {
    let symbol: String
    let event: EconomicEvent

    var id: String {
        "\(symbol)-\(event.id)"
    }
}

private struct PairDashboardSummary: Identifiable {
    let symbol: String
    let events: [EconomicEvent]

    var id: String { symbol }

    var highImpactCount: Int {
        events.filter { $0.impactLevel == .high }.count
    }

    var mediumImpactCount: Int {
        events.filter { $0.impactLevel == .medium }.count
    }

    var upcomingEvents: [EconomicEvent] {
        events.filter { $0.timestamp >= Date() }
    }

    var nextEvent: EconomicEvent? {
        upcomingEvents.min { $0.timestamp < $1.timestamp }
    }

    var exposureLabel: String {
        if highImpactCount >= 2 {
            return "High Exposure"
        }

        if highImpactCount == 1 || mediumImpactCount >= 2 {
            return "Active Week"
        }

        if !events.isEmpty {
            return "On Watch"
        }

        return "Quiet"
    }

    var exposureLabelShort: String {
        if highImpactCount >= 2 {
            return "High"
        }

        if highImpactCount == 1 || mediumImpactCount >= 2 {
            return "Active"
        }

        if !events.isEmpty {
            return "Watch"
        }

        return "Quiet"
    }

    var primaryImpactColor: Color {
        if highImpactCount > 0 {
            return ImpactLevel.high.color
        }

        if mediumImpactCount > 0 {
            return ImpactLevel.medium.color
        }

        if !events.isEmpty {
            return FXNewsPalette.accent
        }

        return FXNewsPalette.muted
    }

    var exposureTint: Color {
        if highImpactCount >= 2 {
            return Color.red.opacity(0.18)
        }

        if highImpactCount == 1 || mediumImpactCount >= 2 {
            return Color.orange.opacity(0.18)
        }

        if !events.isEmpty {
            return FXNewsPalette.accentSoft.opacity(0.35)
        }

        return FXNewsPalette.surfaceStrong
    }

    var exposureDescription: String {
        if let nextEvent {
            return "Next catalyst \(EventDateFormatter.relativeString(for: nextEvent.timestamp))."
        }

        if events.isEmpty {
            return "No mapped events for this pair in the current calendar feed."
        }

        return "\(events.count) events mapped to this pair this week."
    }

    func statusHeadline(timeZone: TimeZone) -> String {
        if let nextEvent {
            return EventDateFormatter.dayString(from: nextEvent.timestamp, timeZone: timeZone)
        }

        return "No catalyst"
    }

    var nextEventRelativeLabel: String {
        guard let nextEvent else {
            return "None"
        }

        return EventDateFormatter.relativeString(for: nextEvent.timestamp)
    }

    var normalizedIntensity: CGFloat {
        let weightedScore = Double(highImpactCount * 3) + Double(mediumImpactCount * 2) + Double(max(events.count - highImpactCount - mediumImpactCount, 0))
        let normalized = min(max(weightedScore / 9.0, 0.12), 1.0)
        return CGFloat(events.isEmpty ? 0.08 : normalized)
    }

    var visualWeight: Double {
        Double(normalizedIntensity)
    }

    static func priorityOrder(lhs: PairDashboardSummary, rhs: PairDashboardSummary) -> Bool {
        let lhsNextTime = lhs.nextEvent?.timestamp ?? .distantFuture
        let rhsNextTime = rhs.nextEvent?.timestamp ?? .distantFuture

        if lhs.highImpactCount != rhs.highImpactCount {
            return lhs.highImpactCount > rhs.highImpactCount
        }

        if lhsNextTime != rhsNextTime {
            return lhsNextTime < rhsNextTime
        }

        if lhs.events.count != rhs.events.count {
            return lhs.events.count > rhs.events.count
        }

        return lhs.symbol < rhs.symbol
    }
}

struct PairCatalogPair: Identifiable, Hashable {
    let symbol: String
    let description: String

    var id: String { symbol }
}

enum PairCatalogCategory: String, CaseIterable, Identifiable {
    case majors
    case crosses
    case exotics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .majors:
            "Majors"
        case .crosses:
            "Crosses"
        case .exotics:
            "Exotics"
        }
    }

    var pairs: [PairCatalogPair] {
        switch self {
        case .majors:
            [
                .init(symbol: "EURUSD", description: "Euro / Dollar"),
                .init(symbol: "GBPUSD", description: "Pound / Dollar"),
                .init(symbol: "USDJPY", description: "Dollar / Yen"),
                .init(symbol: "USDCHF", description: "Dollar / Swissy"),
                .init(symbol: "AUDUSD", description: "Aussie / Dollar"),
                .init(symbol: "USDCAD", description: "Dollar / Loonie"),
                .init(symbol: "NZDUSD", description: "Kiwi / Dollar")
            ]
        case .crosses:
            [
                .init(symbol: "EURGBP", description: "Euro / Pound"),
                .init(symbol: "EURJPY", description: "Euro / Yen"),
                .init(symbol: "GBPJPY", description: "Pound / Yen"),
                .init(symbol: "AUDJPY", description: "Aussie / Yen"),
                .init(symbol: "CHFJPY", description: "Swissy / Yen"),
                .init(symbol: "EURAUD", description: "Euro / Aussie"),
                .init(symbol: "GBPAUD", description: "Pound / Aussie")
            ]
        case .exotics:
            [
                .init(symbol: "USDTRY", description: "Dollar / Lira"),
                .init(symbol: "USDZAR", description: "Dollar / Rand"),
                .init(symbol: "USDMXN", description: "Dollar / Peso"),
                .init(symbol: "EURTRY", description: "Euro / Lira"),
                .init(symbol: "GBPZAR", description: "Pound / Rand"),
                .init(symbol: "AUDMXN", description: "Aussie / Peso")
            ]
        }
    }
}

#Preview("My Pairs") {
    let preferences = UserPreferences()
    preferences.watchedPairSymbols = ["EURUSD", "GBPUSD", "USDJPY"]

    return NavigationStack {
        PairsPlaceholderView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: preferences
        )
    }
}

#Preview("My Pairs iPad") {
    let preferences = UserPreferences()
    preferences.watchedPairSymbols = ["EURUSD", "GBPUSD", "USDJPY"]

    return NavigationStack {
        PairsPlaceholderView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: preferences
        )
    }
    .frame(width: 834, height: 1194)
}
