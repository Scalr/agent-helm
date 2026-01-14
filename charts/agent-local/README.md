# agent-local

![Version: 0.5.63](https://img.shields.io/badge/Version-0.5.63-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.59.0](https://img.shields.io/badge/AppVersion-0.59.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
Deploys a static number of agents and executes runs in shared agent pods.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Configuration](#configuration)
- [Customizing Environment](#customizing-environment)
- [Volumes](#volumes)
- [Security](#security)
- [Metrics and Observability](#metrics-and-observability)
- [Termination](#termination)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Kubernetes 1.33+
- Helm 3.0+
- ReadWriteMany volumes for [Cache Volume Persistence](#cache-volume-persistence) (optional)
- Scalr Agent >= 0.45.0

## Installation

To install the chart with the release name `scalr-agent`:

```console
$ helm repo add scalr-charts https://scalr.github.io/agent-helm/
$ helm install scalr-agent scalr-charts/agent-local --set agent.token="<agent-token>"
```

_See [configuration](#values) below._

_See [helm install](https://helm.sh/docs/helm/helm_install/) for command documentation._

## Overview

The agent-local chart deploys the Scalr Agent as a single Deployment with ephemeral storage for
provider and binary caching. Storage can optionally be upgraded to persistent volumes to maintain
cache persistence across pod restarts.

The chart uses the `local` Scalr Agent driver, where all operations are executed in local subprocesses.
As a result, it uses the `scalr/agent` image as the base environment for runs instead of [scalr/runner](https://docs.scalr.io/docs/self-hosted-agents-pools#golden-image-beta) image.

The concurrency of each agent instance is limited to 1. To scale concurrency, the recommended approach is to increase the `replicaCount`.

### Pros

- Simple to deploy.
- Scalr Agent service doesn’t require permissions to access the Kubernetes API.
- Includes Provider Cache and Binary Cache by default.

### Cons

- Doesn’t support autoscaling out of the box. You need manually increase or decrease the number of replicas or configure Horizontal Pod Autoscaler.
- Not cost-efficient for bursty workloads — e.g., deployments with high number of Runs during short periods and low activity otherwise, as resources remain allocated even when idle.
- Low multi-tenant isolation. A sequence of Scalr Runs shares the same container and data storage. See [Multi-tenant Isolation](#multi-tenant-isolation)

## Architecture Diagram

<p align="center">
  <img src="assets/deploy-diagram.drawio.svg" />
</p>

## Configuration

The Scalr Agent is configured using environment variables, which can be set using the `extraEnv` option in the Helm chart.

```console
$ helm install ...
  --set extraEnv.SCALR_AGENT_DEBUG=1 \
  --set extraEnv.HTTPS_PROXY="http://myproxy.com:3128"
```

See all available configuration options - https://docs.scalr.io/docs/configuration

## Customizing Environment

This chart uses the local driver to run tasks directly within the container where the agent operates. Therefore, it requires an image that includes both the Scalr Agent service and the additional tooling provided by the [scalr/runner](https://hub.docker.com/r/scalr/runner) image. As a result, this chart uses the [scalr/agent-runner](https://hub.docker.com/r/scalr/agent-runner) image, which combines the minimal Scalr Agent image ([scalr/agent](https://hub.docker.com/r/scalr/agent)) with the extra tools from `scalr/runner`. You can use this image, or `scalr/agent` (as a minimal base for building your own lightweight images), as a starting point for customizing your environment.

## Volumes

Two volumes are always attached to agent Pods:

- **Data Volume**

  The data volume stores temporary workspace data needed for processing a run, including run metadata and source code.

  The default configuration uses ephemeral `emptyDir` storage with a 4GB limit.

  The volume is mounted at `agent.dataDir`, which must be readable, writable, and executable.

- **Cache Volume**

  The cache volume stores software binaries, OpenTofu/Terraform providers and modules.

  The default configuration uses ephemeral `emptyDir` storage with a 20GB limit.

  The volume is mounted at `agent.cacheDir`, which must be readable, writable, and executable for OpenTofu/Terraform plugin execution.

### Cache Volume Persistence

It's recommended to enable persistent storage with `ReadWriteMany` access mode to share the cache across all agent pods.

Benefits of persistent cache:

- Faster task execution (no provider/modules/binaries re-downloads on cold agents)
- Reduced network bandwidth usage
- Better fault tolerance during module/provider registry outages

Learn more about [Provider Cache](https://docs.scalr.io/docs/providers-cache) and [Module Cache](https://docs.scalr.io/docs/modules-cache).

**Configuration Example with PVC**:

```yaml
persistence:
  enabled: true
  persistentVolumeClaim:
    # Use existing PVC
    claimName: "my-cache-pvc"
    # Or create new PVC (omit claimName)
    storageClassName: "nfs-client"
    storage: 40Gi
    accessMode: ReadWriteMany
extraEnv:
  SCALR_AGENT_PROVIDER_CACHE_ENABLED: "1" # enabled by default
  SCALR_AGENT_MODULE_CACHE_ENABLED: "1" # disabled by default
```

If configured correctly, you should see confirmation in the Scalr Run console that plugins and modules are being used from cache:

```shell
Initializing modules...
Initialized 8 modules in 4.12s (8 used from cache)
Initializing plugins...
Initialized 20 plugins in 6.09s (20 used from cache)
```

## Security

### Multi-tenant Isolation

This chart deploys a set of static agent workers that process runs sequentially within the same container, which provides a simple and easy-to-maintain architecture but has important security implications for multi-tenant environments:

- **Container reuse**: Multiple runs may execute in the same container without cleanup between executions.
- **Shared filesystem**: The agent process and Scalr Run commands (OpenTofu/Terraform) execute in the same container without filesystem isolation, allowing runs to write to shared cache storage that will be reused by subsequent runs.
- **Cache tampering risk**: Runs can potentially modify cached providers or modules directly without verification.

As a result this chart is suitable only for trusted, single-tenant environments within a single RBAC perimeter.

To enhance security and achieve better isolation between runs:
  - Enable single-run mode to restart the container after each execution and disable provider/module caching:
    ```yaml
    extraEnv:
      SCALR_AGENT_SINGLE: "true"
      SCALR_AGENT_PROVIDER_CACHE_ENABLED: "false"
      SCALR_AGENT_MODULE_CACHE_ENABLED: "false"
    ```
  - Use separate agent node pools for each RBAC perimeter (e.g., Scalr Environment).

### Agent Security Context

Agent pods inherit their Linux user, group, seccomp, and capability settings from `securityContext` configuration. The defaults run the container as the non-root UID/GID `1000`, drop all Linux capabilities, and enforce a read-only root filesystem.

The default is strict and compatible with Terraform/OpenTofu workloads, and it’s generally not recommended to change it. However, it can be useful to disable `readOnlyRootFilesystem` and switch the user to root if you need to install packages via package managers like `apt-get` or `dnf` from Workspace hooks.

### Access to VM Metadata Service

The chart includes an `allowMetadataService` configuration option to control access to the VM metadata service at 169.254.169.254, which is common for AWS, GCP, and Azure environments.

When disabled, the chart creates a Kubernetes NetworkPolicy for agent pods that denies egress traffic to 169.254.169.254/32, blocking access to the VM metadata service. All other outbound traffic is allowed.

Access is enabled by default. To restrict VM metadata service access, use:

```shell
$~ helm upgrade ... \
    --set allowMetadataService=false
```

## Metrics and Observability

The agent can be configured to send telemetry data, including both trace spans and metrics, using [OpenTelemetry](https://opentelemetry.io/).

OpenTelemetry is an extensible, open-source telemetry protocol and platform that enables the Scalr Agent to remain vendor-neutral while producing telemetry data for a wide range of platforms.

Enable telemetry agent by configuring an OpenTelemetry collector endpoint:

```yaml
extraEnv:
  SCALR_AGENT_OTLP_ENDPOINT: "otel-collector:4317"  # gRPC endpoint
  SCALR_AGENT_OTLP_METRICS_ENABLED: "true"
  SCALR_AGENT_OTLP_TRACES_ENABLED: "true"
```

See [all configuration options](https://docs.scalr.io/docs/configuration#telemetry).

Learn more about [available metrics](https://docs.scalr.io/docs/metrics).

## Termination

The agent termination behavior is controlled by `agent.shutdownMode` Helm option.
The value can be `graceful` (default), `drain`, or `force`.

The agent termination behavior is configured via [SCALR_AGENT_WORKER_ON_STOP_ACTION](https://docs.scalr.io/docs/configuration#scalr_agent_worker_on_stop_action) with Kubernetes `terminationGracePeriodSeconds` in mind.
Timeouts are calculated dynamically based on `terminationGracePeriodSeconds`.

### `graceful` Termination

The agent's default termination mode is `graceful`.

In this mode, after receiving a `SIGTERM` signal from Kubernetes, the agent immediately forwards the `SIGTERM` signal to the underlying process (such as OpenTofu or Terraform) and waits for it to complete before shutting down.

The underlying process has `terminationGracePeriodSeconds` minus 10 seconds to complete, otherwise, it will be forcefully stopped via a `SIGKILL` signal.

The `terminationGracePeriodSeconds` must be at least 30 seconds for `graceful` mode.

### `drain` Termination

In `drain` mode, the agent shuts down its consumer and stops accepting new tasks, but continues running active tasks (and their underlying OpenTofu/Terraform processes) without interruption for `terminationGracePeriodSeconds` minus 70 seconds. During the final 70 seconds, it switches to graceful termination: it sends `SIGTERM` to any active Terraform/OpenTofu processes and waits up to 60 seconds for them to complete gracefully. If processes are still running after 60 seconds, the agent uses the remaining 10 seconds to forcefully terminate them via `SIGKILL` and push task results to the Scalr platform.

The `terminationGracePeriodSeconds` must be at least 120 seconds for `drain` mode.

### `force` Termination

In `force` mode, the agent stops the consumer, sends a `SIGKILL` signal to all active Terraform/OpenTofu processes, and allows 10 seconds for all tasks to terminate before exiting.

The `terminationGracePeriodSeconds` must be at least 10 seconds for `force` mode.

## Troubleshooting

If you encounter internal system errors or unexpected behavior, please open a Scalr Support request at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31).

Before doing so, enable debug logs using the `extraEnv.SCALR_AGENT_DEBUG` option. Then collect the debug-level application logs covering the time window when the incident occurred, and attach them to your support ticket.

To archive all logs from the Scalr agent namespace in a single bundle, replace the `ns` variable with the name of your Helm release namespace and run:

```shell
ns="scalr-agent"
mkdir -p logs && for pod in $(kubectl get pods -n $ns -o name); do kubectl logs -n $ns $pod > "logs/${pod##*/}.log"; done && zip -r agent-local-logs.zip logs && rm -rf logs
```

It's best to pull the logs immediately after an incident, since this command will not retrieve logs from restarted or terminated pods.

---

**Homepage:** <https://github.com/Scalr/agent-helm/tree/master/charts/agent-local>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

### Agent

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.cacheDir | string | `"/var/lib/scalr-agent/cache"` | Cache directory where the agent stores provider binaries, plugin cache, and metadata. This directory must be readable, writable, and executable. |
| agent.dataDir | string | `"/var/lib/scalr-agent/data"` | Data directory where the agent stores workspace data (configuration versions, modules, and providers). This directory must be readable, writable, and executable. |

### Persistence

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| persistence.cache.emptyDir.sizeLimit | string | `"20Gi"` | Size limit for the emptyDir volume. |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod scheduling. |
| agent.shutdownMode | string | `"graceful"` | The agent termination behaviour. Can be graceful, force or drain. See https://docs.scalr.io/docs/configuration#scalr_agent_worker_on_stop_action |
| agent.token | string | `""` | The agent pool token. |
| agent.tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| agent.url | string | `""` | The Scalr API endpoint URL. For tokens generated after Scalr version 8.162.0, this value is optional, as the domain can be extracted from the token payload. However, it is recommended to specify the URL explicitly for long-lived services to avoid issues if the account is renamed. |
| allowMetadataService | bool | `true` | Allow access to cloud provider metadata service (169.254.169.254). When false, creates a NetworkPolicy that blocks agent containers from accessing the metadata service. This enhances security by preventing workloads from retrieving cloud credentials or instance metadata. |
| extraEnv | object | `{}` | Additional environment variables for Scalr Agent. Use to configure HTTP proxies or other runtime parameters. |
| fullnameOverride | string | `""` | Fully override the resource name for all resources. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. 'IfNotPresent' is efficient for stable deployments. |
| image.repository | string | `"scalr/agent-runner"` | Docker repository for the Scalr Agent image. |
| image.tag | string | `""` | Image tag. Overrides the default (chart appVersion). Leave empty to use chart default. |
| imagePullSecrets | list | `[]` | Image pull secret to use for registry authentication. |
| nameOverride | string | `""` | Override the default resource name prefix for all resources. |
| nodeSelector | object | `{}` | Node selector for scheduling Scalr Agent pods. |
| persistence | object | `{"cache":{"emptyDir":{"sizeLimit":"20Gi"}},"data":{"emptyDir":{"sizeLimit":"4Gi"}},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteOnce","claimName":"","storage":"20Gi","storageClassName":"","subPath":""}}` | Persistent storage configuration for the Scalr Agent data and cache volumes. |
| persistence.cache | object | `{"emptyDir":{"sizeLimit":"20Gi"}}` | Cache directory storage configuration. Stores OpenTofu/Terraform providers, modules and binaries. |
| persistence.cache.emptyDir | object | `{"sizeLimit":"20Gi"}` | EmptyDir volume configuration (used when persistence.enabled is false). |
| persistence.data | object | `{"emptyDir":{"sizeLimit":"4Gi"}}` | Data directory storage configuration. Stores workspace data including configuration versions, modules, and run metadata. |
| persistence.data.emptyDir | object | `{"sizeLimit":"4Gi"}` | EmptyDir volume configuration. |
| persistence.data.emptyDir.sizeLimit | string | `"4Gi"` | Size limit for the emptyDir volume. |
| persistence.enabled | bool | `false` | Enable persistent storage for cache volume. If false, uses emptyDir (ephemeral storage). |
| persistence.persistentVolumeClaim | object | `{"accessMode":"ReadWriteOnce","claimName":"","storage":"20Gi","storageClassName":"","subPath":""}` | Configuration for persistentVolumeClaim for cache volume (used when persistence.enabled is true). |
| persistence.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC. Use "ReadWriteOnce" for single-replica deployments. Use "ReadWriteMany" only if the Scalr Agent supports shared storage (e.g., with NFS). |
| persistence.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC is created dynamically. |
| persistence.persistentVolumeClaim.storage | string | `"20Gi"` | Storage size for the PVC. |
| persistence.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and require a pre-existing PVC. |
| persistence.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |
| podAnnotations | object | `{}` | Annotations for Scalr Agent pods (e.g., for monitoring or logging). |
| podSecurityContext | object | `{"fsGroup":1000,"runAsNonRoot":true}` | Security context for Scalr Agent pod. |
| replicaCount | int | `1` | Number of replicas for the Scalr Agent deployment. Adjust for high availability. |
| resources | object | `{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"1000m","memory":"1024Mi"}}` | Resource limits and requests for Scalr Agent pods. Set identical resource limits and requests to enable Guaranteed QoS and minimize eviction risk. See: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/#quality-of-service-classes |
| secret | object | `{"annotations":{},"labels":{}}` | Secret configuration for storing the Scalr Agent token. |
| secret.annotations | object | `{}` | Annotations for the Secret resource. |
| secret.labels | object | `{}` | Additional labels for the Secret resource. |
| securityContext | object | `{"capabilities":{"drop":["ALL"]},"privileged":false,"procMount":"Default","runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000}` | Security context for Scalr Agent container. |
| securityContext.capabilities | object | `{"drop":["ALL"]}` | Restrict container capabilities for security. |
| securityContext.privileged | bool | `false` | Run container in privileged mode. Enable only if required. |
| securityContext.procMount | string | `"Default"` | Proc mount type. Valid values: Default, Unmasked, Host. |
| serviceAccount.annotations | object | `{}` | Annotations for the service account. |
| serviceAccount.automountToken | bool | `false` | Whether to automount the service account token in the Scalr Agent pod. |
| serviceAccount.create | bool | `false` | Create a Kubernetes service account for the Scalr Agent. |
| serviceAccount.labels | object | `{}` | Additional labels for the service account. |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and 'create' is true. |
| strategy | object | `{"rollingUpdate":{"maxSurge":"25%","maxUnavailable":"50%"},"type":"RollingUpdate"}` | Deployment strategy configuration. |
| strategy.rollingUpdate | object | `{"maxSurge":"25%","maxUnavailable":"50%"}` | Rolling update parameters. |
| strategy.rollingUpdate.maxSurge | string | `"25%"` | Maximum number of pods that can be created above the desired number during an update. |
| strategy.rollingUpdate.maxUnavailable | string | `"50%"` | Maximum number of pods that can be unavailable during an update. |
| strategy.type | string | `"RollingUpdate"` | Type of deployment strategy. Options: RollingUpdate, Recreate. |
| terminationGracePeriodSeconds | int | `120` | Termination grace period (in seconds) for pod shutdown. |
| tolerations | list | `[]` | Tolerations for scheduling pods on tainted nodes. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
