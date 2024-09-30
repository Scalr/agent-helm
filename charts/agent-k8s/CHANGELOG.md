# agent-k8s Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

- Added `agent.tokenExistingSecretKey` option to specify the custom secret key for the agent token.

## [v0.5.18]

### Updated

- Bumping chart version to v0.5.18 for scalr-agent v0.24.0

## [v0.5.17]

### Updated

- Bumping chart version to v0.5.17 for scalr-agent v0.23.0

## [v0.5.16]

### Updated

- Bumping chart version to v0.5.16 for scalr-agent v0.22.0

## [v0.5.15]

### Updated

- Bumping chart version to v0.5.15 for scalr-agent v0.21.0

## [v0.5.14]

### Updated

- Bumping chart version to v0.5.14 for scalr-agent v0.20.0

## [v0.5.13]

### Updated

- Bumping chart version to v0.5.13 for scalr-agent v0.19.0

## [v0.5.12]

### Updated

- Bumping chart version to v0.5.12 for scalr-agent v0.18.1

## [v0.5.11]

### Updated

- Bumping chart version to v0.5.11 for scalr-agent v0.17.0

## [v0.5.10]

### Updated

- Bumping chart version to v0.5.10 for scalr-agent v0.16.0

- Added the `agent.container_task_ca_cert` configuration option for installing the CA bundle into a task container.

## [v0.5.9]

### Updated

- Bumping chart version to v0.5.9 for scalr-agent v0.15.0

## [v0.5.8]

### Updated

- Bumping chart version to v0.5.8 for scalr-agent v0.14.1

## [v0.5.7]

### Updated

- Bumping chart version to v0.5.7 for scalr-agent v0.14.0

## [v0.5.6]

### Updated

- Bumping chart version to v0.5.6 for scalr-agent v0.13.0

## [v0.5.5]

### Updated

- Bumping chart version to v0.5.5 for scalr-agent v0.12.0

## [v0.5.4]

### Updated

- Bumping chart version to v0.5.4 for scalr-agent v0.10.1

## [v0.5.3]

### Updated

- Bumping chart version to v0.5.3 for scalr-agent v0.9.1

## [v0.5.2]

### Updated

- Bumping chart version to v0.5.2 for scalr-agent v0.9.0

## [v0.5.1]

### Updated

- Bumping chart version to v0.5.1 for scalr-agent v0.8.1

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
