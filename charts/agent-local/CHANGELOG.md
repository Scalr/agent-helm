# agent-local Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

### Added

- Added `agent.shutdownMode` configuration option to control agent termination behavior. Options are `graceful` (default), `force`, or `drain`.

### Changed

- **BREAKING**: Updated validation for minimum `terminationGracePeriodSeconds` value from 10 to 30 seconds for the default `graceful` shutdown mode to prevent undefined behavior and stuck runs. Set `agent.shutdownMode=force` if you need `terminationGracePeriodSeconds` below 30 seconds (minimum is 10 seconds).

## [v0.5.62]

### Updated

- Bumping chart version to v0.5.62 for scalr-agent v0.58.0

## [v0.5.61]

### Updated

- Bumping chart version to v0.5.61 for scalr-agent v0.57.0

### Changed

- The agent's default termination mode is changed from `drain` to `grace-shutdown` via the `SCALR_AGENT_WORKER_ON_STOP_ACTION` configuration. The application layer graceful termination timeout (`SCALR_AGENT_WORKER_GRACE_SHUTDOWN_TIMEOUT`) is set to Kubernetes' `terminationGracePeriodSeconds` minus 10 seconds to give the agent some additional time to terminate and push task results to the Scalr platform. As a result, `terminationGracePeriodSeconds` must be at least 10 seconds.
- **BREAKING:** The `extraEnv` configuration now has addional validations. The following variables are controlled by the chart and cannot be overridden via `extraEnv` to maintain configuration consistency and avoid undefined behavior:
  - `SCALR_AGENT_NAME`
  - `SCALR_URL`
  - `SCALR_AGENT_DRIVER`
  - `SCALR_AGENT_CONCURRENCY`
  - `SCALR_AGENT_DISCONNECT_ON_STOP`
  - `SCALR_AGENT_WORKER_ON_STOP_ACTION`
  - `SCALR_AGENT_WORKER_GRACE_SHUTDOWN_TIMEOUT`
  - `SCALR_AGENT_DATA_DIR`
  - `SCALR_AGENT_TOKEN`

  Users must remove any of these keys from their `extraEnv` configuration before upgrading. If you have any concerns regarding the configuration of these variables, please address them in a GitHub issue.

## [v0.5.60]

### Updated

- Bumping chart version to v0.5.60 for scalr-agent v0.56.0

## [v0.5.59]

### Updated

- Bumping chart version to v0.5.59 for scalr-agent v0.55.2

## [v0.5.58]

### Updated

- Bumping chart version to v0.5.58 for scalr-agent v0.55.1

## [v0.5.57]

### Updated

- Bumping chart version to v0.5.57 for scalr-agent v0.55.0

## [v0.5.56]

### Updated

- Bumping chart version to v0.5.56 for scalr-agent v0.54.0

## [v0.5.55]

### Updated

- Bumping chart version to v0.5.55 for scalr-agent v0.53.0

### Added

- Added new annotations for Karpenter and GKE Autopilot to reduce the risk of pod eviction:
  - `karpenter.sh/do-not-evict: "true"`
  - `karpenter.sh/do-not-disrupt: "true"`
  - `autopilot.gke.io/priority: high`

### Changes

- Update default size limit of emptyDir and PVC to 20Gi.
- Use the Helm fullname for the default secret instead of the name, to allow installing multiple releases in a single namespace.
- Use the newer `SCALR_AGENT` prefix for environment variables.

## [v0.5.54]

### Updated

- Bumping chart version to v0.5.54 for scalr-agent v0.52.3

## [v0.5.53]

### Updated

- Bumping chart version to v0.5.53 for scalr-agent v0.52.2

## [v0.5.52]

### Updated

- Bumping chart version to v0.5.52 for scalr-agent v0.52.1

## [v0.5.51]

### Updated

- Bumping chart version to v0.5.51 for scalr-agent v0.52.0

## [v0.5.50]

### Updated

- Bumping chart version to v0.5.50 for scalr-agent v0.51.0

## [v0.5.49]

### Updated

- Bumping chart version to v0.5.49 for scalr-agent v0.50.0

## [v0.5.48]

### Updated

- Bumping chart version to v0.5.48 for scalr-agent v0.49.0

## [v0.5.47]

### Updated

- Bumping chart version to v0.5.47 for scalr-agent v0.48.0

## [v0.5.46]

### Updated

- Bumping chart version to v0.5.46 for scalr-agent v0.48.0

### Changes

- Switch the agent-local chart from the scalr/agent image to the scalr/agent-runner image, which includes extra tooling (git, aws-cli, gcloud, azure-cli, etc.).

### Fixed

- Resolved the error `git must be available and on the PATH` when installing Terraform modules via Git with the default configuration.

## [v0.5.45]

### Updated

- Bumping chart version to v0.5.45 for scalr-agent v0.47.0

## [v0.5.44]

### Updated

- Bumping chart version to v0.5.44 for scalr-agent v0.46.0

## [v0.5.43]

### Updated

- Bumping chart version to v0.5.43 for scalr-agent v0.45.0

## [v0.5.42]

### Updated

- Bumping chart version to v0.5.42 for scalr-agent v0.44.4

## [v0.5.41]

### Updated

- Bumping chart version to v0.5.41 for scalr-agent v0.44.2
