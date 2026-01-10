# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Cursor-based pagination with Stream support (#9)
- `Braintrust.Pagination` module for lazy and eager pagination
- `Client.get_stream/3` for streaming paginated API results
- `Client.get_all/3` for eager loading of all paginated results
- Duplicate filtering support via `:unique_by` option

## [0.0.1] - 2025-01-07

### Added
- Initial placeholder release to reserve package name on hex.pm
- Basic project structure

[Unreleased]: https://github.com/riddler/braintrust/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/riddler/braintrust/releases/tag/v0.0.1
