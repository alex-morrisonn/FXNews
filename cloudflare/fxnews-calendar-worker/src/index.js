const FOREX_FACTORY_THIS_WEEK_URL = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
const EDGE_CACHE_TTL_SECONDS = 5 * 60;
const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": `public, max-age=${EDGE_CACHE_TTL_SECONDS}`,
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/calendar/latest.json") {
      return cachedCalendarResponse(request, env, async () => {
        const response = await refreshCurrentWeek(env);
        return jsonResponse(response);
      });
    }

    if (request.method === "GET" && url.pathname.startsWith("/calendar/")) {
      return cachedCalendarResponse(request, env, async () => {
        const weekOf = weekFromPath(url.pathname);
        if (!weekOf) {
          return jsonResponse({ error: "Expected /calendar/yyyy-MM-dd.json" }, 400);
        }

        const cached = await env.FXNEWS_CALENDAR.get(cacheKey(weekOf), "json");
        if (!cached) {
          return jsonResponse({ error: `No stored calendar data for ${weekOf}` }, 404);
        }

        return jsonResponse(cached);
      });
    }

    if (request.method === "PUT" && url.pathname.startsWith("/calendar/")) {
      const authHeader = request.headers.get("authorization") ?? "";
      if (!env.REFRESH_TOKEN || authHeader !== `Bearer ${env.REFRESH_TOKEN}`) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }

      const weekOf = weekFromPath(url.pathname);
      if (!weekOf) {
        return jsonResponse({ error: "Expected /calendar/yyyy-MM-dd.json" }, 400);
      }

      let body;
      try {
        body = await request.json();
      } catch {
        return jsonResponse({ error: "Request body must be valid JSON" }, 400);
      }

      const calendarResponse = normalizeUploadedCalendarResponse(body, weekOf);
      await storeCalendarResponse(env, calendarResponse, "manual");

      return jsonResponse(calendarResponse);
    }

    if (request.method === "POST" && url.pathname === "/refresh") {
      const authHeader = request.headers.get("authorization") ?? "";
      if (!env.REFRESH_TOKEN || authHeader !== `Bearer ${env.REFRESH_TOKEN}`) {
        return jsonResponse({ error: "Unauthorized" }, 401);
      }

      const response = await refreshCurrentWeek(env);
      return jsonResponse(response);
    }

    return jsonResponse({ error: "Not found" }, 404);
  },

  scheduled(_event, env, ctx) {
    ctx.waitUntil(
      refreshCurrentWeek(env)
        .then((response) => {
          console.log(`Scheduled calendar refresh stored ${response.events.length} events for ${response.weekOf}`);
        })
        .catch((error) => {
          console.error("Scheduled calendar refresh failed", error);
        })
    );
  },
};

async function refreshCurrentWeek(env) {
  const upstreamResponse = await fetch(FOREX_FACTORY_THIS_WEEK_URL, {
    headers: { accept: "application/json" },
  });

  if (!upstreamResponse.ok) {
    throw new Error(`ForexFactory request failed with ${upstreamResponse.status}`);
  }

  const events = await upstreamResponse.json();
  const calendarResponse = normalizeCalendarResponse(events);

  await storeCalendarResponse(env, calendarResponse, "forexfactory");
  await env.FXNEWS_CALENDAR.put("calendar:latest", JSON.stringify(calendarResponse));

  return calendarResponse;
}

async function cachedCalendarResponse(request, env, responseProvider) {
  const cache = caches.default;
  const cacheKeyRequest = new Request(request.url, {
    method: "GET",
    headers: {
      accept: "application/json",
    },
  });
  const cachedResponse = await cache.match(cacheKeyRequest);

  if (cachedResponse) {
    const response = new Response(cachedResponse.body, cachedResponse);
    response.headers.set("x-fxnews-cache", "HIT");
    return response;
  }

  const response = await responseProvider();
  response.headers.set("x-fxnews-cache", "MISS");

  if (response.ok) {
    await cache.put(cacheKeyRequest, response.clone());
  }

  return response;
}

async function storeCalendarResponse(env, calendarResponse, source) {
  await env.FXNEWS_CALENDAR.put(
    cacheKey(calendarResponse.weekOf),
    JSON.stringify(calendarResponse),
    {
      metadata: {
        weekOf: calendarResponse.weekOf,
        lastUpdated: calendarResponse.lastUpdated,
        eventCount: calendarResponse.events.length,
        source,
      },
    }
  );
}

function normalizeCalendarResponse(rawEvents) {
  const events = rawEvents
    .map(normalizeEvent)
    .filter(Boolean)
    .sort((lhs, rhs) => lhs.timestamp.localeCompare(rhs.timestamp));
  const weekOf = inferFeedWeekOf(events);

  return {
    weekOf,
    lastUpdated: new Date().toISOString(),
    events,
  };
}

function inferFeedWeekOf(events) {
  const firstTimestamp = events[0]?.timestamp;
  const referenceDate = firstTimestamp ? new Date(firstTimestamp) : new Date();
  referenceDate.setUTCDate(referenceDate.getUTCDate() + 1);
  return weekStartIdentifier(referenceDate);
}

function normalizeUploadedCalendarResponse(body, weekOf) {
  const rawEvents = Array.isArray(body) ? body : body.events ?? [];
  const events = rawEvents
    .map(normalizeEvent)
    .filter(Boolean)
    .sort((lhs, rhs) => lhs.timestamp.localeCompare(rhs.timestamp));

  return {
    weekOf,
    lastUpdated: cleanString(body.lastUpdated) ?? new Date().toISOString(),
    events,
  };
}

function normalizeEvent(rawEvent) {
  const timestamp = parseDate(rawEvent.date ?? rawEvent.timestamp);
  const currencyCode = cleanString(rawEvent.currency ?? rawEvent.country)?.toUpperCase();
  const title = cleanString(rawEvent.title);

  if (!timestamp || !currencyCode || !title) {
    return null;
  }

  return {
    id: makeEventID(title, currencyCode, timestamp),
    title,
    country: defaultCountryCode(currencyCode),
    currency: currencyCode,
    timestamp,
    impact: normalizeImpact(rawEvent.impact),
    forecast: optionalString(rawEvent.forecast),
    previous: optionalString(rawEvent.previous),
    actual: optionalString(rawEvent.actual),
    category: optionalString(rawEvent.category),
    relatedPairs: defaultRelatedPairs(currencyCode),
  };
}

function parseDate(value) {
  if (!value) {
    return null;
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function weekStartIdentifier(date) {
  const utcDate = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = utcDate.getUTCDay();
  const daysSinceMonday = (day + 6) % 7;
  utcDate.setUTCDate(utcDate.getUTCDate() - daysSinceMonday);
  return utcDate.toISOString().slice(0, 10);
}

function weekFromPath(pathname) {
  const match = pathname.match(/^\/calendar\/(\d{4}-\d{2}-\d{2})(?:\.json)?$/);
  return match?.[1] ?? null;
}

function cacheKey(weekOf) {
  return `calendar:${weekOf}`;
}

function makeEventID(title, currencyCode, timestamp) {
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return `${currencyCode.toLowerCase()}-${timestamp}-${slug}`;
}

function normalizeImpact(value) {
  const normalized = cleanString(value)?.toLowerCase();
  if (normalized === "high") {
    return "high";
  }

  if (normalized === "medium") {
    return "medium";
  }

  return "low";
}

function optionalString(value) {
  const cleaned = cleanString(value);
  return cleaned === "" ? null : cleaned;
}

function cleanString(value) {
  if (value === undefined || value === null) {
    return null;
  }

  return String(value).trim();
}

function defaultCountryCode(currencyCode) {
  const countries = {
    AUD: "AU",
    CAD: "CA",
    CHF: "CH",
    CNY: "CN",
    EUR: "EU",
    GBP: "GB",
    JPY: "JP",
    NZD: "NZ",
    USD: "US",
  };

  return countries[currencyCode] ?? currencyCode.slice(0, 2);
}

function defaultRelatedPairs(currencyCode) {
  const pairs = {
    AUD: ["AUDUSD", "AUDJPY", "EURAUD"],
    CAD: ["USDCAD", "EURCAD", "CADJPY"],
    CHF: ["USDCHF", "EURCHF", "CHFJPY"],
    CNY: ["USDCNH", "AUDUSD", "NZDUSD"],
    EUR: ["EURUSD", "EURGBP", "EURJPY"],
    GBP: ["GBPUSD", "EURGBP", "GBPJPY"],
    JPY: ["USDJPY", "EURJPY", "GBPJPY"],
    NZD: ["NZDUSD", "AUDNZD", "EURNZD"],
    USD: ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"],
  };

  return pairs[currencyCode] ?? [];
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: JSON_HEADERS,
  });
}
