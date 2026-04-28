import Foundation

protocol MarketActivityService {
    func snapshot(at date: Date, events: [EconomicEvent]) -> MarketActivitySnapshot
}

struct MarketActivitySnapshot {
    let score: Double
    let tier: MarketActivityTier
    let statusText: String
    let sparklineSamples: [Double]
}

enum MarketActivityTier: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
}

struct EstimatedMarketActivityService: MarketActivityService {
    func snapshot(at date: Date, events: [EconomicEvent]) -> MarketActivitySnapshot {
        let relevantEvents = eventsRelevantToDisplayedDay(containing: date, events: events)
        let score = activityScore(at: date, events: relevantEvents)

        return MarketActivitySnapshot(
            score: score,
            tier: tier(for: score),
            statusText: statusText(at: date, score: score, events: relevantEvents),
            sparklineSamples: cachedSparklineSamples(for: date, events: relevantEvents)
        )
    }

    private static let cacheLock = NSLock()
    private static var sparklineSampleCache: [SparklineCacheKey: [Double]] = [:]

    private func activityScore(at date: Date, events: [EconomicEvent]) -> Double {
        guard SessionPresentation.isForexMarketOpen(at: date) else {
            return max(preOpenLift(at: date), 0.08)
        }

        let activeSessions = ForexSessionDefinition.allCases.filter { isSessionActive($0, at: date) }
        let activeOverlaps = ForexOverlapDefinition.allCases.filter { isOverlapActive($0, at: date) }

        let baseline = 0.18
        let sessionScore = activeSessions.reduce(0) { partialResult, definition in
            partialResult + sessionWeight(for: definition)
        }
        let overlapScore = activeOverlaps.reduce(0) { partialResult, definition in
            partialResult + overlapWeight(for: definition)
        }
        let eventScore = nearbyEventLift(at: date, events: events)
        let transitionScore = sessionTransitionLift(at: date)

        return (baseline + sessionScore + overlapScore + eventScore + transitionScore)
            .clamped(to: 0...1)
    }

    private func tier(for score: Double) -> MarketActivityTier {
        switch score {
        case 0.72...:
            return .high
        case 0.42...:
            return .medium
        default:
            return .low
        }
    }

    private func statusText(at date: Date, score: Double, events: [EconomicEvent]) -> String {
        if let overlap = ForexOverlapDefinition.allCases.first(where: { isOverlapActive($0, at: date) }) {
            return overlap.shortTitle + " overlap"
        }

        if let event = nearestMarketMovingEvent(to: date, events: events) {
            return event.impactLevel.label + "-impact release window"
        }

        if !SessionPresentation.isForexMarketOpen(at: date) {
            if preOpenLift(at: date) > 0.12 {
                return "Approaching weekly open"
            }

            return "Market closed"
        }

        let activeSessions = ForexSessionDefinition.allCases.filter { isSessionActive($0, at: date) }
        if activeSessions.count == 1, let activeSession = activeSessions.first {
            return activeSession.shortTitle + " session flow"
        }

        return tier(for: score) == .medium ? "Broad session participation" : "Thin liquidity"
    }

    private func sparklineSamples(for date: Date, events: [EconomicEvent]) -> [Double] {
        let sampleCount = 32
        let rawSamples = (0..<sampleCount).map { index in
            let fraction = Double(index) / Double(sampleCount - 1)
            let sampleDate = SessionPresentation.date(for: fraction, onSameDayAs: date)
            return activityScore(at: sampleDate, events: events)
        }

        return smoothed(samples: rawSamples)
    }

    private func cachedSparklineSamples(for date: Date, events: [EconomicEvent]) -> [Double] {
        let key = SparklineCacheKey(date: date, events: events)

        Self.cacheLock.lock()
        if let cachedSamples = Self.sparklineSampleCache[key] {
            Self.cacheLock.unlock()
            return cachedSamples
        }
        Self.cacheLock.unlock()

        let samples = sparklineSamples(for: date, events: events)

        Self.cacheLock.lock()
        Self.sparklineSampleCache[key] = samples
        if Self.sparklineSampleCache.count > 12 {
            Self.sparklineSampleCache.remove(at: Self.sparklineSampleCache.startIndex)
        }
        Self.cacheLock.unlock()

        return samples
    }

    private func sessionWeight(for definition: ForexSessionDefinition) -> Double {
        switch definition {
        case .asian:
            return 0.18
        case .london:
            return 0.28
        case .newYork:
            return 0.24
        }
    }

    private func overlapWeight(for definition: ForexOverlapDefinition) -> Double {
        switch definition {
        case .asianLondon:
            return 0.10
        case .londonNewYork:
            return 0.16
        }
    }

    private func nearbyEventLift(at date: Date, events: [EconomicEvent]) -> Double {
        let activeWindow: TimeInterval = 90 * 60

        let lift = events.reduce(0.0) { partialResult, event in
            let distance = abs(event.timestamp.timeIntervalSince(date))
            guard distance <= activeWindow else {
                return partialResult
            }

            let proximity = 1 - (distance / activeWindow)
            return partialResult + (impactWeight(for: event.impactLevel) * proximity)
        }

        return min(lift, 0.24)
    }

    private func eventsRelevantToDisplayedDay(containing date: Date, events: [EconomicEvent]) -> [EconomicEvent] {
        let activeWindow: TimeInterval = 90 * 60
        let calendar = Calendar.current
        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
        let lowerBound = dayInterval.start.addingTimeInterval(-activeWindow)
        let upperBound = dayInterval.end.addingTimeInterval(activeWindow)

        return events.filter { event in
            event.timestamp >= lowerBound && event.timestamp <= upperBound
        }
    }

    private func nearestMarketMovingEvent(to date: Date, events: [EconomicEvent]) -> EconomicEvent? {
        let activeWindow: TimeInterval = 75 * 60

        return events
            .filter { abs($0.timestamp.timeIntervalSince(date)) <= activeWindow }
            .max {
                marketMovingPriority(for: $0, referenceDate: date) < marketMovingPriority(for: $1, referenceDate: date)
            }
    }

    private func marketMovingPriority(for event: EconomicEvent, referenceDate: Date) -> Double {
        let distance = abs(event.timestamp.timeIntervalSince(referenceDate))
        let impactScore = impactWeight(for: event.impactLevel) * 100
        return impactScore - (distance / 60)
    }

    private func sessionTransitionLift(at date: Date) -> Double {
        let transitionWindow: TimeInterval = 45 * 60
        let nextOpen = ForexSessionDefinition.allCases
            .map { SessionPresentation.nextInterval(for: $0, after: date).start }
            .min()

        guard let nextOpen else {
            return 0
        }

        let timeUntilOpen = nextOpen.timeIntervalSince(date)
        guard timeUntilOpen >= 0, timeUntilOpen <= transitionWindow else {
            return 0
        }

        let proximity = 1 - (timeUntilOpen / transitionWindow)
        return 0.08 * proximity
    }

    private func preOpenLift(at date: Date) -> Double {
        let nextMarketOpen = SessionPresentation.nextForexMarketOpen(after: date)
        let timeUntilOpen = nextMarketOpen.timeIntervalSince(date)
        let preOpenWindow: TimeInterval = 6 * 60 * 60

        guard timeUntilOpen >= 0, timeUntilOpen <= preOpenWindow else {
            return 0
        }

        let proximity = 1 - (timeUntilOpen / preOpenWindow)
        return 0.18 * proximity
    }

    private func impactWeight(for impact: ImpactLevel) -> Double {
        switch impact {
        case .low:
            return 0.03
        case .medium:
            return 0.08
        case .high:
            return 0.16
        }
    }

    private func isSessionActive(_ definition: ForexSessionDefinition, at date: Date) -> Bool {
        SessionPresentation.intervalsAroundNow(for: definition, now: date)
            .contains(where: { $0.contains(date) })
    }

    private func isOverlapActive(_ definition: ForexOverlapDefinition, at date: Date) -> Bool {
        SessionPresentation.overlapIntervalsAroundNow(for: definition, now: date)
            .contains(where: { $0.contains(date) })
    }

    private func smoothed(samples: [Double]) -> [Double] {
        guard samples.count > 2 else {
            return samples
        }

        let weights = [1.0, 2.0, 3.0, 2.0, 1.0]
        let radius = weights.count / 2

        return samples.indices.map { index in
            var weightedTotal = 0.0
            var totalWeight = 0.0

            for offset in -radius...radius {
                let sampleIndex = min(max(index + offset, 0), samples.count - 1)
                let weight = weights[offset + radius]
                weightedTotal += samples[sampleIndex] * weight
                totalWeight += weight
            }

            return (weightedTotal / totalWeight).clamped(to: 0...1)
        }
    }
}

private struct SparklineCacheKey: Hashable {
    let dayStart: TimeInterval
    let eventIDs: [String]

    init(date: Date, events: [EconomicEvent]) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        self.dayStart = startOfDay.timeIntervalSinceReferenceDate
        self.eventIDs = events.map(\.id)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
