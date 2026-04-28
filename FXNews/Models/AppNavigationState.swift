import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationState {
    static let shared = AppNavigationState()

    var selectedTab: AppTab = .calendar
    var pendingEventID: String?

    private init() {}
}
