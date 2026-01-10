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
- `Braintrust.Project` resource module with full CRUD operations (#11)
- `Project.list/1` for listing all projects with filtering options
- `Project.stream/1` for memory-efficient lazy pagination through projects
- `Project.get/2` for retrieving a project by ID
- `Project.create/2` for creating new projects (idempotent)
- `Project.update/3` for updating project properties
- `Project.delete/2` for soft-deleting projects
- DateTime parsing for `created_at` and `deleted_at` fields
- Comprehensive test suite with 15 tests covering all operations

### Changed
- Updated README to reflect Projects API as implemented
- Increased coverage requirement from 80% to 90%
- Updated module documentation to remove "(coming soon)" from Project resource

## [0.0.1] - 2025-01-07

### Added
- Initial placeholder release to reserve package name on hex.pm
- Basic project structure

[Unreleased]: https://github.com/riddler/braintrust/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/riddler/braintrust/releases/tag/v0.0.1
