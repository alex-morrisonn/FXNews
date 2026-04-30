# FXNews

FXNews is an iOS SwiftUI app for following forex-related economic calendar events, tracking trading sessions, and building a pair-focused watchlist. It is designed to make the weekly macro calendar easier to scan for active FX traders.

## What the app does

- Shows a weekly economic calendar with grouped daily sections
- Filters events by impact, currency, country, category, and watched pairs
- Lets users build a watchlist of forex pairs such as `EURUSD`, `GBPUSD`, and `USDJPY`
- Highlights upcoming catalysts relevant to watched pairs
- Displays major forex sessions and overlap windows in the user’s time zone
- Supports local notifications for calendar events and session opens
- Includes onboarding, appearance settings, quiet hours, and manual time zone controls

## Main areas

### Calendar
The Calendar tab is the core experience. It loads the current trading week, supports pull-to-refresh, and can fall back to cached or bundled data if the remote feed is unavailable.

### My Pairs
The My Pairs tab turns the event feed into a watchlist-driven view. Users can select pairs and see which upcoming releases matter most for those instruments.

### Sessions
The Sessions tab shows major forex market sessions and overlap periods, along with optional session notifications.

### Settings
The Settings tab manages notification timing, quiet hours, display preferences, app appearance, and calendar cache controls.

## Data flow

- The app starts in `RootTabView`
- `CalendarViewModel` manages loading and refreshing event data
- `RemoteCalendarService` fetches calendar data from the repo-hosted JSON feed
- If remote loading fails, the app can use cached data or the bundled sample file
- User settings are persisted through `UserPreferences`

Remote calendar source:

`https://raw.githubusercontent.com/alex-morrisonn/FXNews/main/FXNews/SampleData/calendar.json`

## Project structure

```text
FXNews/
├── FXNews/
│   ├── Models/
│   ├── Services/
│   ├── Utilities/
│   ├── ViewModels/
│   ├── Views/
│   └── SampleData/
├── FXNewsTests/
└── README.md
```

Notable files:

- `FXNews/FXNews/FXnewsApp.swift` - app entry point and notification delegate setup
- `FXNews/FXNews/ViewModels/CalendarViewModel.swift` - loading and refresh state
- `FXNews/FXNews/Services/RemoteCalendarService.swift` - remote feed, cache, and fallback handling
- `FXNews/FXNews/Views/CalendarView.swift` - main calendar UI
- `FXNews/FXNews/Views/PairsPlaceholderView.swift` - watchlist and pair impact UI
- `FXNews/FXNews/Views/SessionsKillzonesView.swift` - sessions and overlap tracking UI
- `FXNews/FXNews/Views/AppSettingsView.swift` - app settings and notification preferences

## Requirements

- Xcode 16 or newer recommended
- iOS target supported by the current Xcode project
- macOS with Apple development tools installed

## Running the app

1. Open the project in Xcode.
2. Select the `FXNews` app target or active scheme.
3. Build and run on an iPhone simulator or a connected device.

## Testing

The repository includes unit tests for:

- calendar utilities
- date formatting
- country display helpers
- economic event decoding
- view model behavior
- remote calendar service behavior
- user preferences
- session presentation and market activity logic

Run tests from Xcode with `Product > Test`.

## Notes for development

- Sample calendar data is stored in `FXNews/FXNews/SampleData/calendar.json`
- The app supports cached and bundled fallback data for offline use
- Notification permission is requested during onboarding or from Settings
- Support, privacy, and terms links point to GitHub Pages content for this repo

## Status

This project is currently structured as an iOS app with a SwiftUI-first architecture using:

- `SwiftUI` for UI
- `Observation` for state management
- `UserNotifications` for reminders
- `Foundation` and local JSON data for calendar handling

## License

Add your preferred license here if you plan to make the repository public.
