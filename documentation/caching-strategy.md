# Caching Strategy

## Overview

Health Trends uses a two-tier caching system to optimize performance and enable the widget to function when the device is locked or HealthKit queries fail. The caches are stored in the App Group shared container (`group.com.healthtrends.shared`) so both the app and widget can access them.

## Cache Types

### Today Data Cache (SharedEnergyData)

**Purpose:** Frequent fallback cache for widget when HealthKit is unavailable

**File:** `energy-data.json` in App Group container

**Contains:**
- `todayTotal` - Cumulative calories burned today
- `moveGoal` - Daily active energy goal (iOS supports weekday-specific goals)
- `todayHourlyData` - Array of hourly cumulative data points
- `lastUpdated` - Timestamp when cache was written

**Note:** Move goal is queried fresh from HealthKit on each refresh; cached value used only as fallback when queries fail.

**Update frequency:** Every app refresh (~15 minutes)

**Staleness check:** Date comparison (`Calendar.isDate(_:inSameDayAs:)`)

**Implementation:**
- Definition: `HealthTrends/Models/SharedEnergyData.swift`
- Writer: `HealthKitManager.fetchEnergyData()` at `HealthTrends/Managers/HealthKitManager.swift:224-228`
- Readers:
  - App authorization check: `HealthKitManager.verifyReadAuthorization()` at `HealthTrends/Managers/HealthKitManager.swift:67-87`
  - Widget fallback: `EnergyWidgetProvider.loadFreshEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:252-318`
  - Widget gallery: `EnergyWidgetProvider.loadCachedEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:474-512`
  - Move goal lookup: `EnergyWidgetProvider.loadCachedMoveGoal()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:515-522`

### Average Data Cache (AverageDataCache)

**Purpose:** Primary data source for average/historical patterns (expensive to compute)

**File:** `average-data-cache.json` in App Group container

**Contains:**
- `averageHourlyPattern` - Averaged cumulative hourly pattern for current weekday
- `projectedTotal` - Average of complete daily totals for current weekday
- `cachedAt` - Timestamp when cache was written
- `cacheVersion` - Schema version for future migrations

**Update frequency:** Once per day (6-9 AM window)

**Staleness check:** Built-in `isStale` property (checks if `cachedAt` is from previous day)

**Implementation:**
- Definition: `HealthTrendsShared/Sources/HealthTrendsShared/AverageDataCache.swift`
- Writer: `HealthKitManager.fetchEnergyData()` at `HealthTrends/Managers/HealthKitManager.swift:231-237`
- Readers:
  - Widget primary source: `EnergyWidgetProvider.loadFreshEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:367-454`
  - Widget fallback: Same method, reads when today's HealthKit query fails
  - Widget gallery: `EnergyWidgetProvider.loadCachedEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:481-485`

## Cache Relationship

The two caches are **independent** and serve different purposes:

| Aspect | Today Cache | Average Cache |
|--------|-------------|---------------|
| Update trigger | App refresh | Daily morning window |
| Data source | Last 24 hours | Last 70 days (weekday-filtered) |
| Computation cost | Low (small query) | High (large dataset, aggregation) |
| Widget strategy | Fallback only | Primary source |
| Staleness tolerance | Minutes | Hours/day |

## Widget Data Loading Strategy

The widget uses a **hybrid approach** to minimize HealthKit queries while ensuring fresh data:

### Normal Operation (Device Unlocked)
1. Query HealthKit for today's data and move goal (always fresh)
2. Read `AverageDataCache` (if fresh, use it; if stale, query HealthKit)
3. Combine and display

### Fallback (Device Locked / Query Failed)
1. Read `SharedEnergyData` for today's data
2. Read `AverageDataCache` for average data
3. If today cache is from yesterday → show average-only view
4. If today cache is from today → show full view

**Implementation:** `EnergyWidgetProvider.loadFreshEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:215-471`

## Authorization Verification

The app uses cache existence as a proxy for HealthKit authorization:
- If `SharedEnergyData` exists → user has granted permission (at some point)
- If no cache exists → user has not granted permission OR first run

**Why this works:**
- HealthKit privacy prevents direct authorization status checks for read permissions
- Cache can only exist if app successfully fetched data (which requires authorization)
- Eliminates false negatives from query-based checks (user with no activity data)

**Implementation:** `HealthKitManager.verifyReadAuthorization()` at `HealthTrends/Managers/HealthKitManager.swift:67-87`

## Cache Invalidation

### Today Cache
- Invalidated implicitly by date check
- Widget shows empty state if cache is from previous day
- No explicit deletion needed (overwrites on next successful fetch)

### Average Cache
- Invalidated by `isStale` property (previous day check)
- Widget refreshes automatically during 6-9 AM window if stale
- Uses stale cache as fallback if refresh fails
- Refresh check: `AverageDataCacheManager.shouldRefresh()` at `HealthTrendsShared/Sources/HealthTrendsShared/AverageDataCache.swift:119-134`

## Performance Characteristics

**Today Data Query:**
- Time range: Midnight → now (< 24 hours)
- Typical samples: 50-1000 (depends on time of day)
- Query time: < 100ms

**Average Data Query:**
- Time range: 70 days ago → yesterday
- Weekday filter: Reduces samples by ~85% (1/7 of days)
- Typical samples: 1000-7000
- Query time: 200-500ms
- Computation: Cumulative aggregation across days

**Cache Read/Write:**
- File size: Today ~2-5 KB, Average ~5-10 KB
- I/O time: < 10ms

## Edge Cases

### First Run (No Caches Exist)
- App shows "Grant Access" button
- Widget shows unauthorized state
- After first successful fetch, both caches populate

### Device Locked
- HealthKit queries fail with error code 6
- Widget falls back to cached data
- Shows last known state until device unlocked

### Stale Average Cache + Query Failure
- Widget uses stale cache (better than nothing)
- Logs warning about cache age
- Retries on next timeline refresh

### Cache Corruption
- JSON decode failure treated as missing cache
- Widget shows unauthorized or today-only state
- Next successful app refresh repairs cache

## Future Considerations

### Version Migration
`AverageDataCache` includes `cacheVersion` field for future schema changes. Today cache (`SharedEnergyData`) does not have versioning—may need to add if breaking changes required.

### Cache Eviction
Currently no automatic cleanup of old caches. App Group storage is generous, but consider adding cleanup if caches grow significantly (e.g., storing multiple days of history).

### Widget Background Refresh
Widget relies on timeline refresh policy (15-minute intervals). Cannot independently refresh HealthKit data without user opening app or timeline reload triggering.
