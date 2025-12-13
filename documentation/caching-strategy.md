# Caching Strategy

## Overview

Health Trends uses a two-tier caching system to optimize performance and enable the widget to function when the device is locked or HealthKit queries fail. The caches are stored in the App Group shared container (`group.com.healthtrends.shared`) so both the app and widget can access them.

## Cache Types

### Today Data Cache (TodayEnergyCache)

**Purpose:** Frequent fallback cache for widget when HealthKit is unavailable

**File:** `energy-data.json` in App Group container

**Contains:**
- `todayTotal` - Cumulative calories burned today
- `moveGoal` - Daily active energy goal (iOS supports weekday-specific goals)
- `todayHourlyData` - Array of hourly cumulative data points
- `latestSampleTimestamp` - Timestamp of most recent HealthKit sample (nil if no samples); determines actual data freshness and is used for staleness checks, NOW marker positioning, and average interpolation

**Notes:**
- Move goal is queried fresh from HealthKit on each refresh; cached value used only as fallback when queries fail.
- `latestSampleTimestamp` reflects when HealthKit data is actually from (last sample's end time). This matters in delayed-sync scenarios (iPad waiting for iPhone, iPhone waiting for Apple Watch) where the widget should accurately represent data freshness.

**Update frequency:** Every app refresh (~15 minutes)

**Staleness check:** Compares `latestSampleTimestamp` to current date using `Calendar.isDate(_:inSameDayAs:)`. If timestamp is nil, cache is treated as stale (fail-safe behavior).

**Implementation:**
- Definition: `HealthTrendsShared/Sources/HealthTrendsShared/TodayEnergyCacheManager.swift`
- Query service: `HealthKitQueryService.fetchTodayHourlyTotals()` returns tuple with data and `latestSampleTimestamp` extracted from most recent sample's `endDate`
- Writer: `HealthKitManager.populateTodayCache()` and `EnergyWidgetProvider.loadFreshEntry()` (both write cache with `latestSampleTimestamp`)
- Readers:
  - App authorization check: `HealthKitManager.verifyReadAuthorization()`
  - Widget fallback: `EnergyWidgetProvider.loadFreshEntry()`
  - Widget gallery: `EnergyWidgetProvider.loadCachedEntry()`
  - Move goal lookup: `EnergyWidgetProvider.loadCachedMoveGoal()`

### Average Data Cache (WeekdayAverageCache)

**Purpose:** Primary data source for average/historical patterns (expensive to compute)

**File:** `average-data-cache-v2.json` in App Group container

**Architecture:** Weekday-specific cache (v2) storing separate average patterns for each weekday

**Contains:**
- `weekdayData` - Dictionary mapping weekday (1-7) to weekday-specific `AverageDataCache`
  - Key: Weekday.rawValue (1=Sunday, 2=Monday, ..., 7=Saturday)
  - Value: `AverageDataCache` with average pattern for that specific weekday
- `cacheVersion` - Schema version (2 for weekday-aware cache)

**Per-Weekday Cache Data:**
- `averageHourlyPattern` - Averaged cumulative hourly pattern for that weekday
- `projectedTotal` - Average of complete daily totals for that weekday
- `cachedAt` - Timestamp when this weekday's cache was written
- `cacheVersion` - Individual cache version (currently 1)

**Update frequency:**
- Initial population: All 7 weekdays populated after first authorization
- Ongoing refresh: Once per day for current weekday (6-9 AM window)
- Automatic refresh: When weekday cache is >30 days old

**Staleness check:** Cache age >30 days (not previous day)

**Why Weekday-Specific:**
- Activity patterns vary significantly by weekday (e.g., Saturday vs Monday)
- Weekday-specific goals are common (e.g., 750 cal on weekends, 1000 cal weekdays)
- Widget can show accurate averages for any day of the week
- All 7 caches populated upfront for complete widget fallback coverage

**Implementation:**
- Definition: `HealthTrendsShared/Sources/HealthTrendsShared/AverageDataCache.swift`
- API: `AverageDataCacheManager.load(for: Weekday)`, `save(_:for: Weekday)`, `shouldRefresh(for: Weekday)`
- Writer (all weekdays): `HealthKitManager.populateWeekdayCaches()` at `HealthTrends/Managers/HealthKitManager.swift:344`
- Readers:
  - Widget primary source: `EnergyWidgetProvider.loadFreshEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:367-454`
  - Widget fallback: Same method, reads when today's HealthKit query fails
  - Widget gallery: `EnergyWidgetProvider.loadCachedEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:481-485`

## Weekday-Specific Cache Architecture

The average cache uses a **weekday-aware architecture** (v2) to handle different activity patterns across days of the week:

**Key Concepts:**
- **Weekday Enum:** Maps to Calendar weekday values (1=Sunday, 2=Monday, ..., 7=Saturday)
- **Container Structure:** Single JSON file containing all 7 weekday caches
- **Independent Caches:** Each weekday tracked separately with own timestamp and staleness
- **Selective Updates:** Only current weekday refreshed during daily morning window
- **Complete Coverage:** All 7 weekdays populated on first authorization

**Benefits:**
1. **Accuracy:** Saturday averages based on Saturdays, Monday averages based on Mondays
2. **Weekday Goals:** Handles users with different goals per weekday (e.g., 750 on weekends, 1000 on weekdays)
3. **Widget Reliability:** Widget always has fresh data regardless of what day user opens app
4. **Performance:** Only refreshes current weekday's cache (not all 7 every day)
5. **Freshness:** 30-day staleness window (vs previous 1-day) reduces unnecessary queries

**Example Scenario:**
- User opens app on Saturday morning → Saturday cache refreshes
- Monday's cache remains valid (last refreshed Monday, 6 days ago)
- Widget on Monday uses Monday's cache (still fresh, <7 days old)
- No unnecessary query needed for Monday's data

## Cache Relationship

The two caches are **independent** and serve different purposes:

| Aspect | Today Cache | Average Cache (per weekday) |
|--------|-------------|------------------------------|
| Update trigger | App refresh | Daily morning window (current weekday only) |
| Data source | Last 24 hours | Last 70 days (weekday-filtered) |
| Computation cost | Low (small query) | High (large dataset, aggregation) |
| Widget strategy | Fallback only | Primary source |
| Staleness tolerance | Same day | Up to 30 days |
| Cache entries | 1 (today) | 7 (one per weekday) |

## Widget Data Loading Strategy

The widget uses a **hybrid approach** to minimize HealthKit queries while ensuring fresh data:

### Normal Operation (Device Unlocked)
1. Query HealthKit for today's data and move goal (always fresh)
2. Read `WeekdayAverageCache` for current weekday (if fresh, use it; if stale, query HealthKit and update that weekday's cache)
3. Combine and display

### Fallback (Device Locked / Query Failed)
1. Read `TodayEnergyCache` for today's data
2. Read `WeekdayAverageCache` for current weekday's average data
3. Check `latestSampleTimestamp`:
   - If nil or from previous day → show average-only view
   - If from today → show full view with cached data
4. Use `latestSampleTimestamp` for NOW marker and average interpolation (fallback to current time if nil)

**Implementation:** `EnergyWidgetProvider.loadFreshEntry()` at `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift:215-471`

## Authorization Verification

The app uses a **hybrid approach** to verify HealthKit authorization:

**Fast Path (Cache Check):**
- If `TodayEnergyCache` exists → user has granted permission (instant verification)
- Returns immediately without querying HealthKit

**Query Path (HealthKit Verification):**
- If no cache exists → performs minimal HealthKit query to check actual permission state
- Uses `HealthKitQueryService.checkReadAuthorization()` to distinguish "denied" from "no data yet"
- Eliminates false negatives from query-based checks (user with no activity data)

**Post-Authorization Initialization:**
After successful authorization:
1. Fetches initial data immediately (populates today cache)
2. Calls `populateWeekdayCaches()` to populate all 7 weekday average caches
3. Ensures widget has complete fallback coverage for all days of the week

**Why this works:**
- HealthKit privacy prevents direct authorization status checks for read permissions
- Cache existence proves permission was granted at some point (fast path)
- Query path provides definitive answer when cache doesn't exist
- Initial population ensures widget works correctly from first authorization

**Implementation:** `HealthKitManager.verifyReadAuthorization()` at `HealthTrends/Managers/HealthKitManager.swift:81-109`

## Cache Invalidation

### Today Cache
- Staleness determined by `latestSampleTimestamp` date comparison (not cache write time)
- Widget shows average-only view if sample timestamp is from previous day or nil
- Accurately reflects data age in delayed-sync scenarios (device waiting for sync)
- No explicit deletion needed (overwrites on next successful fetch)

### Average Cache (Weekday-Specific)
- Each weekday cache tracked independently
- Staleness threshold: 30 days (not previous day)
- Widget refreshes current weekday's cache during 6-9 AM window if >30 days old
- Uses stale cache as fallback if refresh fails (better than nothing)
- Other weekday caches remain valid until 30-day threshold
- Refresh check: `AverageDataCacheManager.shouldRefresh(for: Weekday)` at `HealthTrendsShared/Sources/HealthTrendsShared/AverageDataCache.swift:233-245`

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
- File size: Today ~2-5 KB, Weekday Average ~35-70 KB (7 weekdays × ~5-10 KB each)
- I/O time: < 10ms (read single weekday), < 20ms (write full container)
- Storage overhead: Minimal (~70 KB total for all caches)

## Edge Cases

### First Run (No Caches Exist)
- App shows "Grant Access" button
- Widget shows unauthorized state
- After first successful authorization:
  - Today cache populates immediately
  - All 7 weekday average caches populate (via `populateWeekdayCaches()`)
  - Widget gains complete fallback coverage for all days

### Device Locked
- HealthKit queries fail with error code 6
- Widget falls back to cached data from `TodayEnergyCache`
- Staleness check uses `latestSampleTimestamp` to determine if data is from today
- Chart NOW marker and average interpolation use `latestSampleTimestamp` (reflects actual sample time, not cache write time)
- If `latestSampleTimestamp` is nil:
  - Current time used as fallback for NOW marker and interpolation
  - Cache treated as stale (shows average-only view)
  - Warning logged to help diagnose first-install vs delayed-sync scenarios

### Stale Average Cache + Query Failure
- Widget uses stale weekday cache even if >30 days old (better than nothing)
- Logs warning about cache age
- Retries on next timeline refresh
- Other weekday caches unaffected (remain valid)

### Cache Corruption
- JSON decode failure treated as missing cache
- Widget shows unauthorized or today-only state
- Next successful app refresh repairs current weekday's cache
- `populateWeekdayCaches()` can be called manually to rebuild all 7 weekday caches

## Future Considerations

### Version Migration
- `WeekdayAverageCache` has `cacheVersion` (currently 2) for container-level changes
- Individual `AverageDataCache` entries have their own `cacheVersion` (currently 1)
- `TodayEnergyCache` does not have explicit versioning
  - Schema changes cause decode failures (treated as missing cache)
  - Cache automatically regenerates on next app refresh
  - Brief widget unavailability during transition is acceptable
- Migration from v1 (`average-data-cache.json`) to v2 (`average-data-cache-v2.json`) happens automatically:
  - Old single-weekday cache ignored
  - New weekday-specific cache populated on first authorization or app refresh

### Cache Eviction
- Weekday caches naturally stay fresh (30-day auto-refresh policy)
- Old v1 cache file (`average-data-cache.json`) not automatically deleted—consider cleanup
- App Group storage is generous (~70 KB for all caches is negligible)
- No automatic cleanup needed unless additional historical data added

### Widget Background Refresh
Widget relies on timeline refresh policy (15-minute intervals). Cannot independently refresh HealthKit data without user opening app or timeline reload triggering.
