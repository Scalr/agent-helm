# agent-job Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

### Breaking Changes

- **Selector labels changed**: The default `app.kubernetes.io/name` label changed from `agent-job` to `scalr-agent`. Kubernetes does not allow modifying Deployment selectors, so existing installations will fail to upgrade with "field is immutable" error.

  Migration options:

  - Delete the existing Deployment before upgrading (causes brief downtime, uninstallation will termineta active jobs):

    ```bash
    kubectl delete deployment <release-name> -n <namespace>
    helm upgrade --install <release-name> scalr-agent/agent-job ...
    ```

  - Preserve the old name to maintain compatibility (no downtime):

    ```bash
    helm upgrade --install <release-name> scalr-agent/agent-job \
    --set nameOverride="agent-job" ...
    ```

- **CRD replaced**: The `atasks.scalr.io` CRD has been replaced by `agenttasktemplates.scalr.io`. Existing `AgentTask` resources will no longer be recognized. The old CRD must be manually removed after upgrading:

  ```bash
  kubectl delete crd atasks.scalr.io
  ```

### Added

- Added `task.job.basename` option to override the base name prefix for spawned Kubernetes Jobs.
- Added "Task Naming" documentation section explaining how Job names are generated.

### Changed

- Renamed CRD from `AgentTask` to `AgentTaskTemplate` for clarity, as the CRD defines a template for tasks, not a task itself.
- Default base name changed from chart name (`agent-job`) to `scalr-agent` for cleaner resource naming.
- Deployment and task template names now use the `fullname` template instead of hardcoded values.
- Updated RBAC to reference `agenttasktemplates` instead of `atasks`.
- Job naming scheme changed from `atask-xxx` to `<basename>-<run-id>-<stage>` (e.g., `scalr-agent-run-v0p500fu3s9ban8s8-plan`). This provides better control over job naming and uses run IDs familiar to users and operators for better observability.
- ClusterRole and ClusterRoleBinding names now include namespace prefix to avoid conflicts in multi-namespace deployments.

### Removed

- Removed `atasks.scalr.io` CRD (replaced by `agenttasktemplates.scalr.io`).
- Removed unused helper templates: `agent-job.componentName`, `agent-job.dataPVCName`, `agent-job.cachePVCName`.

### Fixed

- Fixed `podSecurityContext` description comments (incorrectly referenced `podAnnotations`).
- Fixed selector labels not being included in Deployment pod template labels.
- Fixed pod labels indentation in Deployment template.
- Fixed ClusterRoleBinding by removing incorrect `namespace` field from metadata.

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
