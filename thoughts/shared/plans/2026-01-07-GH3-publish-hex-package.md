# Publish Initial Hex Package Implementation Plan

## Overview

Publish the initial version (0.0.1) of the `braintrust` Hex package to reserve the package name on hex.pm and establish presence for the Braintrust Elixir SDK.

## Current State Analysis

- **mix.exs**: Basic project configuration without package metadata
- **lib/braintrust.ex**: Placeholder module with `hello/0` function
- **README.md**: Comprehensive documentation of planned API (marked as WIP)
- **License**: MIT (stated in README, no LICENSE file exists)
- **Version**: Currently `0.1.0`, needs to change to `0.0.1`

### Key Discoveries:
- Package name `braintrust` is available on hex.pm
- Missing required fields: `description/0`, `package/0` functions
- Missing `ex_doc` dependency for documentation generation
- No LICENSE file exists (required for publish)
- No CHANGELOG.md file exists (recommended)

## Desired End State

After this plan is complete:
1. Package is published to hex.pm as `braintrust` version `0.0.1`
2. Package page shows correct description, links to GitHub (`https://github.com/riddler/braintrust`) and Braintrust.dev
3. Package can be added as a dependency: `{:braintrust, "~> 0.0.1"}`
4. Documentation is generated and available on hexdocs.pm/braintrust
5. README displays properly on both hex.pm and hexdocs.pm

### Verification:
- Visit `https://hex.pm/packages/braintrust` and confirm package exists
- Visit `https://hexdocs.pm/braintrust` and confirm docs are accessible
- Test adding dependency in a new project with `{:braintrust, "~> 0.0.1"}`

## What We're NOT Doing

- Adding production dependencies (req, jason) - will be added when functionality is implemented
- Implementing actual SDK functionality - this is a placeholder release
- Setting up CI/CD for automated publishing
- Creating organization on hex.pm (will use personal account)

## Implementation Approach

Minimal changes to enable publishing: add required metadata to `mix.exs`, create LICENSE file, create CHANGELOG.md, add `ex_doc` dependency, and publish.

## Phase 1: Add Required Package Metadata

### Overview
Update `mix.exs` with all required and recommended fields for Hex publishing.

### Changes Required:

#### 1. Update mix.exs
**File**: `mix.exs`
**Changes**: Add description, package, and docs functions; add ex_doc dependency; update version to 0.0.1

```elixir
defmodule Braintrust.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/riddler/braintrust"

  def project do
    [
      app: :braintrust,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Braintrust",
      source_url: @source_url,
      homepage_url: "https://braintrust.dev"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Elixir client for Braintrust.dev AI evaluation and observability platform.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Braintrust" => "https://braintrust.dev"
      },
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] Code compiles: `mix compile`
- [x] Dependencies install: `mix deps.get`

---

## Phase 2: Create LICENSE File

### Overview
Create MIT LICENSE file (required for Hex publish).

### Changes Required:

#### 1. Create LICENSE file
**File**: `LICENSE`
**Changes**: Create new MIT license file

```
MIT License

Copyright (c) 2026 John Thornton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Success Criteria:

#### Automated Verification:
- [x] LICENSE file exists and contains MIT license text

---

## Phase 3: Create CHANGELOG

### Overview
Create initial CHANGELOG.md file following Keep a Changelog format.

### Changes Required:

#### 1. Create CHANGELOG.md file
**File**: `CHANGELOG.md`
**Changes**: Create new changelog file

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.1] - 2025-01-07

### Added
- Initial placeholder release to reserve package name on hex.pm
- Basic project structure

[Unreleased]: https://github.com/riddler/braintrust/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/riddler/braintrust/releases/tag/v0.0.1
```

### Success Criteria:

#### Automated Verification:
- [x] CHANGELOG.md file exists

---

## Phase 4: Update Module Documentation

### Overview
Update the main Braintrust module with proper moduledoc for hexdocs.

### Changes Required:

#### 1. Update lib/braintrust.ex
**File**: `lib/braintrust.ex`
**Changes**: Improve moduledoc to display well on hexdocs.pm

```elixir
defmodule Braintrust do
  @moduledoc """
  Unofficial Elixir SDK for the [Braintrust](https://braintrust.dev) AI evaluation and observability platform.

  > ⚠️ **Work in Progress** - This package is under active development.
  > The API design is being finalized and functionality is not yet implemented.

  ## Installation

  Add `braintrust` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:braintrust, "~> 0.0.1"}
        ]
      end

  ## Configuration

  Set your API key via environment variable:

      export BRAINTRUST_API_KEY="sk-your-api-key"

  Or configure in your application:

      # config/config.exs
      config :braintrust, api_key: System.get_env("BRAINTRUST_API_KEY")

  ## Resources

  - [Braintrust Documentation](https://www.braintrust.dev/docs)
  - [API Reference](https://www.braintrust.dev/docs/api-reference/introduction)
  - [GitHub Repository](https://github.com/riddler/braintrust)
  """

  @doc """
  Placeholder function - SDK functionality coming soon.

  ## Examples

      iex> Braintrust.hello()
      :world

  """
  def hello do
    :world
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] Code compiles: `mix compile`
- [x] Tests pass: `mix test`

---

## Phase 5: Update README Version Reference

### Overview
Update README.md to reference version 0.0.1 instead of 0.1.0.

### Changes Required:

#### 1. Update README.md
**File**: `README.md`
**Changes**: Update version number in installation section

Change:
```elixir
{:braintrust, "~> 0.1.0"}
```

To:
```elixir
{:braintrust, "~> 0.0.1"}
```

### Success Criteria:

#### Automated Verification:
- [x] README.md contains `~> 0.0.1` version reference

---

## Phase 6: Verify and Publish

### Overview
Run all verification steps, generate docs locally, and publish to hex.pm.

### Changes Required:

None - this phase is verification and publishing only.

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `mix test`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Docs generate successfully: `mix docs`
- [x] Hex dry run succeeds: `mix hex.publish --dry-run` (package metadata verified)

#### Manual Verification:
- [ ] Run `mix hex.publish` and authenticate with hex.pm credentials
- [ ] Visit https://hex.pm/packages/braintrust and confirm package appears
- [ ] Visit https://hexdocs.pm/braintrust and confirm documentation is accessible
- [ ] Test in a new project: add `{:braintrust, "~> 0.0.1"}` to deps and run `mix deps.get`

**Implementation Note**: The actual `mix hex.publish` command requires interactive authentication. This must be done manually by the human. After completing the automated verification, pause for manual execution of the publish command.

---

## Testing Strategy

### Unit Tests:
- Existing `hello/0` doctest will run as part of `mix test`

### Integration Tests:
- Post-publish: Create a new Elixir project and add braintrust as dependency

### Manual Testing Steps:
1. After publish, visit hex.pm/packages/braintrust
2. Verify package metadata (description, links, license) displays correctly
3. Visit hexdocs.pm/braintrust and verify documentation renders
4. Create new mix project, add dependency, run `mix deps.get`

## Performance Considerations

None - this is a minimal placeholder package.

## Migration Notes

None - this is the initial release.

## References

- Source document: GitHub Issue #3 "Publish initial Hex package as placeholder"
- Research: `thoughts/shared/research/braintrust_hex_package.md`
- Hex.pm publishing docs: https://hex.pm/docs/publish
