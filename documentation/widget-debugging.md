# Widget Debugging Guide

This guide explains how to check widget logs when running the Daily Active Energy Widget on your physical iPhone.

## Widget Logging Overview

The widget logs errors when HealthKit queries fail. Look for lines starting with ❌ in the logs:

```
❌ Widget FAILED to fetch today's HealthKit data at 2025-11-28 14:35:00
❌ Error: <specific error details>
❌ Error type: <error type>
```

---

## Method 1: Xcode Console (Easiest while actively testing)

**Best for:** Real-time debugging while you have your phone connected

1. **Connect your iPhone** via USB to your Mac
2. **Open Xcode** and go to **Window → Devices and Simulators**
3. **Select your iPhone** in the left sidebar
4. Click **"Open Console"** button at the bottom
5. In the filter box at the top, enter: `DailyActiveEnergyWidget`
6. Look for lines with ❌ - those are the failure logs

**Tips:**
- Filter by process name or search for specific text like "FAILED"
- The console auto-scrolls as new logs appear
- Use Cmd+F to search within logs

---

## Method 2: Console App (Best for reviewing logs later)

**Best for:** Reviewing logs after the fact, or monitoring over longer periods

1. **Open Console.app** on your Mac (in `/Applications/Utilities/`)
2. **Connect your iPhone** via USB
3. **Select your iPhone** in the left sidebar under "Devices"
4. In the search box, enter: `process:DailyActiveEnergyWidget`
5. Or search for: `❌` to see just failures
6. **Optional:** Click "Start" to begin streaming live logs

**Tips:**
- You can save logs for later review using File → Save
- Use predicates for advanced filtering: `subsystem == "com.finelycrafted.HealthTrends.DailyActiveEnergyWidgetExtension"`
- Logs persist even after disconnecting the device (historical logs)

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

### Success Case (No errors)
If the widget is working correctly, you won't see any ❌ error logs. The widget will query HealthKit successfully every ~15 minutes.

### Failure Case (Errors present)
If you see these patterns:

```
❌ Widget FAILED to fetch today's HealthKit data at 2025-11-28 14:35:00
❌ Error: Error Domain=com.apple.healthkit Code=4 "Protected data is unavailable"
❌ Error type: NSError
```

**Common error codes:**
- **Code 4 (Protected data unavailable):** Device is locked, HealthKit data encrypted
- **Code 5 (Authorization not determined):** User hasn't granted permission yet
- **Code 6 (Authorization denied):** User denied HealthKit access
- **Missing NSHealthShareUsageDescription:** HealthKit queries fail silently

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

## Issue #12 Context

This debugging guide was created while fixing issue #12, where the widget was showing stale data because HealthKit queries were failing silently. The root cause was missing `NSHealthShareUsageDescription` in the widget target's build settings.

**Fix applied:** Added `INFOPLIST_KEY_NSHealthShareUsageDescription` to both Debug and Release build configurations for the DailyActiveEnergyWidgetExtension target.
