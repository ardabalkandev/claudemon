# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed

- Avoided force-unwrapping static update/download URLs so invalid URL construction fails gracefully instead of crashing.
- Corrected the privacy documentation to disclose the GitHub Releases update check while clarifying that usage data remains local and telemetry-free.

### Maintenance

- Ignored local `.wrongstack/` session artifacts in Git.
