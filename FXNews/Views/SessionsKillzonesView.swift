import SwiftUI

@MainActor
struct SessionsKillzonesView: View {
    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences

    @State private var notificationMessage: String?

    private let sessionDefinitions = ForexSessionDefinition.allCases
    private let overlapDefinitions = ForexOverlapDefinition.allCases

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Market Time",
                        title: "Sessions",
                        subtitle: "See the major trading centers in your time zone and what is live right now."
                    )

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let sessionStates = sessionDefinitions.map {
                            SessionState(definition: $0, now: context.date, displayTimeZone: preferences.effectiveTimeZone)
                        }
                        let overlapStates = overlapDefinitions.map {
                            OverlapState(definition: $0, now: context.date, displayTimeZone: preferences.effectiveTimeZone)
                        }

                        VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                            marketBoardCard(now: context.date)
                            notificationsCard(sessionStates: sessionStates, overlapStates: overlapStates)
                        }
                    }
                }
            }
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("FX News")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)
            }
        }
        .alert("Session Notification", isPresented: notificationAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notificationMessage ?? "")
        }
    }

    private func marketBoardCard(now: Date) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 18) {
                boardHeaderText

                MarketBoardPanel(now: now, events: viewModel.events, displayTimeZone: preferences.effectiveTimeZone)
            }
        }
        .padding(.top, 8)
    }

    private func notificationsCard(sessionStates: [SessionState], overlapStates: [OverlapState]) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Notifications")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text("Get a 15-minute warning before a session opens or an overlap begins.")
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                ForEach(sessionStates) { state in
                    Toggle(isOn: sessionNotificationBinding(for: state.definition)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(state.definition.title) open")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FXNewsPalette.text)

                            Text("Alerts 15 minutes before \(state.definition.shortTitle) starts.")
                                .font(.caption)
                                .foregroundStyle(FXNewsPalette.muted)
                        }
                    }
                    .tint(FXNewsPalette.accent)
                }

                Divider()
                    .overlay(FXNewsPalette.stroke)

                ForEach(overlapStates) { overlap in
                    Toggle(isOn: overlapNotificationBinding(for: overlap.definition)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(overlap.definition.title) start")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(FXNewsPalette.text)

                            Text("Alerts 15 minutes before the overlap begins.")
                                .font(.caption)
                                .foregroundStyle(FXNewsPalette.muted)
                        }
                    }
                    .tint(FXNewsPalette.accent)
                }
            }
        }
    }

    private var boardHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Market Board")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(FXNewsPalette.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionNotificationBinding(for definition: ForexSessionDefinition) -> Binding<Bool> {
        Binding(
            get: {
                switch definition {
                case .asian:
                    preferences.asianSessionNotificationsEnabled
                case .london:
                    preferences.londonSessionNotificationsEnabled
                case .newYork:
                    preferences.newYorkSessionNotificationsEnabled
                }
            },
            set: { isEnabled in
                switch definition {
                case .asian:
                    preferences.asianSessionNotificationsEnabled = isEnabled
                case .london:
                    preferences.londonSessionNotificationsEnabled = isEnabled
                case .newYork:
                    preferences.newYorkSessionNotificationsEnabled = isEnabled
                }

                Task {
                    FXNewsHaptics.selection()
                    await syncSessionNotification(for: definition, enabled: isEnabled)
                }
            }
        )
    }

    private func overlapNotificationBinding(for definition: ForexOverlapDefinition) -> Binding<Bool> {
        Binding(
            get: {
                switch definition {
                case .asianLondon:
                    preferences.asianLondonOverlapNotificationsEnabled
                case .londonNewYork:
                    preferences.londonNewYorkOverlapNotificationsEnabled
                }
            },
            set: { isEnabled in
                switch definition {
                case .asianLondon:
                    preferences.asianLondonOverlapNotificationsEnabled = isEnabled
                case .londonNewYork:
                    preferences.londonNewYorkOverlapNotificationsEnabled = isEnabled
                }

                Task {
                    FXNewsHaptics.selection()
                    await syncOverlapNotification(for: definition, enabled: isEnabled)
                }
            }
        )
    }

    private func syncSessionNotification(for definition: ForexSessionDefinition, enabled: Bool) async {
        do {
            if enabled {
                try await SessionNotificationStore.scheduleSessionNotification(for: definition, preferences: preferences)
                notificationMessage = "\(definition.title) session notification scheduled."
            } else {
                await SessionNotificationStore.removeSessionNotification(for: definition)
                notificationMessage = "\(definition.title) session notification removed."
            }
        } catch {
            if enabled {
                setSessionNotification(definition, enabled: false)
            }
            notificationMessage = error.localizedDescription
        }
    }

    private func syncOverlapNotification(for definition: ForexOverlapDefinition, enabled: Bool) async {
        do {
            if enabled {
                try await SessionNotificationStore.scheduleOverlapNotification(for: definition, preferences: preferences)
                notificationMessage = "\(definition.title) notification scheduled."
            } else {
                await SessionNotificationStore.removeOverlapNotification(for: definition)
                notificationMessage = "\(definition.title) notification removed."
            }
        } catch {
            if enabled {
                setOverlapNotification(definition, enabled: false)
            }
            notificationMessage = error.localizedDescription
        }
    }

    private var notificationAlertBinding: Binding<Bool> {
        Binding(
            get: { notificationMessage != nil },
            set: { isPresented in
                if !isPresented {
                    notificationMessage = nil
                }
            }
        )
    }

    private func setSessionNotification(_ definition: ForexSessionDefinition, enabled: Bool) {
        switch definition {
        case .asian:
            preferences.asianSessionNotificationsEnabled = enabled
        case .london:
            preferences.londonSessionNotificationsEnabled = enabled
        case .newYork:
            preferences.newYorkSessionNotificationsEnabled = enabled
        }
    }

    private func setOverlapNotification(_ definition: ForexOverlapDefinition, enabled: Bool) {
        switch definition {
        case .asianLondon:
            preferences.asianLondonOverlapNotificationsEnabled = enabled
        case .londonNewYork:
            preferences.londonNewYorkOverlapNotificationsEnabled = enabled
        }
    }
}

#Preview("Sessions") {
    NavigationStack {
        SessionsKillzonesView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}

#Preview("Sessions iPad", traits: .fixedLayout(width: 834, height: 1194)) {
    NavigationStack {
        SessionsKillzonesView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}

private struct MarketBoardPanel: View {
    let now: Date
    let events: [EconomicEvent]
    let displayTimeZone: TimeZone

    @State private var markerDayFractionOverride: Double?
    @State private var markerDragStartFraction: Double?

    private let rows = MarketBoardDefinition.allCases
    private static let activityService: any MarketActivityService = EstimatedMarketActivityService()

    var body: some View {
        let displayedDate = markerDayFractionOverride.map {
            SessionPresentation.date(for: $0, onSameDayAs: now, displayTimeZone: displayTimeZone)
        } ?? now
        let boardStates = rows.map { MarketBoardState(definition: $0, now: displayedDate, displayTimeZone: displayTimeZone) }
        let activitySnapshot = Self.activityService.snapshot(at: displayedDate, events: events)
        let markerTimeLabel = SessionPresentation.markerTimeString(for: displayedDate, displayTimeZone: displayTimeZone)

        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                let isCompact = proxy.size.width < 380
                let labelWidth: CGFloat = isCompact ? 92 : 106
                let spacing: CGFloat = isCompact ? 8 : 10
                let rowHeight: CGFloat = isCompact ? 70 : 74
                let volumeRowHeight: CGFloat = isCompact ? 110 : 118
                let timelineWidth = max(proxy.size.width - labelWidth - spacing, 1)
                let compactTimelineWidth = max(proxy.size.width - 32, 1)
                let timelineRowCount = CGFloat(boardStates.count)
                let markerHeight = isCompact
                    ? proxy.size.height - rowHeight
                    : (rowHeight * timelineRowCount) + (8 * max(timelineRowCount - 1, 0)) + 8 + volumeRowHeight
                let markerFraction = markerDayFractionOverride ?? SessionPresentation.dayFraction(for: now, displayTimeZone: displayTimeZone)
                let markerXPosition = (isCompact ? compactTimelineWidth : timelineWidth) * markerFraction

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(FXNewsPalette.surfaceStrong)

                    Group {
                        if isCompact {
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 8) {
                                    ForEach(boardStates) { state in
                                        CompactMarketTimelineRow(
                                            state: state,
                                            timelineWidth: compactTimelineWidth
                                        )
                                        .frame(height: rowHeight)
                                    }

                                    CompactVolumeTimelineRow(
                                        snapshot: activitySnapshot,
                                        markerDate: displayedDate,
                                        timelineWidth: compactTimelineWidth
                                    )
                                    .frame(height: volumeRowHeight)
                                }

                                SessionNowMarker(
                                    xPosition: markerXPosition,
                                    timelineWidth: compactTimelineWidth,
                                    height: markerHeight,
                                    timeLabel: markerTimeLabel,
                                    isInteracting: markerDayFractionOverride != nil
                                )
                                .gesture(markerDragGesture(timelineWidth: compactTimelineWidth))
                            }
                        } else {
                            HStack(alignment: .top, spacing: spacing) {
                                VStack(spacing: 8) {
                                    ForEach(boardStates) { state in
                                        MarketSessionSidebarCard(
                                            state: state,
                                            compact: false
                                        )
                                        .frame(height: rowHeight)
                                    }

                                    VolumeSidebarCard(
                                        title: "Volume",
                                        statusText: activitySnapshot.statusText,
                                        tag: activitySnapshot.tier.rawValue,
                                        tagColor: activityColor(for: activitySnapshot.tier)
                                    )
                                    .frame(height: volumeRowHeight)
                                }
                                .frame(width: labelWidth)

                                ZStack(alignment: .topLeading) {
                                    VStack(spacing: 8) {
                                        ForEach(boardStates) { state in
                                            MarketSessionTimelineRow(
                                                state: state,
                                                timelineWidth: timelineWidth,
                                                compact: false
                                            )
                                            .frame(height: rowHeight)
                                        }

                                        VolumeTimelineRow(
                                            snapshot: activitySnapshot,
                                            markerDate: displayedDate
                                        )
                                            .frame(height: volumeRowHeight)
                                    }

                                    SessionNowMarker(
                                        xPosition: markerXPosition,
                                        timelineWidth: timelineWidth,
                                        height: markerHeight,
                                        timeLabel: markerTimeLabel,
                                        isInteracting: markerDayFractionOverride != nil
                                    )
                                    .gesture(markerDragGesture(timelineWidth: timelineWidth))
                                }
                                .frame(width: timelineWidth)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .frame(height: 458)
        }
    }

    private func markerDragGesture(timelineWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let clampedTimelineWidth = max(timelineWidth, 1)
                let startFraction = markerDragStartFraction
                    ?? markerDayFractionOverride
                    ?? SessionPresentation.dayFraction(for: now, displayTimeZone: displayTimeZone)

                if markerDragStartFraction == nil {
                    markerDragStartFraction = startFraction
                }

                let translatedFraction = startFraction + (value.translation.width / clampedTimelineWidth)
                let fraction = snappedMarkerFraction(for: translatedFraction, timelineWidth: clampedTimelineWidth)
                markerDayFractionOverride = fraction
            }
            .onEnded { _ in
                markerDragStartFraction = nil
                markerDayFractionOverride = nil
            }
    }

    private func snappedMarkerFraction(for fraction: Double, timelineWidth: CGFloat) -> Double {
        let clampedFraction = min(max(fraction, 0), 1)
        let snapThreshold = 4 / timelineWidth
        let snapFractions = SessionPresentation.marketBoundaryFractions(onSameDayAs: now, displayTimeZone: displayTimeZone)

        guard let nearestBoundary = snapFractions.min(by: {
            abs($0 - clampedFraction) < abs($1 - clampedFraction)
        }) else {
            return clampedFraction
        }

        return abs(nearestBoundary - clampedFraction) <= snapThreshold ? nearestBoundary : clampedFraction
    }
    private func activityColor(for tier: MarketActivityTier) -> Color {
        switch tier {
        case .high:
            FXNewsPalette.success
        case .medium:
            FXNewsPalette.warning
        case .low:
            Color(red: 0.80, green: 0.26, blue: 0.47)
        }
    }
}

private struct MarketBoardState: Identifiable {
    let definition: MarketBoardDefinition
    let localNow: String
    let localDateLine: String
    let nextTransitionLabel: String
    let transitionStatusText: String
    let transitionStatusColor: Color
    let timelineSegments: [TimelineSegment]

    var id: String { definition.id }

    init(definition: MarketBoardDefinition, now: Date, displayTimeZone: TimeZone) {
        self.definition = definition

        let intervals = SessionPresentation.marketIntervalsAroundNow(for: definition, now: now)
        let active = intervals.first(where: { $0.contains(now) })
        let nextInterval = intervals.first(where: { $0.start > now }) ?? SessionPresentation.nextMarketInterval(for: definition, after: now)
        let referenceInterval = active ?? nextInterval

        self.localNow = SessionPresentation.timeString(in: definition.timeZone, for: now)
        self.localDateLine = SessionPresentation.dateString(in: definition.timeZone, for: now)
        self.nextTransitionLabel = active == nil
            ? "Opens in \(SessionPresentation.relativeCountdown(to: referenceInterval.start, from: now))"
            : "Closes in \(SessionPresentation.relativeCountdown(to: referenceInterval.end, from: now))"
        self.transitionStatusText = active == nil ? "Closed" : "Open"
        self.transitionStatusColor = active == nil ? Color.red : FXNewsPalette.success
        self.timelineSegments = SessionPresentation.timelineSegments(for: definition, dayContaining: now, displayTimeZone: displayTimeZone)
    }
}

private struct MarketSessionSidebarCard: View {
    let state: MarketBoardState
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(state.definition.flag)
                    .font(compact ? .subheadline : .headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.definition.cityName)
                        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)
                        .lineLimit(1)

                    Text(state.localNow)
                        .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                        .foregroundStyle(FXNewsPalette.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(state.transitionStatusText)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(state.transitionStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(state.localDateLine)
                .font(.caption2)
                .foregroundStyle(FXNewsPalette.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 8 : 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FXNewsPalette.surface)
        )
    }
}

private struct MarketSessionTimelineRow: View {
    let state: MarketBoardState
    let timelineWidth: CGFloat
    let compact: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(FXNewsPalette.surface)
                        .frame(height: compact ? 8 : 10)

                    ForEach(Array(state.timelineSegments.enumerated()), id: \.offset) { _, segment in
                        Capsule(style: .continuous)
                            .fill(state.definition.color)
                            .frame(width: max(timelineWidth * segment.length, 10), height: compact ? 8 : 10)
                            .offset(x: timelineWidth * segment.start)
                    }
                }
                .frame(height: compact ? 8 : 10)

                Text(state.nextTransitionLabel)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(FXNewsPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 8 : 9)
        }
    }
}

private struct CompactMarketTimelineRow: View {
    let state: MarketBoardState
    let timelineWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.definition.flag)
                    .font(.caption)

                Text(state.definition.cityName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
                    .lineLimit(1)

                Text(state.localNow)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(FXNewsPalette.muted)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(state.transitionStatusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(state.transitionStatusColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(FXNewsPalette.surface)
                        .frame(height: 8)

                    ForEach(Array(state.timelineSegments.enumerated()), id: \.offset) { _, segment in
                        Capsule(style: .continuous)
                            .fill(state.definition.color)
                            .frame(width: max(timelineWidth * segment.length, 10), height: 8)
                            .offset(x: timelineWidth * segment.start)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }
}

private struct VolumeSidebarCard: View {
    let title: String
    let statusText: String
    let tag: String
    let tagColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(FXNewsPalette.muted)
                .lineLimit(1)

            FXNewsPill(text: tag, tint: tagColor.opacity(0.14))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(FXNewsPalette.surface)
        )
    }
}

private struct VolumeTimelineRow: View {
    let snapshot: MarketActivitySnapshot
    let markerDate: Date

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.12))

            VolumeProfileWave(snapshot: snapshot, markerDate: markerDate, showsBackground: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
        }
    }
}

private struct CompactVolumeTimelineRow: View {
    let snapshot: MarketActivitySnapshot
    let markerDate: Date
    let timelineWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Trading volume")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)

                Text(snapshot.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(FXNewsPalette.muted)

                Spacer(minLength: 4)

                FXNewsPill(text: snapshot.tier.rawValue, tint: activityColor.opacity(0.14))
            }

            VolumeProfileWave(snapshot: snapshot, markerDate: markerDate, showsBackground: false)
                .frame(width: timelineWidth, height: 62)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }

    private var activityColor: Color {
        switch snapshot.tier {
        case .high:
            FXNewsPalette.success
        case .medium:
            FXNewsPalette.warning
        case .low:
            Color(red: 0.80, green: 0.26, blue: 0.47)
        }
    }
}

private struct SessionNowMarker: View {
    let xPosition: CGFloat
    let timelineWidth: CGFloat
    let height: CGFloat
    let timeLabel: String
    let isInteracting: Bool

    private let markerWidth: CGFloat = 78
    private let lineWidth: CGFloat = 3

    var body: some View {
        let clampedXPosition = min(max(xPosition, 0), timelineWidth)

        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .top) {
                if isInteracting {
                    Text(timeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(FXNewsPalette.surface)
                        )
                        .offset(y: -34)
                }

                VStack(spacing: 0) {
                    Image(systemName: "triangle.fill")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.accent)
                        .rotationEffect(.degrees(180))
                        .offset(y: -1)

                    Rectangle()
                        .fill(FXNewsPalette.accent)
                        .frame(width: lineWidth, height: max(height + 12, 1))
                        .shadow(color: FXNewsPalette.accent.opacity(0.2), radius: 6, x: 0, y: 0)
                }
            }
            .frame(width: markerWidth)
            .offset(x: clampedXPosition - (markerWidth / 2))
        }
        .frame(width: timelineWidth, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

private struct VolumeProfileWave: View {
    let snapshot: MarketActivitySnapshot
    let markerDate: Date
    var showsBackground: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let points = wavePoints(in: size)
            let strokeGradient = LinearGradient(
                colors: [
                    FXNewsPalette.success,
                    FXNewsPalette.warning,
                    Color(red: 0.80, green: 0.26, blue: 0.47),
                    FXNewsPalette.warning,
                    FXNewsPalette.success
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            ZStack {
                if showsBackground {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    FXNewsPalette.surfaceStrong,
                                    FXNewsPalette.surface
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                waveFillPath(points: points, size: size)
                    .fill(
                        LinearGradient(
                            colors: [
                                FXNewsPalette.success.opacity(0.24),
                                FXNewsPalette.warning.opacity(0.18),
                                Color(red: 0.80, green: 0.26, blue: 0.47).opacity(0.14),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                waveStrokePath(points: points)
                    .stroke(
                        strokeGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 14)
                    .opacity(0.28)

                waveStrokePath(points: points)
                    .stroke(
                        strokeGradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                    .blur(radius: 4)
                    .opacity(0.24)

                waveStrokePath(points: points)
                    .stroke(
                        strokeGradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )

            }
        }
    }

    private func waveY(sample: Double, height: CGFloat) -> CGFloat {
        let normalizedValue = emphasizedSample(sample)
        let verticalPadding = height * 0.10
        let drawableHeight = max(height - (verticalPadding * 2), 1)
        return verticalPadding + (1 - normalizedValue) * drawableHeight
    }

    private func wavePoints(in size: CGSize) -> [CGPoint] {
        let samples = snapshot.sparklineSamples
        let count = max(samples.count - 1, 1)

        return samples.enumerated().map { index, sample in
            let progress = Double(index) / Double(count)
            return CGPoint(
                x: size.width * progress,
                y: waveY(sample: sample, height: size.height)
            )
        }
    }

    private func emphasizedSample(_ sample: Double) -> Double {
        let clampedSample = min(max(sample, 0), 1)
        let boostedSample = min(max(0.5 + ((clampedSample - 0.5) * 1.7), 0), 1)

        if boostedSample < 0.5 {
            return 0.5 * pow(boostedSample * 2, 1.45)
        }

        let mirroredSample = (1 - boostedSample) * 2
        return 1 - (0.5 * pow(mirroredSample, 1.45))
    }

    private func waveStrokePath(points: [CGPoint]) -> Path {
        Path { path in
            guard let firstPoint = points.first else {
                return
            }

            path.move(to: firstPoint)

            if points.count == 2, let lastPoint = points.last {
                path.addLine(to: lastPoint)
            } else {
                for index in 1..<points.count {
                    let previousPoint = points[index - 1]
                    let currentPoint = points[index]
                    let midpoint = CGPoint(
                        x: (previousPoint.x + currentPoint.x) / 2,
                        y: (previousPoint.y + currentPoint.y) / 2
                    )

                    path.addQuadCurve(to: midpoint, control: previousPoint)
                    path.addQuadCurve(to: currentPoint, control: midpoint)
                }
            }
        }
    }

    private func waveFillPath(points: [CGPoint], size: CGSize) -> Path {
        var path = waveStrokePath(points: points)

        guard let lastPoint = points.last else {
            return path
        }

        path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()

        return path
    }
}

private struct SessionState: Identifiable {
    let definition: ForexSessionDefinition
    let activeInterval: DateInterval
    let nextOpenDate: Date
    let isActive: Bool
    let timelineSegments: [TimelineSegment]
    let localWindowLabel: String
    let openRelativeLabel: String
    let closeRelativeLabel: String

    var id: String { definition.id }

    init(definition: ForexSessionDefinition, now: Date, displayTimeZone: TimeZone) {
        self.definition = definition

        let intervals = SessionPresentation.intervalsAroundNow(for: definition, now: now)
        let active = intervals.first(where: { $0.contains(now) })
        let nextOpen = intervals.map(\.start).filter { $0 > now }.min() ?? SessionPresentation.nextInterval(for: definition, after: now).start
        let referenceInterval = active ?? SessionPresentation.nextInterval(for: definition, after: now)

        self.activeInterval = referenceInterval
        self.nextOpenDate = nextOpen
        self.isActive = active != nil
        self.timelineSegments = SessionPresentation.timelineSegments(for: definition, dayContaining: now, displayTimeZone: displayTimeZone)
        self.localWindowLabel = SessionPresentation.localWindowLabel(for: definition, referenceDate: now, displayTimeZone: displayTimeZone)
        self.openRelativeLabel = SessionPresentation.relativeCountdown(to: nextOpen, from: now)
        self.closeRelativeLabel = SessionPresentation.relativeCountdown(to: referenceInterval.end, from: now)
    }
}

private struct OverlapState: Identifiable {
    let definition: ForexOverlapDefinition
    let activeInterval: DateInterval
    let nextStartDate: Date
    let isActive: Bool
    let localWindowLabel: String
    let startRelativeLabel: String
    let endRelativeLabel: String

    var id: String { definition.id }

    init(definition: ForexOverlapDefinition, now: Date, displayTimeZone: TimeZone) {
        self.definition = definition
        let intervals = SessionPresentation.overlapIntervalsAroundNow(for: definition, now: now)
        let active = intervals.first(where: { $0.contains(now) })
        let nextStart = intervals.map(\.start).filter { $0 > now }.min() ?? SessionPresentation.nextOverlapInterval(for: definition, after: now).start
        let referenceInterval = active ?? SessionPresentation.nextOverlapInterval(for: definition, after: now)

        self.activeInterval = referenceInterval
        self.nextStartDate = nextStart
        self.isActive = active != nil
        self.localWindowLabel = SessionPresentation.localWindowLabel(for: definition, referenceDate: now, displayTimeZone: displayTimeZone)
        self.startRelativeLabel = SessionPresentation.relativeCountdown(to: nextStart, from: now)
        self.endRelativeLabel = SessionPresentation.relativeCountdown(to: referenceInterval.end, from: now)
    }
}

#Preview {
    NavigationStack {
        SessionsKillzonesView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}
