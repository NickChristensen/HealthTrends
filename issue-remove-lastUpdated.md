# Remove lastUpdated field from SharedEnergyData in favor of latestSampleTimestamp

## Problem

`SharedEnergyData` currently has two timestamp fields:
- `lastUpdated`: When the cache was written
- `latestSampleTimestamp`: When the most recent HealthKit sample was recorded

The `lastUpdated` field is redundant and less useful than `latestSampleTimestamp` for all current use cases.

## Current Usage of `lastUpdated`

1. **Staleness check** (DailyActiveEnergyWidget.swift:297):
   ```swift
   let isCacheFromToday = calendar.isDate(todayCache.lastUpdated, inSameDayAs: date)
   ```
   Determines if cache is from today or yesterday to decide whether to show today's data or average-only view.

2. **Average interpolation** (lines 284, 564):
   ```swift
   let averageAtCurrentHour = averageHourlyData.interpolatedValue(at: todayCache.lastUpdated) ?? 0
   ```
   Interpolates average value at cache write time.

3. **Widget gallery entry date** (line 567):
   ```swift
   return EnergyWidgetEntry(date: todayCache.lastUpdated, ...)
   ```

4. **Logging/debug UI** (CacheDebugView.swift)

## Why `latestSampleTimestamp` is Better

**For staleness check (#1):** We should check if the *actual data* is from today, not when we wrote the cache. Example:
- iPad queries HealthKit at 11:59 PM but iPhone hasn't synced since 8 AM
- `lastUpdated` = 11:59 PM (today) ✅ passes staleness check
- `latestSampleTimestamp` = 8 AM (today) ❌ correctly identifies stale data
- Using `latestSampleTimestamp` prevents showing 15-hour-old data as "fresh"

**For interpolation (#2):** Should interpolate at sample time, not cache write time, for same reason.

**For entry date (#3):** Entry date should reflect actual data freshness, not cache write time.

## Proposed Solution

1. Remove `lastUpdated` field from `SharedEnergyData`
2. Update all usages to use `latestSampleTimestamp` instead
3. Handle `nil` case appropriately (when no samples exist):
   - Staleness check: Treat as stale (fail-safe)
   - Interpolation: Use current time or skip
   - Entry date: Use current time as fallback

## Impact

**Files to update:**
- `HealthTrends/Models/SharedEnergyData.swift` - Remove field from struct
- `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift` - Update staleness check, interpolation, entry date
- `HealthTrends/Views/App/CacheDebugView.swift` - Update debug UI
- `documentation/caching-strategy.md` - Update documentation

**Breaking change:** Yes, this changes the cache schema. Old caches will fail to decode.
- **Migration strategy:** Just let it fail - app will regenerate cache on next refresh
- Alternative: Add default value to maintain backward compatibility temporarily

## Acceptance Criteria

- [ ] `lastUpdated` field removed from `SharedEnergyData`
- [ ] Staleness check uses `latestSampleTimestamp` with appropriate nil handling
- [ ] Average interpolation uses `latestSampleTimestamp`
- [ ] Widget entry date uses `latestSampleTimestamp`
- [ ] Debug UI updated to show only `latestSampleTimestamp`
- [ ] Documentation updated
- [ ] All code compiles and runs
- [ ] Widget correctly handles nil `latestSampleTimestamp` case
- [ ] Tested with fresh data and stale/delayed-sync scenarios
