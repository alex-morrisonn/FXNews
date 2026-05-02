import SwiftUI
import UserNotifications

@MainActor
struct AppSettingsView: View {
    let viewModel: CalendarViewModel
    @Bindable var preferences: UserPreferences

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var cacheMessage: String?
    @State private var notificationMessage: String?
    @State private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationLeadTimeOptions = [0, 5, 10, 15, 30, 45, 60]
    private let manualTimeZoneOptions = [
        "UTC",
        "America/New_York",
        "America/Los_Angeles",
        "Europe/London",
        "Europe/Zurich",
        "Asia/Tokyo",
        "Asia/Singapore",
        "Australia/Sydney"
    ]

    var body: some View {
        ScrollView {
            FXNewsScreen {
                VStack(alignment: .leading, spacing: FXNewsLayout.sectionSpacing) {
                    FXNewsSectionHeader(
                        eyebrow: "Your App",
                        title: "Settings",
                        subtitle: "Manage alerts, display options, app data, and support links."
                    )

                    notificationPreferencesCard
                    displayPreferencesCard
                    dataCard
                    aboutCard
                }
            }
        }
        .background(Color.clear)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshNotificationAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }

            Task {
                await refreshNotificationAuthorizationStatus()
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("FX News")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(FXNewsPalette.text)
            }
        }
        .alert("Cache", isPresented: cacheAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cacheMessage ?? "")
        }
        .alert("Notifications", isPresented: notificationAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notificationMessage ?? "")
        }
    }

    private var notificationPreferencesCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Event Reminders")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                Text("Choose the automatic reminder timing for calendar events. Session open alerts are managed on the Sessions tab.")
                    .font(.subheadline)
                    .foregroundStyle(FXNewsPalette.muted)

                FXNewsInfoRow(label: "Notification access", value: notificationAuthorizationLabel)

                Button {
                    Task {
                        await handleNotificationAccessAction()
                    }
                } label: {
                    settingsActionButtonLabel(
                        title: notificationAuthorizationActionTitle,
                        tint: notificationAuthorizationStatus == .denied ? Color.orange.opacity(0.82) : FXNewsPalette.accent
                    )
                }
                .buttonStyle(.plain)

                leadTimePicker(title: "High impact", selection: $preferences.highImpactNotificationLeadTimeMinutes)
                leadTimePicker(title: "Medium impact", selection: $preferences.mediumImpactNotificationLeadTimeMinutes)
                leadTimePicker(title: "Low impact", selection: $preferences.lowImpactNotificationLeadTimeMinutes)

                FXNewsInfoRow(label: "Custom reminders", value: "Open any event and tap Set Reminder for a one-off alert.")

                FXNewsToggleRow(
                    title: "Quiet hours",
                    subtitle: "Pause reminders during the hours you do not want alerts.",
                    isOn: $preferences.quietHoursEnabled
                )

                if preferences.quietHoursEnabled {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            quietHoursPicker(title: "From", selection: quietHoursBinding(isStart: true))
                            quietHoursPicker(title: "To", selection: quietHoursBinding(isStart: false))
                        }

                        VStack(spacing: 12) {
                            quietHoursPicker(title: "From", selection: quietHoursBinding(isStart: true))
                            quietHoursPicker(title: "To", selection: quietHoursBinding(isStart: false))
                        }
                    }
                }
            }
        }
    }

    private var displayPreferencesCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Display")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Time zone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Picker(
                        "Timezone",
                        selection: Binding(
                            get: { preferences.manualTimeZoneIdentifier ?? "auto" },
                            set: { preferences.manualTimeZoneIdentifier = $0 == "auto" ? nil : $0 }
                        )
                    ) {
                        Text("Use device time zone").tag("auto")
                        ForEach(manualTimeZoneOptions, id: \.self) { identifier in
                            Text(timeZoneLabel(for: identifier)).tag(identifier)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Showing times in \(timeZoneLabel(for: preferences.effectiveTimeZone.identifier))")
                        .font(.caption)
                        .foregroundStyle(FXNewsPalette.muted)
                }

                FXNewsToggleRow(
                    title: "24-hour time",
                    subtitle: "Show event times in 24-hour format.",
                    isOn: $preferences.use24HourTime
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Default impact filter")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Picker("Impact", selection: $preferences.minimumImpact) {
                        ForEach(ImpactLevel.allCases.reversed(), id: \.id) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FXNewsPalette.text)

                    Picker("Appearance", selection: $preferences.preferredAppearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var dataCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Calendar Data")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                FXNewsInfoRow(
                    label: "Last updated",
                    value: viewModel.lastRefreshDate.map {
                        EventDateFormatter.relativeString(for: $0)
                    } ?? "No refresh yet"
                )

                FXNewsInfoRow(label: "Data source", value: dataSourceLabel)

                Button {
                    Task {
                        await viewModel.refresh()
                        cacheMessage = viewModel.errorMessage == nil
                            ? "Calendar refreshed."
                            : (viewModel.errorMessage ?? "Refresh failed.")
                    }
                } label: {
                    settingsActionButtonLabel(title: "Refresh Now", tint: FXNewsPalette.accent)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        do {
                            try viewModel.clearCache()
                            await viewModel.refresh()
                            cacheMessage = "Saved calendar data was cleared."
                        } catch {
                            cacheMessage = error.localizedDescription
                        }
                    }
                } label: {
                    settingsActionButtonLabel(title: "Clear Cache", tint: Color.red.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aboutCard: some View {
        FXNewsCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("About")
                    .font(.headline)
                    .foregroundStyle(FXNewsPalette.text)

                FXNewsInfoRow(label: "App version", value: appVersion)

                settingsLinkButton(title: "Send Feedback", action: {
                    openURL(URL(string: "mailto:fxnews.app@gmail.com?subject=FX%20News%20Feedback")!)
                })

                settingsLinkButton(title: "Privacy Policy", action: {
                    openURL(URL(string: AppExternalLinks.privacyPolicyURL)!)
                })

                settingsLinkButton(title: "Terms of Service", action: {
                    openURL(URL(string: AppExternalLinks.termsOfServiceURL)!)
                })

                settingsLinkButton(title: "Support", action: {
                    openURL(URL(string: AppExternalLinks.supportURL)!)
                })
            }
        }
    }

    private func leadTimePicker(title: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            Picker(title, selection: selection) {
                ForEach(notificationLeadTimeOptions, id: \.self) { minutes in
                    Text(leadTimeLabel(minutes)).tag(minutes)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func quietHoursPicker(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1)
                .foregroundStyle(FXNewsPalette.muted)

            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(FXNewsPalette.accent)
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
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quietHoursBinding(isStart: Bool) -> Binding<Date> {
        Binding(
            get: { dateFromMinutes(isStart ? preferences.quietHoursStartMinutes : preferences.quietHoursEndMinutes) },
            set: { newDate in
                if isStart {
                    preferences.quietHoursStartMinutes = minutesFromDate(newDate)
                } else {
                    preferences.quietHoursEndMinutes = minutesFromDate(newDate)
                }
            }
        )
    }

    private func dateFromMinutes(_ minutes: Int) -> Date {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .minute, value: minutes, to: startOfDay) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func timeZoneLabel(for identifier: String) -> String {
        guard let timeZone = TimeZone(identifier: identifier) else {
            return identifier
        }

        let short = timeZone.localizedName(for: .shortStandard, locale: .current) ?? identifier
        return "\(identifier.replacingOccurrences(of: "_", with: " ")) (\(short))"
    }

    private func leadTimeLabel(_ minutes: Int) -> String {
        if minutes == 0 {
            return "Off"
        }
        if minutes == 60 {
            return "1h"
        }
        return "\(minutes)m"
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var dataSourceLabel: String {
        switch viewModel.dataSource {
        case .remote:
            "Live remote feed"
        case .cache:
            viewModel.isShowingFallbackData ? "Cached fallback data" : "Local cache"
        case .bundled:
            "Bundled sample feed"
        case nil:
            "Not loaded yet"
        }
    }

    private func settingsActionButtonLabel(title: String, tint: Color) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(tint)
            )
    }

    private func settingsLinkButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FXNewsPalette.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(FXNewsPalette.muted)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private var cacheAlertBinding: Binding<Bool> {
        Binding(
            get: { cacheMessage != nil },
            set: { isPresented in
                if !isPresented {
                    cacheMessage = nil
                }
            }
        )
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

    private func handleNotificationAccessAction() async {
        switch notificationAuthorizationStatus {
        case .denied:
            NotificationAuthorizationStore.openSystemSettings()
        case .authorized, .provisional, .ephemeral:
            notificationMessage = "Notifications are already turned on."
        case .notDetermined:
            do {
                let granted = try await NotificationAuthorizationStore.requestAuthorizationIfNeeded()
                await refreshNotificationAuthorizationStatus()
                notificationMessage = granted ? "Notifications are now turned on." : "Notifications remain turned off."
            } catch {
                notificationMessage = error.localizedDescription
            }
        @unknown default:
            notificationMessage = "FX News could not confirm your notification status."
        }
    }

    private func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await NotificationAuthorizationStore.authorizationStatus()
    }

    private var notificationAuthorizationLabel: String {
        switch notificationAuthorizationStatus {
        case .authorized:
            "On"
        case .provisional:
            "On silently"
        case .ephemeral:
            "Temporarily on"
        case .denied:
            "Turned off in Settings"
        case .notDetermined:
            "Not set yet"
        @unknown default:
            "Unknown"
        }
    }

    private var notificationAuthorizationActionTitle: String {
        switch notificationAuthorizationStatus {
        case .denied:
            "Open Settings"
        case .authorized, .provisional, .ephemeral:
            "Notifications On"
        case .notDetermined:
            "Enable Notifications"
        @unknown default:
            "Check Notifications"
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        AppSettingsView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}

#Preview("Settings iPad") {
    NavigationStack {
        AppSettingsView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}

enum AppExternalLinks {
    static let githubPagesBaseURL = "https://alex-morrisonn.github.io/FXNews"
    static let supportEmailURL = "mailto:fxnews.app@gmail.com?subject=FX%20News%20Support"
    static let privacyPolicyURL = githubPagesBaseURL + "/privacy.html"
    static let termsOfServiceURL = githubPagesBaseURL + "/terms.html"
    static let supportURL = githubPagesBaseURL + "/support.html"
}

#Preview {
    NavigationStack {
        AppSettingsView(
            viewModel: CalendarViewModel(service: MockCalendarService()),
            preferences: UserPreferences()
        )
    }
}

private struct FXNewsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                copy
                Spacer(minLength: 20)
                toggle
            }

            VStack(alignment: .leading, spacing: 12) {
                copy
                toggle
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FXNewsPalette.text)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(FXNewsPalette.muted)
        }
    }

    private var toggle: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .tint(FXNewsPalette.accent)
    }
}
