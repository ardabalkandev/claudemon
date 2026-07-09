# Changelog

All notable changes to this project will be documented in this file.

## [1.4.6] - 2026-07-09

### Added

- Limit-reset alert: when a session/weekly limit you actually used rolls over
  into a fresh window while the app is running, Claudemon posts a single
  notification that the quota is available again. Untouched windows reset
  silently. Toggleable via the new "When a limit resets" setting (default on).
  Thanks @anilsenay!

### Fixed

- Avoided force-unwrapping static update/download URLs so invalid URL construction fails gracefully instead of crashing.
- Corrected the privacy documentation to disclose the GitHub Releases update check while clarifying that usage data remains local and telemetry-free.

### Maintenance

- Ignored local `.wrongstack/` session artifacts in Git.
