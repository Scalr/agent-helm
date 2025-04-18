# agent-k8s Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

## [v0.5.41]

### Updated

- Bumping chart version to v0.5.41 for scalr-agent v0.43.0

## [v0.5.40]

### Updated

- Bumping chart version to v0.5.40 for scalr-agent v0.42.0

## [v0.5.39]

### Updated

- Bumping chart version to v0.5.39 for scalr-agent v0.41.0

## [v0.5.38]

### Updated

- Bumping chart version to v0.5.38 for scalr-agent v0.40.0

## [v0.5.37]

### Updated

- Bumping chart version to v0.5.37 for scalr-agent v0.39.0

## [v0.5.36]

### Updated

- Bumping chart version to v0.5.36 for scalr-agent v0.38.1

## [v0.5.35]

### Updated

- Bumping chart version to v0.5.35 for scalr-agent v0.38.0

## [v0.5.34]

### Updated

- Bumping chart version to v0.5.34 for scalr-agent v0.37.1

## [v0.5.33]

### Updated

- Bumping chart version to v0.5.33 for scalr-agent v0.37.0

## [v0.5.32]

### Updated

- Bumping chart version to v0.5.32 for scalr-agent v0.36.0

## [v0.5.31]

### Updated

- Bumping chart version to v0.5.31 for scalr-agent v0.35.0

## [v0.5.30]

### Updated

- Bumping chart version to v0.5.30 for scalr-agent v0.34.0

## [v0.5.29]

### Updated

- Bumping chart version to v0.5.29 for scalr-agent v0.33.0

## [v0.5.28]

### Updated

- Bumping chart version to v0.5.28 for scalr-agent v0.32.0

## [v0.5.27]

### Updated

- Bumping chart version to v0.5.27 for scalr-agent v0.31.0

## [v0.5.26]

### Updated

- Bumping chart version to v0.5.26 for scalr-agent v0.30.0

## [v0.5.25]

### Updated

- Bumping chart version to v0.5.25 for scalr-agent v0.29.0

## [v0.5.24]

### Updated

- Bumping chart version to v0.5.24 for scalr-agent v0.28.0

## [v0.5.23]

### Updated

- Bumping chart version to v0.5.23 for scalr-agent v0.28.0

## [v0.5.22]

### Updated

- Bumping chart version to v0.5.22 for scalr-agent v0.27.0

### Added

- Added `restrictMetadataService` option. When set to true, applies pod network policy that blocks outbound access to instance metadata service.

## [v0.5.21]

### Updated

- Bumping chart version to v0.5.21 for scalr-agent v0.26.1

## [v0.5.20]

### Updated

- Bumping chart version to v0.5.20 for scalr-agent v0.26.0

## [v0.5.19]

### Updated

- Bumping chart version to v0.5.19 for scalr-agent v0.25.0

- Added the option to mount the EFS filesystem to the EKS cluster as the `agent.data_home` directory.
- Added the option to enable automatic mounting of service account tokens into the agent task pods.
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
