# agent-k8s Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

## [v0.5.0]

### Added

- Added `agent.tokenExistingSecret` option to specify the custom secret for the agent token.

### Updated

- Synchronizing Chart `version` with `appVersion`.

## [v0.2.5]

### Added

- Added the worker/controller modes to the agent-k8s chart

### Updated

- Updating Agent version to 0.5.0

## [v0.2.4]

### Updated

- Updating Agent version to 0.1.36

## [v0.2.3]

### Fixed

- Fix invalid service account reference.

## [v0.2.2]

### Fixed

- Improve the agent-k8s chart description
- Note about relation to agent-docker chart.

## [v0.2.1]

### Added

- Chart description
- Kubernetes deployment diagram

## [v0.2.0]

### Added

- Automatically rollout deployment on the Sclar token change

## [v0.1.0]

### Added

- Initial release.
