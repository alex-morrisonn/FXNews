import SwiftUI

@MainActor
struct SessionsKillzonesView: View {
    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences

    @State private var notificationMessage: String?

    private let sessionDefinitions = ForexSessionDefinition.allCases

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

                        VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                            marketBoardCard(now: context.date)
                            notificationsCard(sessionStates: sessionStates)
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

    private func notificationsCard(sessionStates: [SessionState]) -> some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Notifications")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text("Choose a 15-minute warning, an at-open alert, or both for each session.")
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                ForEach(sessionStates) { state in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.definition.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FXNewsPalette.text)

                        Toggle(isOn: sessionNotificationBinding(for: state.definition, timing: .warning)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("15 min before open")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(FXNewsPalette.text)

                                Text("Alerts 15 minutes before \(state.definition.shortTitle) starts.")
                                    .font(.caption)
                                    .foregroundStyle(FXNewsPalette.muted)
                            }
                        }
                        .tint(FXNewsPalette.accent)

                        Toggle(isOn: sessionNotificationBinding(for: state.definition, timing: .open)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("At session open")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(FXNewsPalette.text)

                                Text("Alerts when \(state.definition.shortTitle) opens.")
                                    .font(.caption)
                                    .foregroundStyle(FXNewsPalette.muted)
                            }
                        }
                        .tint(FXNewsPalette.accent)
                    }
                    if state.id != sessionStates.last?.id {
                        Divider()
                            .overlay(FXNewsPalette.stroke)
                    }
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

    private func sessionNotificationBinding(for definition: ForexSessionDefinition, timing: SessionNotificationTiming) -> Binding<Bool> {
        Binding(
            get: {
                sessionNotificationEnabled(for: definition, timing: timing)
            },
            set: { isEnabled in
                setSessionNotification(definition, timing: timing, enabled: isEnabled)

                Task {
                    FXNewsHaptics.selection()
                    await syncSessionNotification(for: definition, timing: timing, enabled: isEnabled)
                }
            }
        )
    }

    private func syncSessionNotification(for definition: ForexSessionDefinition, timing: SessionNotificationTiming, enabled: Bool) async {
        do {
            if enabled {
                try await SessionNotificationStore.scheduleSessionNotification(for: definition, timing: timing, preferences: preferences)
                notificationMessage = "\(definition.title) \(timing.titleSuffix) notification scheduled."
            } else {
                await SessionNotificationStore.removeSessionNotification(for: definition, timing: timing)
                notificationMessage = "\(definition.title) \(timing.titleSuffix) notification removed."
            }
        } catch {
            if enabled {
                setSessionNotification(definition, timing: timing, enabled: false)
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

    private func sessionNotificationEnabled(for definition: ForexSessionDefinition, timing: SessionNotificationTiming) -> Bool {
        switch (definition, timing) {
        case (.asian, .warning):
            preferences.asianSessionNotificationsEnabled
        case (.london, .warning):
            preferences.londonSessionNotificationsEnabled
        case (.newYork, .warning):
            preferences.newYorkSessionNotificationsEnabled
        case (.asian, .open):
            preferences.asianSessionOpenNotificationsEnabled
        case (.london, .open):
            preferences.londonSessionOpenNotificationsEnabled
        case (.newYork, .open):
            preferences.newYorkSessionOpenNotificationsEnabled
        }
    }

    private func setSessionNotification(_ definition: ForexSessionDefinition, timing: SessionNotificationTiming, enabled: Bool) {
        switch (definition, timing) {
        case (.asian, .warning):
            preferences.asianSessionNotificationsEnabled = enabled
        case (.london, .warning):
            preferences.londonSessionNotificationsEnabled = enabled
        case (.newYork, .warning):
            preferences.newYorkSessionNotificationsEnabled = enabled
        case (.asian, .open):
            preferences.asianSessionOpenNotificationsEnabled = enabled
        case (.london, .open):
            preferences.londonSessionOpenNotificationsEnabled = enabled
        case (.newYork, .open):
            preferences.newYorkSessionOpenNotificationsEnabled = enabled
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

    @State private var markerDateOverride: Date?
    @State private var markerDragStartDate: Date?

    private let rows = MarketBoardDefinition.allCases
    private static let activityService: any MarketActivityService = EstimatedMarketActivityService()

    var body: some View {
        let displayedDate = markerDateOverride ?? now
        let boardStates = rows.map {
            MarketBoardState(
                definition: $0,
                displayedDate: displayedDate,
                timelineCenterDate: now,
                displayTimeZone: displayTimeZone
            )
        }
        let activitySnapshot = Self.activityService.snapshot(at: displayedDate, events: events)
        let markerTimeLabel = SessionPresentation.markerTimeString(for: displayedDate, displayTimeZone: displayTimeZone)
        let markerWindow = SessionPresentation.centeredWindow(containing: now)

        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { proxy in
                let isCompact = proxy.size.width < 380
                let labelWidth: CGFloat = isCompact ? 92 : 106
                let spacing: CGFloat = isCompact ? 8 : 10
                let rowHeight: CGFloat = isCompact ? 70 : 74
                let volumeRowHeight: CGFloat = isCompact ? 110 : 118
                let timelineWidth = max(proxy.size.width - labelWidth - spacing, 1)
                let compactTimelineWidth = max(proxy.size.width - 32, 1)
                let timelineTrackInset: CGFloat = 0
                let timelineTrackWidth = max(isCompact ? compactTimelineWidth : timelineWidth, 1)
                let timelineRowCount = CGFloat(boardStates.count)
                let markerHeight = isCompact
                    ? proxy.size.height - rowHeight
                    : (rowHeight * timelineRowCount) + (8 * max(timelineRowCount - 1, 0)) + 8 + volumeRowHeight
                let markerFraction = markerFraction(for: displayedDate, in: markerWindow)
                let markerXPosition = timelineTrackInset + (timelineTrackWidth * markerFraction)

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
                                            timelineWidth: timelineTrackWidth
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
                                        isInteracting: markerDateOverride != nil
                                )
                                .gesture(markerDragGesture(timelineWidth: timelineTrackWidth))
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
                                        title: "Liquidity",
                                        statusText: activitySnapshot.statusText,
                                        tag: activitySnapshot.displayLabel,
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
                                                timelineWidth: timelineTrackWidth,
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
                                        isInteracting: markerDateOverride != nil
                                    )
                                    .gesture(markerDragGesture(timelineWidth: timelineTrackWidth))
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
                let startDate = markerDragStartDate
                    ?? markerDateOverride
                    ?? now

                if markerDragStartDate == nil {
                    markerDragStartDate = startDate
                }

                let secondsPerPoint = (24 * 60 * 60) / clampedTimelineWidth
                let translatedDate = startDate.addingTimeInterval(TimeInterval(value.translation.width) * secondsPerPoint)
                let clampedDate = clampedMarkerDate(for: translatedDate)
                markerDateOverride = snappedMarkerDate(for: clampedDate, timelineWidth: clampedTimelineWidth)
            }
            .onEnded { _ in
                markerDragStartDate = nil
                markerDateOverride = nil
            }
    }

    private func markerFraction(for date: Date, in window: DateInterval) -> CGFloat {
        guard window.duration > 0 else {
            return 0.5
        }

        let offset = date.timeIntervalSince(window.start) / window.duration
        return CGFloat(min(max(offset, 0), 1))
    }

    private func clampedMarkerDate(for date: Date) -> Date {
        let window = SessionPresentation.centeredWindow(containing: now)
        let clampedTimeInterval = min(max(date.timeIntervalSince(window.start), 0), window.duration)
        return window.start.addingTimeInterval(clampedTimeInterval)
    }

    private func snappedMarkerDate(for date: Date, timelineWidth: CGFloat) -> Date {
        let snapThreshold = (4 / timelineWidth) * (24 * 60 * 60)
        let boundaryDates = marketBoundaryDates(around: date)

        guard let nearestBoundary = boundaryDates.min(by: {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        }) else {
            return date
        }

        return abs(nearestBoundary.timeIntervalSince(date)) <= snapThreshold ? nearestBoundary : date
    }

    private func marketBoundaryDates(around referenceDate: Date) -> [Date] {
        rows.flatMap { definition in
            SessionPresentation.marketIntervalsAroundNow(for: definition, now: referenceDate).flatMap { interval in
                [interval.start, interval.end]
            }
        }
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

    init(definition: MarketBoardDefinition, displayedDate: Date, timelineCenterDate: Date, displayTimeZone: TimeZone) {
        self.definition = definition

        let intervals = SessionPresentation.marketIntervalsAroundNow(for: definition, now: displayedDate)
        let active = intervals.first(where: { $0.contains(displayedDate) })
        let nextInterval = intervals.first(where: { $0.start > displayedDate }) ?? SessionPresentation.nextMarketInterval(for: definition, after: displayedDate)
        let referenceInterval = active ?? nextInterval

        self.localNow = SessionPresentation.timeString(in: definition.timeZone, for: displayedDate)
        self.localDateLine = SessionPresentation.dateString(in: definition.timeZone, for: displayedDate)
        self.nextTransitionLabel = active == nil
            ? "Opens in \(SessionPresentation.relativeCountdown(to: referenceInterval.start, from: displayedDate))"
            : "Closes in \(SessionPresentation.relativeCountdown(to: referenceInterval.end, from: displayedDate))"
        self.transitionStatusText = active == nil ? "Closed" : "Open"
        self.transitionStatusColor = active == nil ? Color.red : FXNewsPalette.success
        self.timelineSegments = SessionPresentation.timelineSegments(for: definition, centeredAt: timelineCenterDate)
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
                SessionTimelineTrack(
                    color: state.definition.color,
                    timelineWidth: timelineWidth,
                    segments: state.timelineSegments,
                    height: compact ? 8 : 10
                )

                Text(state.nextTransitionLabel)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .foregroundStyle(FXNewsPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, compact ? 8 : 10)
            }
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
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                SessionTimelineTrack(
                    color: state.definition.color,
                    timelineWidth: timelineWidth,
                    segments: state.timelineSegments,
                    height: 8
                )
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
    }
}

private struct SessionTimelineTrack: View {
    let color: Color
    let timelineWidth: CGFloat
    let segments: [TimelineSegment]
    let height: CGFloat

    private let edgePadding: CGFloat = 6

    var body: some View {
        let trackWidth = max(timelineWidth, 1)

        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(FXNewsPalette.surface)

            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let rawStart = max(trackWidth * segment.start, 0)
                let start = rawStart <= 0.5 ? edgePadding : rawStart
                let remainingWidth = max(trackWidth - start, 0)
                let segmentWidth = min(trackWidth * segment.length, remainingWidth)
                let touchesLeadingEdge = rawStart <= 0.5
                let touchesTrailingEdge = (start + segmentWidth) >= (trackWidth - 0.5)

                if segmentWidth > 0 {
                    TimelineSegmentShape(
                        roundLeadingEdge: !touchesLeadingEdge,
                        roundTrailingEdge: !touchesTrailingEdge
                    )
                        .fill(color)
                        .frame(width: segmentWidth, height: height)
                        .offset(x: start)
                }
            }
        }
        .frame(width: trackWidth, height: height, alignment: .leading)
        .clipShape(Capsule(style: .continuous))
    }
}

private struct TimelineSegmentShape: Shape {
    let roundLeadingEdge: Bool
    let roundTrailingEdge: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, rect.width / 2)
        let leadingRadius = roundLeadingEdge ? radius : 0
        let trailingRadius = roundTrailingEdge ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leadingRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - trailingRadius, y: rect.minY))

        if trailingRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - trailingRadius, y: rect.midY),
                radius: trailingRadius,
                startAngle: .degrees(-90),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        path.addLine(to: CGPoint(x: rect.minX + leadingRadius, y: rect.maxY))

        if leadingRadius > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + leadingRadius, y: rect.midY),
                radius: leadingRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(-90),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }

        path.closeSubpath()
        return path
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

            LiquidityStrip(
                snapshot: snapshot,
                markerDate: markerDate,
                showsBackground: false
            )
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
                Text("Liquidity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)

                Text(snapshot.statusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(FXNewsPalette.muted)

                Spacer(minLength: 4)

                FXNewsPill(text: snapshot.displayLabel, tint: activityColor.opacity(0.14))
            }

            LiquidityStrip(
                snapshot: snapshot,
                markerDate: markerDate,
                showsBackground: false
            )
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

private struct LiquidityStrip: View {
    let snapshot: MarketActivitySnapshot
    let markerDate: Date
    var showsBackground: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let columns = max(snapshot.sparklineSamples.count, 1)
            let spacing: CGFloat = columns > 24 ? 2 : 3
            let columnWidth = max((size.width - (CGFloat(columns - 1) * spacing)) / CGFloat(columns), 3)

            VStack(alignment: .leading, spacing: 10) {
                if showsBackground {
                    header
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(Array(snapshot.sparklineSamples.enumerated()), id: \.offset) { index, sample in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(sampleColor(for: sample))
                                .frame(width: columnWidth, height: barHeight(for: sample, totalHeight: size.height))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .padding(.horizontal, showsBackground ? 12 : 0)
                .padding(.top, showsBackground ? 10 : 0)
                .padding(.bottom, showsBackground ? 12 : 0)
                .background {
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
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Liquidity")
                .font(.headline)
                .foregroundStyle(FXNewsPalette.text)

            Text(snapshot.displayLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(activityColor)

            Spacer(minLength: 8)

            Text(SessionPresentation.markerTimeString(for: markerDate))
                .font(.caption.weight(.medium))
                .foregroundStyle(FXNewsPalette.muted)
        }
    }

    private func barHeight(for sample: Double, totalHeight: CGFloat) -> CGFloat {
        let minimumHeight = max(totalHeight * 0.22, 12)
        let usableHeight = max(totalHeight - minimumHeight, 1)
        return minimumHeight + (min(max(sample, 0), 1) * usableHeight)
    }

    private func sampleColor(for sample: Double) -> Color {
        let normalized = min(max(sample, 0), 1)
        let opacity = 0.22 + (normalized * 0.73)
        return activityColor.opacity(opacity)
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

private extension MarketActivitySnapshot {
    var displayLabel: String {
        isMarketClosed ? "Closed" : tier.rawValue
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

#Preview {
    NavigationStack {
        SessionsKillzonesView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}
