# FXNews Calendar Worker

Cloudflare Worker for a shared FXNews calendar cache.

It fetches ForexFactory's current-week JSON, normalizes it to the app's `CalendarResponse` shape, stores it in KV by week, and serves week-specific JSON to the app.

## Endpoints

- `GET /calendar/latest.json` returns the latest stored current-week response, refreshing first if needed.
- `GET /calendar/2026-05-18.json` returns the stored response for that week.
- `POST /refresh` refreshes the current week immediately when called with `Authorization: Bearer <REFRESH_TOKEN>`.

## Deploy Notes

1. Create a KV namespace:

   ```sh
   wrangler kv namespace create FXNEWS_CALENDAR
   ```

2. Put the returned namespace id into `wrangler.toml`.

3. Set a refresh token:

   ```sh
   wrangler secret put REFRESH_TOKEN
   ```

4. Deploy:

   ```sh
   wrangler deploy
   ```

5. Point `RemoteCalendarService.calendarBaseURL` at your route, for example:

   ```swift
   static let calendarBaseURL = URL(string: "https://api.yourdomain.com/calendar/")!
   ```

