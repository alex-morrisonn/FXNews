import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationState {
    static let shared = AppNavigationState()

    var selectedTab: AppTab = .today
    var pendingEventID: String?

    private init() {}
}
