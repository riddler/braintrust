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
- `Braintrust.Experiment` module with full CRUD operations (#13)
  - `Experiment.list/1`, `Experiment.stream/1` - List experiments with pagination
  - `Experiment.get/2` - Get experiment by ID
  - `Experiment.create/2` - Create new experiment
  - `Experiment.update/3` - Update experiment
  - `Experiment.delete/2` - Delete experiment (soft delete)
- Experiment-specific operations (#13)
  - `Experiment.insert/3` - Insert evaluation events
  - `Experiment.fetch/3`, `Experiment.fetch_stream/3` - Fetch events with pagination
  - `Experiment.feedback/3` - Add scores and comments to events
  - `Experiment.summarize/2` - Get aggregated experiment metrics
- Internal Resource helper module to eliminate code duplication between resource modules
- Shared test helpers for pagination testing
- `Braintrust.Dataset` module with full CRUD operations (#14)
  - `Dataset.list/1`, `Dataset.stream/1` - List datasets with pagination
  - `Dataset.get/2` - Get dataset by ID
  - `Dataset.create/2` - Create new dataset (idempotent)
  - `Dataset.update/3` - Update dataset
  - `Dataset.delete/2` - Delete dataset (soft delete)
- Dataset-specific operations (#14)
  - `Dataset.insert/3` - Insert test records with versioning
  - `Dataset.fetch/3`, `Dataset.fetch_stream/3` - Fetch records with pagination
  - `Dataset.feedback/3` - Add scores and comments to records
  - `Dataset.summarize/2` - Get dataset summary statistics
- 24 comprehensive tests for Dataset module
- `dataset_name` filter support in Resource module
- Refactored test helpers (`empty_events_stub/1`, `error_on_first_page_stub/1`) to eliminate code duplication
- `Braintrust.Span` struct for representing traces in Braintrust (#15)
  - Core fields: `id`, `span_id`, `root_span_id`, `span_parents` for DAG trace structure
  - Data fields: `input`, `output`, `expected`, `error`
  - Scoring fields: `scores` (normalized 0-1), `metrics` (raw numbers)
  - Metadata fields: `metadata`, `tags`, `created_at`
  - `Span.to_map/1` for converting to API-ready maps (removes nil values)
- `Braintrust.Log` module for production observability (#15)
  - `Log.insert/3` - Insert production logs/traces (write-only API)
  - Accepts both raw maps and `%Braintrust.Span{}` structs
  - Supports batching multiple events in a single request
  - OpenAI message format recommended for best UI integration
- Enhanced `Experiment.insert/3` to accept `%Braintrust.Span{}` structs (#15)
- Enhanced `Dataset.insert/3` to accept `%Braintrust.Span{}` structs (#15)
- 23 comprehensive tests for Span and Log modules
- 4 additional tests for Span support in Experiment and Dataset modules
- `Braintrust.Prompt` module with full CRUD operations (#16)
  - `Prompt.list/1`, `Prompt.stream/1` - List prompts with pagination
  - `Prompt.get/2` - Get prompt by ID with version/xact_id support
  - `Prompt.create/2` - Create new prompt (idempotent)
  - `Prompt.update/3` - Update prompt (creates new version)
  - `Prompt.delete/2` - Delete prompt (soft delete)
- Version-controlled prompt management with template variables (#16)
- Support for OpenAI-compatible message format with `{{variable}}` syntax
- `prompt_name` and `slug` filter parameters in Resource module
- 21 comprehensive tests for Prompt module
- `Braintrust.Function` module with full CRUD operations (#17)
  - `Function.list/1`, `Function.stream/1` - List functions with pagination and filtering
  - `Function.get/2` - Get function by ID with version/xact_id support
  - `Function.create/2` - Create new function (idempotent)
  - `Function.update/3` - Update function (may create new version)
  - `Function.delete/2` - Delete function (soft delete)
- Support for tools, scorers, and prompt-type functions (#17)
- Polymorphic `function_data` field for different function implementations
- `function_name` and `function_type` filter parameters in Resource module
- 21 comprehensive tests for Function module

### Changed
- Updated README to reflect Projects API as implemented
- Increased coverage requirement from 80% to 90%
- Updated module documentation to remove "(coming soon)" from Project resource
- Updated README with Experiments examples and API coverage table
- Refactored Project and Experiment modules to use shared Resource helpers
- Updated README with Datasets examples and marked as implemented in API coverage table
- Updated main Braintrust module documentation to reflect Dataset availability
- Updated README with Logs examples and marked as implemented in API coverage table
- Enhanced insert operations across Experiment and Dataset modules to accept Span structs while maintaining backward compatibility
- Updated README with comprehensive Prompts examples
- Updated main module documentation to reflect Prompt availability
- Marked Prompts as implemented in API coverage table
- Updated README with Functions examples and usage patterns
- Marked Functions as implemented in API coverage table
- Updated work-in-progress notice to reflect Functions availability

## [0.0.1] - 2025-01-07

### Added
- Initial placeholder release to reserve package name on hex.pm
- Basic project structure

[Unreleased]: https://github.com/riddler/braintrust/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/riddler/braintrust/releases/tag/v0.0.1
