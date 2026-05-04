import SwiftUI

@MainActor
struct PairsImpactView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences

    @State private var isShowingWatchlistEditor = false

    private let pairCategories = PairCatalogCategory.allCases

    private var selectedPairs: [String] {
        preferences.watchedPairSymbols.sorted()
    }

    private var watchedCurrencyPairCounts: [String: Int] {
        Dictionary(
            grouping: selectedPairs.flatMap { PairDashboardSummary.currencyCodes(in: $0) },
            by: { $0 }
        ).mapValues(\.count)
    }

    private var watchedPairSummaries: [PairDashboardSummary] {
        selectedPairs
            .map { symbol in
                PairDashboardSummary(
                    symbol: symbol,
                    events: viewModel.events(forPair: symbol).sorted { $0.timestamp < $1.timestamp }
                )
            }
            .sorted { lhs, rhs in
                PairDashboardSummary.priorityOrder(
                    lhs: lhs,
                    rhs: rhs,
                    currencyPairCounts: watchedCurrencyPairCounts
                )
            }
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

    private var currencyPressureSummaries: [CurrencyPressureSummary] {
        let currencies = Set(watchedPairSummaries.flatMap(\.currencies))

        return currencies
            .map { currency in
                let affectedPairs = watchedPairSummaries.filter { $0.currencies.contains(currency) }
                let uniqueEvents = Dictionary(
                    affectedPairs
                        .flatMap(\.events)
                        .filter { $0.currencyCode == currency }
                        .map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                return CurrencyPressureSummary(
                    currencyCode: currency,
                    pairSymbols: affectedPairs.map(\.symbol).sorted(),
                    events: uniqueEvents.values.sorted { $0.timestamp < $1.timestamp }
                )
            }
            .sorted(by: CurrencyPressureSummary.priorityOrder)
    }

    private var quietPairs: [PairDashboardSummary] {
        watchedPairSummaries.filter { $0.events.isEmpty }
    }

    private var quickHighlights: [String] {
        var items: [String] = []

        if let topPair = watchedPairSummaries.first {
            items.append("Top: \(topPair.symbol)")
        }

        if let topCurrency = currencyPressureSummaries.first, topCurrency.upcomingEventCount > 0 {
            items.append("Focus: \(topCurrency.currencyCode)")
        }

        if !quietPairs.isEmpty {
            items.append("Quiet: \(quietPairs.count)")
        }

        if items.isEmpty {
            items.append("Add pairs")
        }

        return items
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
            return "Track the pairs you trade and see which setups deserve attention this week."
        }

        if nextCatalyst != nil {
            return "Rank your setups, spot concentration, and see which pairs need attention first."
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
                    priorityBoardSection
                    riskConcentrationSection
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
                Text("FX News")
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
            VStack(alignment: .leading, spacing: 16) {
                Text(summaryTitle)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)

                PairExposureOverviewBar(
                    summaries: watchedPairSummaries,
                    currencyPairCounts: watchedCurrencyPairCounts
                )

                if !quickHighlights.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(quickHighlights, id: \.self) { item in
                                FXNewsPill(text: item, tint: FXNewsPalette.surfaceStrong)
                            }
                        }
                    }
                }
            }
        }
    }

    private var priorityBoardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if watchedPairSummaries.isEmpty {
                FXNewsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No watched pairs yet")
                            .font(.headline)
                            .foregroundStyle(FXNewsPalette.text)

                        Text("Select the pairs you trade and FX News will surface the events that matter most this week.")
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
                sectionHeader(
                    title: "Priority Board",
                    subtitle: "Glance view for your watched pairs."
                )

                LazyVStack(spacing: 12) {
                    ForEach(Array(watchedPairSummaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink {
                            PairNext24HoursView(
                                summary: summary,
                                preferences: preferences,
                                currencyPairCounts: watchedCurrencyPairCounts
                            )
                        } label: {
                            PairPriorityCard(
                                rank: index + 1,
                                summary: summary,
                                preferences: preferences,
                                currencyPairCounts: watchedCurrencyPairCounts
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var riskConcentrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Risk Concentration",
                subtitle: selectedPairs.isEmpty
                    ? "Book-level risk appears here once you follow pairs."
                    : "Where shared macro risk is concentrated."
            )

            if currencyPressureSummaries.isEmpty {
                FXNewsCard {
                    Text(selectedPairs.isEmpty
                        ? "Start with a few pairs to see where event pressure clusters."
                        : "No concentrated currency pressure is showing up in the current feed.")
                        .font(.subheadline)
                        .foregroundStyle(FXNewsPalette.muted)
                }
            } else {
                FXNewsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(currencyPressureSummaries.prefix(4).enumerated()), id: \.element.id) { index, summary in
                            CurrencyPressureRow(summary: summary, preferences: preferences)

                            if index < min(currencyPressureSummaries.count, 4) - 1 {
                                Divider()
                                    .overlay(FXNewsPalette.stroke)
                                    .padding(.leading, 62)
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
            return "Turn the calendar into a pair-focused trading desk"
        }

        if highImpactEventsForSelectedPairs > 0 {
            return "\(highImpactEventsForSelectedPairs) high-impact catalysts are shaping your book"
        }

        if activePairCount > 0 {
            return "\(activePairCount) of your watched pairs need attention this week"
        }

        return "Your watched pairs are quiet this week"
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

private struct PairPriorityCard: View {
    let rank: Int
    let summary: PairDashboardSummary
    let preferences: UserPreferences
    let currencyPairCounts: [String: Int]

    private var signal: PairDashboardSummary.SignalSummary? {
        summary.primarySignal(currencyPairCounts: currencyPairCounts)
    }

    var body: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("#\(rank)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FXNewsPalette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FXNewsPalette.accentSoft)
                        )

                    Text(summary.symbol)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(FXNewsPalette.text)

                    Spacer(minLength: 8)

                    HStack(spacing: 6) {
                        Text(summary.briefTimingLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(summary.accentColor(currencyPairCounts: currencyPairCounts))

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(FXNewsPalette.muted)
                    }
                }

                PairExposureBar(
                    summary: summary,
                    fillColor: summary.accentColor(currencyPairCounts: currencyPairCounts)
                )

                HStack(spacing: 8) {
                    if let signal {
                        PairCompactStat(label: "Signal", value: signal.label)
                    }

                    PairCompactStat(label: "Next", value: summary.nextEventTimeLabel(preferences: preferences))
                    PairCompactStat(label: "Pair", value: summary.currencyPairLabel)
                }
            }
        }
    }
}

private struct PairCompactStat: View {
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
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CurrencyPressureRow: View {
    let summary: CurrencyPressureSummary
    let preferences: UserPreferences

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(summary.tint)
                    .frame(width: 38, height: 38)

                Text(summary.currencyCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(summary.primaryColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(summary.headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    FXNewsPill(text: summary.urgencyLabel, tint: summary.tint.opacity(0.85))
                }

                Text(summary.description(preferences: preferences))
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                Text(summary.pairSymbols.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(FXNewsPalette.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }
}

private struct PairExposureOverviewBar: View {
    let summaries: [PairDashboardSummary]
    let currencyPairCounts: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(summaries) { summary in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(summary.accentColor(currencyPairCounts: currencyPairCounts).opacity(summary.events.isEmpty ? 0.18 : 0.82))
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
                                .fill(summary.accentColor(currencyPairCounts: currencyPairCounts))
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
    var fillColor: Color? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(FXNewsPalette.surfaceStrong)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [barColor.opacity(0.55), barColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * summary.normalizedIntensity, 8))
            }
        }
        .frame(height: 8)
    }

    private var barColor: Color {
        fillColor ?? summary.primaryImpactColor
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

private struct PairNext24HoursView: View {
    let summary: PairDashboardSummary
    let preferences: UserPreferences
    let currencyPairCounts: [String: Int]

    @State private var isShowingHelp = false

    private var primarySignal: PairDashboardSummary.SignalSummary? {
        summary.primarySignal(currencyPairCounts: currencyPairCounts)
    }

    private var focusEvents: [EconomicEvent] {
        summary.eventsInNext24Hours
    }

    private var laterWeekEvents: [EconomicEvent] {
        summary.eventsAfterNext24Hours
    }

    private var focusHeadline: String {
        if focusEvents.isEmpty {
            return "No catalysts in the next 24 hours"
        }

        if focusEvents.count == 1 {
            return "1 catalyst needs attention in the next 24 hours"
        }

        return "\(focusEvents.count) catalysts need attention in the next 24 hours"
    }

    private var groupedEvents: [PairEventDayGroup] {
        var calendar = Calendar.current
        calendar.timeZone = preferences.effectiveTimeZone

        return Dictionary(grouping: focusEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        .map { day, events in
            PairEventDayGroup(
                day: day,
                events: events.sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp {
                        return lhs.timestamp < rhs.timestamp
                    }

                    return lhs.impactLevel.rank > rhs.impactLevel.rank
                }
            )
        }
        .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Pair Focus",
                        title: summary.symbol,
                        subtitle: focusHeadline
                    )

                    FXNewsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            if let nextEvent = summary.nextEvent {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Next catalyst")
                                        .font(.caption.weight(.semibold))
                                        .tracking(1)
                                        .foregroundStyle(FXNewsPalette.muted)

                                    HStack(alignment: .top, spacing: 12) {
                                        Circle()
                                            .fill(nextEvent.impactLevel.color)
                                            .frame(width: 12, height: 12)
                                            .padding(.top, 5)

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(nextEvent.title)
                                                .font(.headline)
                                                .foregroundStyle(FXNewsPalette.text)

                                            Text(primarySignal?.reason ?? summary.exposureDescription)
                                                .font(.subheadline)
                                                .foregroundStyle(FXNewsPalette.muted)

                                            if let primarySignal {
                                                PairSignalPill(signal: primarySignal)
                                            }
                                        }
                                    }
                                }

                                Divider()
                                    .overlay(FXNewsPalette.stroke)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: FXNewsLayout.compactItemSpacing) {
                                    FXNewsMetricCard(title: "Next 24h", value: "\(focusEvents.count)")
                                    FXNewsMetricCard(title: "High impact", value: "\(focusEvents.filter { $0.impactLevel == .high }.count)")
                                    FXNewsMetricCard(title: "Later week", value: "\(laterWeekEvents.count)")
                                }

                                VStack(spacing: FXNewsLayout.compactItemSpacing) {
                                    FXNewsMetricCard(title: "Next 24h", value: "\(focusEvents.count)")
                                    FXNewsMetricCard(title: "High impact", value: "\(focusEvents.filter { $0.impactLevel == .high }.count)")
                                    FXNewsMetricCard(title: "Later week", value: "\(laterWeekEvents.count)")
                                }
                            }
                        }
                    }

                    FXNewsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Next 24 Hours")
                                .font(.headline)
                                .foregroundStyle(FXNewsPalette.text)

                            if focusEvents.isEmpty {
                                Text("Nothing in the current feed is scheduled to affect \(summary.symbol) in the next 24 hours.")
                                    .font(.subheadline)
                                    .foregroundStyle(FXNewsPalette.muted)
                            } else {
                                ForEach(groupedEvents) { group in
                                    PairEventDaySection(
                                        group: group,
                                        summary: summary,
                                        pairSymbol: summary.symbol,
                                        preferences: preferences,
                                        currencyPairCounts: currencyPairCounts
                                    )
                                }
                            }
                        }
                    }

                    if !laterWeekEvents.isEmpty {
                        NavigationLink {
                            PairEventsView(
                                summary: summary,
                                preferences: preferences,
                                currencyPairCounts: currencyPairCounts
                            )
                        } label: {
                            FXNewsCard {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Later This Week")
                                            .font(.headline)
                                            .foregroundStyle(FXNewsPalette.text)

                                        Text("\(laterWeekEvents.count) more event\(laterWeekEvents.count == 1 ? "" : "s") are scheduled after the next 24 hours.")
                                            .font(.subheadline)
                                            .foregroundStyle(FXNewsPalette.muted)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(FXNewsPalette.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.headline)
                }
                .tint(FXNewsPalette.accent)
                .accessibilityLabel("Explain pair focus")
            }
        }
        .sheet(isPresented: $isShowingHelp) {
            NavigationStack {
                PairFocusHelpView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct PairEventsView: View {
    let summary: PairDashboardSummary
    let preferences: UserPreferences
    let currencyPairCounts: [String: Int]

    private var groupedEvents: [PairEventDayGroup] {
        var calendar = Calendar.current
        calendar.timeZone = preferences.effectiveTimeZone

        return Dictionary(grouping: summary.events) { event in
            calendar.startOfDay(for: event.timestamp)
        }
        .map { day, events in
            PairEventDayGroup(
                day: day,
                events: events.sorted { lhs, rhs in
                    if lhs.timestamp != rhs.timestamp {
                        return lhs.timestamp < rhs.timestamp
                    }

                    return lhs.impactLevel.rank > rhs.impactLevel.rank
                }
            )
        }
        .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Week View",
                        title: summary.symbol,
                        subtitle: "\(summary.events.count) mapped event\(summary.events.count == 1 ? "" : "s") this week"
                    )

                    FXNewsCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Full week schedule")
                                .font(.headline)
                                .foregroundStyle(FXNewsPalette.text)

                            Text("Use this only when you want the complete weekly context for \(summary.symbol).")
                                .font(.subheadline)
                                .foregroundStyle(FXNewsPalette.muted)
                        }
                    }

                    FXNewsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            if summary.events.isEmpty {
                                Text("No events in the current calendar feed affect this pair.")
                                    .font(.subheadline)
                                    .foregroundStyle(FXNewsPalette.muted)
                            } else {
                                ForEach(groupedEvents) { group in
                                    PairEventDaySection(
                                        group: group,
                                        summary: summary,
                                        pairSymbol: summary.symbol,
                                        preferences: preferences,
                                        currencyPairCounts: currencyPairCounts
                                    )
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

private struct PairEventDaySection: View {
    let group: PairEventDayGroup
    let summary: PairDashboardSummary
    let pairSymbol: String
    let preferences: UserPreferences
    let currencyPairCounts: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(EventDateFormatter.dayString(from: group.day, timeZone: preferences.effectiveTimeZone))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)

                Spacer()

                Text("\(group.events.count) event\(group.events.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.muted)
            }

            VStack(spacing: 10) {
                ForEach(group.events) { event in
                    PairEventCard(
                        summary: summary,
                        event: event,
                        pairSymbol: pairSymbol,
                        preferences: preferences,
                        currencyPairCounts: currencyPairCounts
                    )
                }
            }
        }
    }
}

private struct PairEventCard: View {
    let summary: PairDashboardSummary
    let event: EconomicEvent
    let pairSymbol: String
    let preferences: UserPreferences
    let currencyPairCounts: [String: Int]

    private var signal: PairDashboardSummary.SignalSummary {
        summary.signal(for: event, currencyPairCounts: currencyPairCounts)
    }

    private var eventTimingLabel: String {
        EventDateFormatter.relativeString(for: event.timestamp)
    }

    private var eventTimeLabel: String {
        EventDateFormatter.timeString(
            from: event.timestamp,
            timeZone: preferences.effectiveTimeZone,
            use24HourTime: preferences.use24HourTime
        )
    }

    private var eventContext: [String] {
        [
            "\(CountryDisplay.flag(for: event.countryCode)) \(event.currencyCode)",
            EventPresentation.categoryLabel(for: event.category)
        ]
    }

    private var hasValues: Bool {
        event.actual != nil || event.forecast != nil || event.previous != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        PairEventImpactBadge(level: event.impactLevel)
                        PairSignalPill(signal: signal)

                        Text(eventTimeLabel)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(FXNewsPalette.text)
                    }

                    Text(event.title)
                        .font(.headline)
                        .foregroundStyle(FXNewsPalette.text)

                    Text(eventContext.joined(separator: " • "))
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)

                    Text(signal.reason)
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(eventTimingLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.accent)

                    if event.isHoliday {
                        FXNewsPill(text: "Holiday", tint: FXNewsPalette.warning.opacity(0.16))
                    }
                }
            }

            if hasValues {
                PairEventValuesGrid(event: event)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct PairSignalPill: View {
    let signal: PairDashboardSummary.SignalSummary

    var body: some View {
        Text(signal.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(signal.pillTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(signal.pillBackgroundColor)
            )
    }
}

private struct PairFocusHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Help",
                        title: "Pair Focus",
                        subtitle: "Quick legend for the labels on this page."
                    )

                    PairHelpPairExampleCard()

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        PairHelpSignalCard(
                            title: "Base-Side Risk",
                            tint: FXNewsPalette.accent.opacity(0.14),
                            accent: FXNewsPalette.accent,
                            detail: "News affecting the first currency in the pair."
                        )

                        PairHelpSignalCard(
                            title: "Quote-Side Risk",
                            tint: FXNewsPalette.accentSoft,
                            accent: FXNewsPalette.accent,
                            detail: "News affecting the second currency in the pair."
                        )

                        PairHelpSignalCard(
                            title: "Direct Risk",
                            tint: FXNewsPalette.danger.opacity(0.14),
                            accent: FXNewsPalette.danger,
                            detail: "A stronger, pair-specific risk signal."
                        )

                        PairHelpSignalCard(
                            title: "Direct Driver",
                            tint: FXNewsPalette.warning.opacity(0.14),
                            accent: FXNewsPalette.warning,
                            detail: "One of the main scheduled reasons the pair could move."
                        )

                        PairHelpSignalCard(
                            title: "Shared Macro Theme",
                            tint: FXNewsPalette.surfaceStrong,
                            accent: FXNewsPalette.muted,
                            detail: "Broader risk affecting several watched pairs."
                        )
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

private struct PairHelpPairExampleCard: View {
    var body: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Base vs Quote")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                HStack(spacing: 10) {
                    PairHelpCurrencyCard(code: "EUR", label: "Base", tint: FXNewsPalette.accentSoft)

                    Image(systemName: "arrow.left.and.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FXNewsPalette.muted)

                    PairHelpCurrencyCard(code: "USD", label: "Quote", tint: FXNewsPalette.surfaceStrong)
                }

                Text("In EUR/USD, the first currency is the base and the second is the quote.")
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)
            }
        }
    }
}

private struct PairHelpCurrencyCard: View {
    let code: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(code)
                .font(.title3.weight(.bold))
                .foregroundStyle(FXNewsPalette.text)

            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(FXNewsPalette.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }
}

private struct PairHelpSignalCard: View {
    let title: String
    let tint: Color
    let accent: Color
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(FXNewsPalette.stroke, lineWidth: 1)
                }
        )
    }
}

private struct PairEventImpactBadge: View {
    let level: ImpactLevel

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)

            Text(level.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(level.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(level.color.opacity(0.14))
        )
    }
}

private struct PairEventValuesGrid: View {
    let event: EconomicEvent

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                PairEventValuePill(label: "Forecast", value: event.forecast ?? "—")
                PairEventValuePill(label: "Previous", value: event.previous ?? "—")
                PairEventValuePill(label: "Actual", value: event.actual ?? "—")
            }

            VStack(spacing: 8) {
                PairEventValuePill(label: "Forecast", value: event.forecast ?? "—")
                PairEventValuePill(label: "Previous", value: event.previous ?? "—")
                PairEventValuePill(label: "Actual", value: event.actual ?? "—")
            }
        }
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

private struct PairEventDayGroup: Identifiable {
    let day: Date
    let events: [EconomicEvent]

    var id: Date { day }
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

    struct SignalSummary {
        let event: EconomicEvent
        let role: EventRole
        let isSharedMacroTheme: Bool
        let score: Int
    }

    enum EventRole: Int {
        case shared = 0
        case quote = 1
        case base = 2
        case direct = 3
    }

    var currencies: [String] {
        [baseCurrency, quoteCurrency].compactMap { $0 }
    }

    static func currencyCodes(in symbol: String) -> [String] {
        guard symbol.count == 6 else { return [] }
        return [String(symbol.prefix(3)), String(symbol.suffix(3))]
    }

    var baseCurrency: String? {
        guard symbol.count == 6 else { return nil }
        return String(symbol.prefix(3))
    }

    var quoteCurrency: String? {
        guard symbol.count == 6 else { return nil }
        return String(symbol.suffix(3))
    }

    var highImpactCount: Int {
        events.filter { $0.impactLevel == .high }.count
    }

    var mediumImpactCount: Int {
        events.filter { $0.impactLevel == .medium }.count
    }

    var lowImpactCount: Int {
        events.filter { $0.impactLevel == .low }.count
    }

    var upcomingEvents: [EconomicEvent] {
        events.filter { $0.timestamp >= Date() }
    }

    var eventsInNext24Hours: [EconomicEvent] {
        let now = Date()
        let cutoff = now.addingTimeInterval(24 * 60 * 60)
        return events.filter { $0.timestamp >= now && $0.timestamp <= cutoff }
    }

    var eventsAfterNext24Hours: [EconomicEvent] {
        let cutoff = Date().addingTimeInterval(24 * 60 * 60)
        return events.filter { $0.timestamp > cutoff }
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

    func accentColor(currencyPairCounts: [String: Int]) -> Color {
        guard let signal = primarySignal(currencyPairCounts: currencyPairCounts) else {
            return FXNewsPalette.muted
        }

        switch signal.role {
        case .direct:
            return signal.event.impactLevel == .high ? FXNewsPalette.danger : FXNewsPalette.warning
        case .base:
            return signal.isSharedMacroTheme ? FXNewsPalette.warning : FXNewsPalette.accent
        case .quote:
            return signal.isSharedMacroTheme ? FXNewsPalette.warning : FXNewsPalette.accentSoft
        case .shared:
            return FXNewsPalette.warning
        }
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

    var driverMixLabel: String {
        "\(highImpactCount)H • \(mediumImpactCount)M • \(lowImpactCount)L"
    }

    var currencyPairLabel: String {
        currencies.joined(separator: "/")
    }

    var briefTimingLabel: String {
        guard let nextEvent else {
            return "Quiet"
        }

        return EventDateFormatter.relativeString(for: nextEvent.timestamp)
    }

    func priorityNarrative(currencyPairCounts: [String: Int]) -> String {
        if let signal = primarySignal(currencyPairCounts: currencyPairCounts) {
            return "\(signal.reason) \(signal.event.title) is the next driver for \(symbol)."
        }

        return "No upcoming catalysts are scheduled for \(symbol) in the current feed."
    }

    func nextEventTimeLabel(preferences: UserPreferences) -> String {
        guard let nextEvent else {
            return "No trigger"
        }

        return EventDateFormatter.timeString(
            from: nextEvent.timestamp,
            timeZone: preferences.effectiveTimeZone,
            use24HourTime: preferences.use24HourTime
        )
    }

    func primarySignal(currencyPairCounts: [String: Int]) -> SignalSummary? {
        let focusEvents = eventsInNext24Hours.isEmpty ? upcomingEvents : eventsInNext24Hours

        return focusEvents
            .map { signal(for: $0, currencyPairCounts: currencyPairCounts) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                return lhs.event.timestamp < rhs.event.timestamp
            }
            .first
    }

    func signal(for event: EconomicEvent, currencyPairCounts: [String: Int]) -> SignalSummary {
        let role = eventRole(for: event)
        let sharedTheme = role != .direct && currencyPairCounts[event.currencyCode, default: 0] >= 3
        let score = impactWeight(for: event.impactLevel) + roleWeight(for: role) - (sharedTheme ? 18 : 0)
        return SignalSummary(event: event, role: role, isSharedMacroTheme: sharedTheme, score: score)
    }

    private func eventRole(for event: EconomicEvent) -> EventRole {
        let normalizedPairs = Set(event.relatedPairs.map { $0.uppercased() })

        if normalizedPairs.contains(symbol.uppercased()) {
            return .direct
        }

        if event.currencyCode == baseCurrency {
            return .base
        }

        if event.currencyCode == quoteCurrency {
            return .quote
        }

        return .shared
    }

    private func impactWeight(for impactLevel: ImpactLevel) -> Int {
        switch impactLevel {
        case .high:
            return 60
        case .medium:
            return 36
        case .low:
            return 16
        }
    }

    private func roleWeight(for role: EventRole) -> Int {
        switch role {
        case .direct:
            return 44
        case .base:
            return 28
        case .quote:
            return 22
        case .shared:
            return 10
        }
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

    static func priorityOrder(lhs: PairDashboardSummary, rhs: PairDashboardSummary, currencyPairCounts: [String: Int]) -> Bool {
        let lhsScore = lhs.primarySignal(currencyPairCounts: currencyPairCounts)?.score ?? 0
        let rhsScore = rhs.primarySignal(currencyPairCounts: currencyPairCounts)?.score ?? 0
        let lhsNextTime = lhs.nextEvent?.timestamp ?? .distantFuture
        let rhsNextTime = rhs.nextEvent?.timestamp ?? .distantFuture

        if lhsScore != rhsScore {
            return lhsScore > rhsScore
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

private extension PairDashboardSummary.SignalSummary {
    var label: String {
        switch role {
        case .direct:
            return event.impactLevel == .high ? "Direct risk" : "Direct driver"
        case .base:
            return isSharedMacroTheme ? "Shared macro theme" : "Base-side risk"
        case .quote:
            return isSharedMacroTheme ? "Shared macro theme" : "Quote-side risk"
        case .shared:
            return "Shared macro theme"
        }
    }

    var reason: String {
        switch role {
        case .direct:
            return "This is pair-specific."
        case .base:
            return isSharedMacroTheme ? "This is a broad \(event.currencyCode) driver affecting several watched pairs." : "This hits the base currency directly."
        case .quote:
            return isSharedMacroTheme ? "This is a broad \(event.currencyCode) driver affecting several watched pairs." : "This hits the quote currency directly."
        case .shared:
            return "This is a shared macro driver across your watchlist."
        }
    }

    var pillBackgroundColor: Color {
        switch role {
        case .direct:
            return event.impactLevel.color.opacity(0.16)
        case .base:
            return isSharedMacroTheme ? FXNewsPalette.warning.opacity(0.16) : FXNewsPalette.accent.opacity(0.14)
        case .quote:
            return isSharedMacroTheme ? FXNewsPalette.warning.opacity(0.16) : FXNewsPalette.accentSoft
        case .shared:
            return FXNewsPalette.warning.opacity(0.16)
        }
    }

    var pillTextColor: Color {
        switch role {
        case .direct:
            return event.impactLevel.color
        case .base:
            return isSharedMacroTheme ? FXNewsPalette.warning : FXNewsPalette.accent
        case .quote:
            return isSharedMacroTheme ? FXNewsPalette.warning : FXNewsPalette.text
        case .shared:
            return FXNewsPalette.warning
        }
    }
}

private struct CurrencyPressureSummary: Identifiable {
    let currencyCode: String
    let pairSymbols: [String]
    let events: [EconomicEvent]

    var id: String { currencyCode }

    var highImpactCount: Int {
        events.filter { $0.impactLevel == .high }.count
    }

    var upcomingEventCount: Int {
        events.filter { $0.timestamp >= Date() }.count
    }

    var nextEvent: EconomicEvent? {
        events
            .filter { $0.timestamp >= Date() }
            .min { $0.timestamp < $1.timestamp }
    }

    var primaryColor: Color {
        if highImpactCount > 0 {
            return ImpactLevel.high.color
        }

        if upcomingEventCount > 0 {
            return ImpactLevel.medium.color
        }

        return FXNewsPalette.accent
    }

    var tint: Color {
        primaryColor.opacity(0.16)
    }

    var urgencyLabel: String {
        if highImpactCount >= 2 {
            return "Heavy"
        }

        if highImpactCount == 1 || upcomingEventCount >= 2 {
            return "Active"
        }

        return "Light"
    }

    var headline: String {
        "\(currencyCode) exposure"
    }

    func description(preferences: UserPreferences) -> String {
        if let nextEvent {
            let time = EventDateFormatter.timeString(
                from: nextEvent.timestamp,
                timeZone: preferences.effectiveTimeZone,
                use24HourTime: preferences.use24HourTime
            )
            return "\(upcomingEventCount) scheduled driver\(upcomingEventCount == 1 ? "" : "s"), next at \(time)."
        }

        return "No upcoming releases are mapped directly to \(currencyCode) in this feed."
    }

    static func priorityOrder(lhs: CurrencyPressureSummary, rhs: CurrencyPressureSummary) -> Bool {
        let lhsNextTime = lhs.nextEvent?.timestamp ?? .distantFuture
        let rhsNextTime = rhs.nextEvent?.timestamp ?? .distantFuture

        if lhs.highImpactCount != rhs.highImpactCount {
            return lhs.highImpactCount > rhs.highImpactCount
        }

        if lhs.upcomingEventCount != rhs.upcomingEventCount {
            return lhs.upcomingEventCount > rhs.upcomingEventCount
        }

        if lhs.pairSymbols.count != rhs.pairSymbols.count {
            return lhs.pairSymbols.count > rhs.pairSymbols.count
        }

        if lhsNextTime != rhsNextTime {
            return lhsNextTime < rhsNextTime
        }

        return lhs.currencyCode < rhs.currencyCode
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
        PairsImpactView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: preferences
        )
    }
}

#Preview("My Pairs iPad") {
    let preferences = UserPreferences()
    preferences.watchedPairSymbols = ["EURUSD", "GBPUSD", "USDJPY"]

    return NavigationStack {
        PairsImpactView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: preferences
        )
    }
    .frame(width: 834, height: 1194)
}
