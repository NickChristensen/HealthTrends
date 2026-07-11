# Daily device install LaunchAgent

`com.nick.healthtrends-device-install.plist` is ready to symlink into `~/Library/LaunchAgents/` for this checkout and user account.

For example, from the repository root:

```bash
mkdir -p "$HOME/Library/Logs/HealthTrends" "$HOME/Library/LaunchAgents"
ln -sfn "$PWD/launchd/com.nick.healthtrends-device-install.plist" "$HOME/Library/LaunchAgents/com.nick.healthtrends-device-install.plist"
```

The plist runs at 3:00 AM, and the script itself skips attempts until six days after the last successful install. On an actual install success or failure, it sends a best-effort Pushover notification using the `mac-mini` app. It explicitly sources the local Pushover environment and function files, so notification failures are logged but do not affect the install result or the six-day success timestamp. Loading or unloading the agent is intentionally left to the operator.
