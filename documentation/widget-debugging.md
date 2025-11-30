# Widget Debugging Guide

This guide explains how to check widget logs when running the Daily Active Energy Widget on your physical iPhone.

## Widget Logging Overview

The widget uses **persistent logging** via Apple's `Logger` framework. This means:
- ✅ **Logs are saved to disk** on your iPhone
- ✅ **Can be retrieved hours or days later** (don't need to be watching live)
- ✅ **Survive device reboots** (for a limited time period)

**Log Types:**
- **❌ Error logs:** HealthKit query failures
- **⚠️ Warning logs:** Stale data detected (>30 minutes old)

**Note:** Successful queries with fresh data are NOT logged to reduce noise. You'll only see logs when something is wrong.

---

## Method 1: Console App (RECOMMENDED for historical debugging)

**Best for:** Finding logs from hours or days ago when you notice stale data

1. **Connect your iPhone** via USB to your Mac
2. **Open Console.app** (`/Applications/Utilities/Console.app`)
3. **Select your iPhone** in the left sidebar under "Devices"
4. **DO NOT click "Start streaming"** - we want historical logs
5. In the search box at the top, enter: `subsystem:com.finelycrafted.HealthTrends`
6. **Set time range:** Click the clock icon and select "Last 24 hours" (or longer)
7. Filter further by typing in search: `❌` (errors) or `⚠️` (warnings)

**Key Predicates to Use:**
```
subsystem == "com.finelycrafted.HealthTrends" AND category == "DailyActiveEnergyWidget"
```

**To find stale data issues:**
```
subsystem == "com.finelycrafted.HealthTrends" AND message CONTAINS "stale"
```

**To find all errors:**
```
subsystem == "com.finelycrafted.HealthTrends" AND messageType == error
```

**Tips:**
- **Time filter is critical** - use the clock icon to view logs from the past 24-48 hours
- Logs persist for ~7 days on device (depending on storage)
- You can save logs to a file: File → Save
- No logs = everything is working normally (fresh data)

---

## Method 2: Xcode Console (For real-time debugging only)

**Best for:** Watching logs live while testing

1. **Connect your iPhone** via USB to your Mac
2. **Open Xcode** → **Window → Devices and Simulators**
3. **Select your iPhone** in the left sidebar
4. Click **"Open Console"** button at the bottom
5. In the filter box at the top, enter: `DailyActiveEnergyWidget`

**Note:** Xcode Console shows **live logs only** - not historical. Use Console.app for viewing past logs.

---

## Method 3: Terminal (For scripting/automation)

**Best for:** Capturing logs in scripts or CI/CD pipelines

```bash
# List connected devices to get DEVICE_ID
xcrun devicectl list devices

# Stream logs from your iPhone (replace DEVICE_ID with your device's UUID)
xcrun devicectl device logs stream --device DEVICE_ID | grep "DailyActiveEnergyWidget"

# Or filter for just failures:
xcrun devicectl device logs stream --device DEVICE_ID | grep "❌"

# Save logs to a file:
xcrun devicectl device logs stream --device DEVICE_ID > widget_logs.txt
```

**Example with device ID:**
```bash
# Get device ID
DEVICE_ID=$(xcrun devicectl list devices | grep "iPhone" | head -1 | awk '{print $NF}')

# Stream widget logs
xcrun devicectl device logs stream --device "$DEVICE_ID" | grep "DailyActiveEnergyWidget"
```

---

## What to Look For

### Normal Operation (No Logs)
**If you see NO logs, everything is working perfectly!** The widget only logs when:
- HealthKit queries fail (❌ errors)
- HealthKit returns stale data >30 minutes old (⚠️ warnings)

**Silence is golden** - it means fresh data is being retrieved successfully.

### Stale Data Warning
If HealthKit returns data that's >30 minutes old, you'll see:
```
⚠️ Stale HealthKit data detected
⚠️ Query time: 2025-11-30 14:35:00
⚠️ Latest data point: 2025-11-30 13:00:00
⚠️ Data age: 95 minutes (5700s)
⚠️ Today total: 467 cal from 14 data points
```

**This is the key indicator for issue #14** - the widget successfully queries HealthKit, but HealthKit itself has stale data!

### Failure Logs
If HealthKit queries fail entirely:
```
❌ Widget FAILED to fetch today's HealthKit data at 2025-11-30 14:35:00
❌ Error: Protected data is unavailable
❌ Error type: NSError
```

**Common error codes:**
- **Protected data unavailable:** Device is locked, HealthKit data encrypted
- **Authorization not determined:** User hasn't granted permission yet
- **Authorization denied:** User denied HealthKit access

### Widget Refresh Timeline

The widget refreshes on this schedule:
- **Every 15 minutes:** Normal refresh cycle
- **At midnight:** Special zero-state entry, then reload at 12:01 AM
- **When added to home screen:** Initial load
- **After device reboot:** Reload all widgets

---

## Forcing a Widget Refresh for Testing

### Option 1: Remove and Re-add Widget
1. Long-press the widget on home screen
2. Tap "Remove Widget"
3. Add it back (long-press home screen → + button → search for "Daily Active Energy")

### Option 2: Reboot Device
Simply restart your iPhone - widgets reload after boot

### Option 3: Wait
Widgets refresh automatically every ~15 minutes

---

## Troubleshooting Common Issues

### Widget Shows Stale Data
**Symptoms:** Widget data is hours old, doesn't update

**Check:**
1. Look for ❌ errors in logs (indicates HealthKit query failures)
2. Verify `NSHealthShareUsageDescription` is set in widget target build settings
3. Check that widget extension has HealthKit entitlement enabled

**Fix:** See issue #12 - ensure widget target has proper HealthKit configuration

### No Logs Appearing
**Symptoms:** Can't see any widget logs in Console

**Check:**
1. Ensure device is connected and trusted
2. Verify you're filtering for the correct process name
3. Try broader search: just search for "Widget" or "HealthKit"

**Fix:**
- In Console.app, clear all filters and look for "DailyActiveEnergyWidgetExtension"
- Make sure "Action" → "Include Info Messages" and "Include Debug Messages" are enabled

### Device Locked / Protected Data
**Symptoms:** Errors about "Protected data is unavailable"

**Explanation:** iOS encrypts HealthKit data when the device is locked (first unlock after boot)

**Fix:** This is normal behavior - unlock your device and the next widget refresh should succeed

---

## Related Files

- `DailyActiveEnergyWidget/DailyActiveEnergyWidget.swift` - Widget timeline provider with logging
- `DailyActiveEnergyWidgetExtension.entitlements` - HealthKit entitlement configuration
- `HealthTrends.xcodeproj/project.pbxproj` - Build settings (includes NSHealthShareUsageDescription)

---

## Quick Reference

| Task | Command/Action |
|------|----------------|
| View live logs | Open Xcode → Devices & Simulators → Select device → Open Console |
| Filter for widget | Search: `DailyActiveEnergyWidget` |
| Filter for errors only | Search: `❌` |
| Save logs to file | Console.app → File → Save |
| Stream from terminal | `xcrun devicectl device logs stream --device DEVICE_ID` |
| Force widget refresh | Remove and re-add widget, or reboot device |

---

---

## Investigating Issue #14: Intermittent Stale Data

**Symptoms:** Widget shows stale data (hours old) even though the "now" time is recent.

**How to diagnose:**

1. **Let the app run for 24-48 hours** on your phone
2. **When you notice stale data**, open Console.app
3. **Filter logs from the past 24 hours:**
   - Search: `subsystem:com.finelycrafted.HealthTrends`
   - Time: Last 24 hours (or longer)
4. **Look for patterns:**
   - Are there ❌ errors? → HealthKit queries are failing
   - Are there ⚠️ warnings about stale data? → HealthKit is returning old data (>30 min)
   - Are there NO logs at all? → Queries work fine, but may need to check thresholds

**Key question:** Are there stale data warnings (⚠️) when you notice stale widget data?

```
⚠️ Data age: 95 minutes (5700s)  ← Data is >30 minutes old!
```

If you see these warnings when widget data looks stale, **HealthKit itself has stale data** - not a widget issue.

---

## Issue #12 Context

This debugging guide was created while fixing issue #12, where the widget was showing stale data because HealthKit queries were failing silently. The root cause was missing `NSHealthShareUsageDescription` in the widget target's build settings.

**Fix applied:** Added `INFOPLIST_KEY_NSHealthShareUsageDescription` to both Debug and Release build configurations for the DailyActiveEnergyWidgetExtension target.

**Issue #14 Update:** Enhanced logging with persistent `Logger` to detect when HealthKit returns stale data vs when queries fail entirely.
