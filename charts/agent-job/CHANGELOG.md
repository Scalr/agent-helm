# agent-job Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

### Added

- Added `task.job.basename` option to override the base name prefix for spawned Kubernetes Jobs.
- Added "Task Naming" documentation section explaining how Job names are generated.

### Changed

- Renamed CRD from `AgentTask` to `AgentTaskTemplate` for clarity.
- Default base name changed from chart name (`agent-job`) to `scalr-agent` for cleaner resource naming.
- Deployment and task template names now use `fullname` template instead of hardcoded values.
- Updated RBAC to reference `agenttasktemplates` instead of `atasks`.

### Removed

- Removed `atasks.scalr.io` CRD (replaced by `agenttasktemplates.scalr.io`).
- Removed unused helper templates: `agent-job.componentName`, `agent-job.dataPVCName`, `agent-job.cachePVCName`.

### Fixed

- Fixed `podSecurityContext` description comments (incorrectly referenced `podAnnotations`).

## [v0.5.67]

### Updated

- Bumping chart version to v0.5.67 for scalr-agent v0.60.0

### Changed

- Clarified metadata service access defaults and configuration in documentation.
- Added "Security > Multi-tenant Isolation" section to documentation.
- The `task.runner.image` has switched from `scalr/agent-runner` to `scalr/runner`, the entrypoint is now installed via an external GCS script.

### Fixed

- Fixed `accessModes` configuration for PVC data volume.

## [v0.5.66]

### Updated

- Bumping chart version to v0.5.66 for scalr-agent v0.59.0

- Added `SCALR_AGENT_STATE_PERSISTENCE_ENABLED=1` to disable persistent state files.

## [v0.5.65]

### Updated

- Bumping chart version to v0.5.65 for scalr-agent v0.58.0

## [v0.5.64]

### Updated

- Bumping chart version to v0.5.64 for scalr-agent v0.57.0

## [v0.5.63]

### Updated

- Bumping chart version to v0.5.63 for scalr-agent v0.56.0

## [v0.5.62]

### Updated

- Bumping chart version to v0.5.62 for scalr-agent v0.55.2

## [v0.5.61]

### Updated

- Bumping chart version to v0.5.61 for scalr-agent v0.55.1

## [v0.5.60]

### Updated

- Bumping chart version to v0.5.60 for scalr-agent v0.55.0

- Initial release.
