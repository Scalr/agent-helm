# agent-local Helm Chart Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [UNRELEASED]

### Added

- Added `agent.providerNetworkMirrors` to configure OpenTofu/Terraform provider network mirrors. Each entry has a required `url`, an optional `token` bearer credential, and an optional `include` list of provider source address patterns (defaults to all providers). The chart renders the list as JSON into the `SCALR_AGENT_PROVIDER_NETWORK_MIRRORS` environment variable. Requires an agent version with network mirror support.

## [v0.6.2]

### Updated

- Bumping chart version to v0.6.2 for scalr-agent v1.2.0

### Fixed

- Fixed `helm template`/`helm install` failing with `YAML parse error ... block sequence entries are not allowed in this context` when `persistence.data.persistentVolumeClaim.storageClassName` or `persistence.cache.persistentVolumeClaim.storageClassName` was set to `"-"`. The documented `"-"` convention now works as intended and renders `storageClassName: ""` to disable dynamic provisioning. Existing setups are unaffected: an empty value still omits the field (cluster default storage class) and an explicit class name is still rendered as-is.

## [v0.6.1]

### Updated

- Bumping chart version to v0.6.1 for scalr-agent v1.1.0

### Changed

- **BREAKING:** Default `image.repository` changed from `scalr/agent-runner` to `scalr/agent`.

  The chart now defaults to the minimal [`scalr/agent`](https://hub.docker.com/r/scalr/agent) image, which ships the Scalr Agent service, the OpenTofu/Terraform runtime, and basic tooling (`git`, `curl`, `openssl`, `ca-certificates`). It does **not** ship cloud-provider CLIs (`aws`, `gcloud`, `az`, `kubectl`, `scalr-cli`) — those were previously bundled in `scalr/agent-runner`. The motivation is a smaller default image, faster pulls, and a reduced attack surface for the majority of installations that never invoke a cloud CLI from a run.

  Only installations whose runs invoke `aws`, `gcloud`, `az`, `kubectl`, `scalr-cli`, or other tooling that was previously preinstalled in `scalr/agent-runner` are affected. To check, scan your Workspace hooks and Terraform/OpenTofu modules for those binaries. Installations already using a custom `image.repository` are unaffected.

  If affected, pick one:

  - Build a custom image on top of `scalr/agent` with the required tooling preinstalled (see [Custom Agent Image](README.md#custom-agent-image)) and point the chart at it:

    ```yaml
    image:
      repository: registry.example.com/my-scalr-agent
      tag: "1.0.5"
    ```

  - Or install the required tooling on demand via Workspace pre-run hooks.

### Added

- Added custom CA bundle configuration (`agent.tls.caBundleSecret`, `agent.tls.caBundle`) for outbound TLS validation against the Scalr API, VCS providers, and provider registries. The bundle is mounted read-only at `/etc/ssl/certs/scalr-ca-bundle.crt` and exported via `SCALR_AGENT_CA_CERT` and `SSL_CERT_FILE`. Supports both existing Kubernetes secrets and inline PEM values; `caBundleSecret` takes precedence when both are set. `SCALR_AGENT_CA_CERT` and `SSL_CERT_FILE` are now reserved env var names and cannot be overridden via `extraEnv`.

- Added `extraVolumes` and `extraVolumeMounts` for mounting additional secrets, configMaps, or other volumes into the agent pod alongside the chart-managed ones.

- Added mTLS client certificate configuration (`agent.tls.clientCertSecret`, `agent.tls.clientCert`, `agent.tls.clientKey`) for mutual TLS authentication between the agent and Scalr. The bootstrap certificate and key are mounted read-only at `/etc/scalr-agent/ssl/` and mapped to `SCALR_AGENT_TLS_CERT_FILE` and `SCALR_AGENT_TLS_KEY_FILE`. Supports both existing Kubernetes secrets (including `kubernetes.io/tls` type) and inline PEM values. Note: mTLS is an upcoming Enterprise feature.

- Made the data directory persistence configurable. The `persistence.data` block now supports the same `enabled` / `emptyDir` / `persistentVolumeClaim` structure as `persistence.cache`, allowing the data volume to be backed by a PVC instead of `emptyDir`. Example:

  ```yaml
  persistence:
    data:
      enabled: true
      persistentVolumeClaim:
        storageClassName: ""        # use cluster default
        storage: 4Gi
        accessMode: ReadWriteOnce
    cache:
      enabled: true
      persistentVolumeClaim:
        storageClassName: "nfs-client"
        storage: 40Gi
        accessMode: ReadWriteMany   # share cache across replicas
  ```

- Persistence schema is now symmetric between `persistence.data` and `persistence.cache`, matching the `agent-job` chart.

### Deprecated

- The top-level `persistence.enabled` and `persistence.persistentVolumeClaim.*` keys are deprecated in favor of `persistence.cache.enabled` and `persistence.cache.persistentVolumeClaim.*`. The legacy keys still work and the chart emits a deprecation warning via `NOTES.txt` when they are used. They will be removed in a future release.

**Backward compatibility:** existing installations continue to work without any values changes. When the legacy keys are set, the chart maps them onto the cache volume and preserves the legacy default cache PVC name (`<release-fullname>`) to avoid orphaning existing PVCs on upgrade. On the new schema, the default cache PVC name is `<release-fullname>-cache` and the new data PVC default name is `<release-fullname>-data`.

**Action required (recommended migration):** move legacy values under `persistence.cache.*`. Before:

```yaml
persistence:
  enabled: true
  persistentVolumeClaim:
    claimName: "my-cache-pvc"
    storageClassName: "nfs-client"
    storage: 40Gi
    accessMode: ReadWriteMany
```

After:

```yaml
persistence:
  cache:
    enabled: true
    persistentVolumeClaim:
      claimName: "my-cache-pvc"
      storageClassName: "nfs-client"
      storage: 40Gi
      accessMode: ReadWriteMany
```

When you migrate **without specifying `claimName`** and previously relied on the auto-created PVC, note that the default PVC name changes from `<release-fullname>` to `<release-fullname>-cache`. To keep using the existing PVC, set `persistence.cache.persistentVolumeClaim.claimName: "<release-fullname>"` explicitly, or rename/re-bind the underlying PV.

## [v0.5.76]

### Updated

- Bumping chart version to v0.5.76 for scalr-agent v1.0.5

## [v0.5.75]

### Updated

- Bumping chart version to v0.5.75 for scalr-agent v1.0.4

## [v0.5.74] - YANKED

### Updated

- Released as part of an internal process, superseded by v0.5.75

## [v0.5.73]

### Updated

- Bumping chart version to v0.5.73 for scalr-agent v1.0.0

## [v0.5.72]

### Updated

- Bumping chart version to v0.5.72 for scalr-agent v0.65.1

## [v0.5.71]

### Updated

- Bumping chart version to v0.5.71 for scalr-agent v0.65.0

## [v0.5.70]

### Updated

- Bumping chart version to v0.5.70 for scalr-agent v0.64.0

## [v0.5.69]

### Updated

- Bumping chart version to v0.5.69 for scalr-agent v0.63.1

## [v0.5.68]

### Updated

- Bumping chart version to v0.5.68 for scalr-agent v0.63.0

## [v0.5.67]

### Updated

- Bumping chart version to v0.5.67 for scalr-agent v0.62.0

### Fixed

- Fixed `allowMetadataService` NetworkPolicy to be compatible with GKE Dataplane V2. Updated documentation with tested configurations and known limitations.
- Fixed an issue where `allowMetadataService: true` had no effect and the NetworkPolicy was always created regardless of the configured value.

## [v0.5.66]

### Updated

- Bumping chart version to v0.5.66 for scalr-agent v0.61.4

## [v0.5.65]

### Updated

- Bumping chart version to v0.5.65 for scalr-agent v0.61.3

## [v0.5.64]

### Updated

- Bumping chart version to v0.5.64 for scalr-agent v0.60.0

### Updated

- Upgrade default resource limits from 2 to 4 cpu.

### Added

- Added metadata service access control with `allowMetadataService` and NetworkPolicy support.
- Added OpenTelemetry configuration options for metrics and traces.
- Added "Security" section to documentation.

### Changed

- The shared data directory (which previously included cache) is now split into separate directories for workspace runtime data and cache:
  - Added `agent.cacheDir` configuration option to control the cache directory location, default is `/var/lib/scalr-agent/cache`.
  - Default `agent.dataDir` mount changed from `/var/lib/scalr-agent` to `/var/lib/scalr-agent/data` to avoid collisions with the cache directory.
  - The `persistence.enabled` option now applies only to the cache directory using a single shared PVC. The data directory will remain on emptyDir regardless of the `persistence.enabled` setting, as the data directory doesn't require persistence.
  - The `persistence.emptyDir.sizeLimit=20Gi` is now split into `persistence.data.emptyDir.sizeLimit=4Gi` and `persistence.cache.emptyDir.sizeLimit=1Gi`.

## [v0.5.63]

### Updated

- Bumping chart version to v0.5.63 for scalr-agent v0.59.0

### Added

- Added `agent.shutdownMode` configuration option to control agent termination behavior. Options are `graceful` (default), `force`, or `drain`.

### Changed

- **BREAKING**: Updated validation for minimum `terminationGracePeriodSeconds` value from 10 to 30 seconds for the default `graceful` shutdown mode to prevent undefined behavior and stuck runs. Set `agent.shutdownMode=force` if you need `terminationGracePeriodSeconds` below 30 seconds (minimum is 10 seconds).
- Default `terminationGracePeriodSeconds` changed from 360 seconds to 120 seconds.

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
