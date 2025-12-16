# agent-job

![Version: 0.5.64](https://img.shields.io/badge/Version-0.5.64-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.57.0](https://img.shields.io/badge/AppVersion-0.57.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
It uses a job-based model, where each Scalr Run is isolated
in its own Kubernetes Job.

See the [official documentation](https://docs.scalr.io/docs/agent-pools) for more information about Scalr Agents.

> [!WARNING]
> This chart is in Alpha, and implementation details are subject to change.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Architecture Diagram](#architecture-diagram)
- [Custom Runner Images](#custom-runner-images)
- [Performance Optimization](#performance-optimization)
- [Graceful Termination](#graceful-termination)
- [HTTP Proxy](#http-proxy)
- [Custom Certificate Authorities](#custom-certificate-authorities)
- [Volumes](#volumes)
- [Security](#security)
- [Job History Management](#job-history-management)
- [Metrics and Observability](#metrics-and-observability)
- [Custom Resource Definitions](#custom-resource-definitions)
- [RBAC](#rbac)
- [Troubleshooting and Support](#troubleshooting-and-support)

## Prerequisites

- Kubernetes 1.33+
- Helm 3.0+
- ReadWriteMany volumes for [Cache Volume Persistence](#cache-volume-persistence) (optional)

## Installation

To install the chart with the release name `scalr-agent`:

```shell
# Add the Helm repo
helm repo add scalr-agent https://scalr.github.io/agent-helm/
helm repo update

# Install or upgrade the chart
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --set agent.token="<agent-pool-token>"
```

## Overview

The `agent-job` Helm chart deploys a [Scalr Agent](https://docs.scalr.io/docs/agent-pools) that uses a job-based architecture to execute IaC tasks in Kubernetes.

The chart consists of two Kubernetes resources: **[agent](#agent)** and **[agent task](#agent-task)**.

### Agent

The agent is a [Kubernetes Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), deployed by default as a single replica consisting of one container:

- **controller**: The Scalr Agent process in controller mode, based on the `scalr/agent` image.

The agent controller is responsible for polling incoming tasks from Scalr and launching them as isolated Kubernetes Jobs.

See [template](https://github.com/Scalr/agent-helm/blob/master/charts/agent-job/templates/agent.yaml).

### Agent Task

Each agent task is a [Kubernetes Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/) created by the agent controller. It consists of two isolated containers:

- **runner**: The environment where the run (Terraform/OpenTofu operations, OPA policies, shell hooks, etc.) is executed, based on the [scalr/runner](https://hub.docker.com/r/scalr/runner) image (temporary [scalr/agent-runner](https://hub.docker.com/r/scalr/agent-runner)).
- **worker**: The Scalr Agent process in worker mode, that supervises task execution, using the [scalr/agent](https://hub.docker.com/r/scalr/agent) image.

The task template is defined via a [Custom Resource Definition](#custom-resource-definitions). The agent **controller** uses this resource to create Jobs from a template fully managed by this Helm chart. The controller may patch the Job definition to inject dynamic resources, such as labels and annotations with resource IDs (run ID, workspace ID, etc.).

The runner and worker containers share a single disk volume, allowing the worker to provision the configuration version, providers, and software binaries required by the runner container.

The number of agent task Jobs depends on the active workload that the Scalr platform delegates to the agent pool to which the agent is connected.

See [template](https://github.com/Scalr/agent-helm/blob/master/charts/agent-job/templates/task.yaml).

### Pros

- Cost-efficient for bursty workloads — e.g., deployments with high number of Runs during short periods and low activity otherwise, as resources allocated on demand for each Scalr Run.
- High multi-tenant isolation, as each Scalr Run always has its own newly provisioned environment.
- Better observability, as each Scalr Run is tied to its own unique Pod.

### Cons

- Requires access to the Kubernetes API to launch new Pods.
- Requires a ReadWriteMany Persistent Volume configuration for provider/binary caching. This type of volume is generally vendor-specific and not widely available across all cloud providers.

## Architecture Diagram

<p align="center">
  <img src="assets/deploy-diagram.drawio.svg" />
</p>

## Custom Runner Images

The chart uses `scalr/runner` by default to provision run environments.

> [!NOTE]
> Currently, `scalr/agent-runner` is temporarily used instead. This image bundles agent code with the runner to provision the entrypoint script. This will be replaced with `scalr/runner` in a future releases.

You can override `task.runner.image.*` to use a custom runner image.
If you are using a custom runner image, it must include a user with UID/GID `1000`. By default, Scalr images come with a user `scalr` under `1000:1000`.

Example override:

```shell
helm upgrade --install scalr-agent scalr-charts/agent-job \
  --set agent.token="<agent-token>" \
  --set task.runner.image.repository="registry.example.com/custom-runner" \
  --set task.runner.image.tag="v1.2.3"
```

## Performance Optimization

The following additional configurations are recommended to optimize Scalr Run startup time and overall chart performance.

### Optimize Job Startup Time

This chart uses Kubernetes Jobs to launch runs, so fast Job launch is critical for low Scalr Run startup latency. Common bottlenecks that may introduce latency include slow image pull times on cold nodes. To optimize this, you can:

- Use image copies in an OCI-compatible registry mirror (Google Container Registry, Amazon Elastic Container Registry, Azure Container Registry, and similar) located in the same region as your node pool. This enables faster pull times and reduces the risk of hitting Docker Hub rate limits.
- Use a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) to preemptively cache all images used in this chart (`scalr/agent`, `scalr/runner`).
- Enable [Image Streaming](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/image-streaming) (GKE only) to improve Job launch time.

### Use Persistent Cache

A major performance bottleneck in any IaC pipeline is the time spent re-downloading binaries, providers, and modules during each run. To optimize this, we recommend enabling [Cache Directory Persistence](#cache-volume-persistence).

## Graceful Termination

Both the controller (long-lived service) and worker (one-off function per run) agents maintain a registration and liveness indicator within the Scalr Agent Pool throughout their entire runtime. When an agent stops, it deregisters itself automatically from the Scalr platform as part of its shutdown procedure after receiving a SIGTERM signal.

Force-terminating active Jobs (e.g., with SIGKILL) or terminating with an insufficient grace period may interrupt underlying IaC workflows and lead to undefined behavior. To prevent Pod eviction for active task Jobs, the default configuration applies the following annotations to reduce the risk of evictions by common autoscalers like Cluster Autoscaler, GKE Autopilot, and Karpenter:

```yaml
cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
karpenter.sh/do-not-evict: "true"
karpenter.sh/do-not-disrupt: "true"
autopilot.gke.io/priority: "high"
```

## HTTP Proxy

Configure HTTP proxy settings for external connectivity:

```yaml
global:
  proxy:
    enabled: true
    httpProxy: "http://proxy.example.com:8080"
    httpsProxy: "http://proxy.example.com:8080"
    noProxy: "localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
```

The `noProxy` setting should include Kubernetes internal domains to avoid routing cluster traffic through the proxy.

## Custom Certificate Authorities

If your environment uses custom or self-signed certificates, you can configure the CA bundle used by the agent for TLS validation. This configuration sets the **primary CA bundle** for all agent HTTPS connections (to Scalr API, VCS providers, provider registries, etc.).

> [!IMPORTANT]
> This replaces the system default CA certificates. If you need to trust both custom CAs and public CAs, include the complete certificate chain with both your custom certificates and standard root CAs in the bundle.

You can provide the CA bundle in two ways:

**Option 1: Inline CA bundle**

```yaml
global:
  tls:
    caBundle: |
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAKZ...
      -----END CERTIFICATE-----
      -----BEGIN CERTIFICATE-----
      MIIEFzCCAv+gAwIBAgIUDiCT...
      -----END CERTIFICATE-----
```

**Option 2: Reference existing secret**

```yaml
global:
  tls:
    caBundleSecret:
      name: "my-ca-bundle"
      key: "ca-bundle.crt"
```

To create the secret:

```shell
kubectl create secret generic my-ca-bundle \
  --from-file=ca-bundle.crt=/path/to/your/ca-bundle.crt \
  -n scalr-agent
```

If both `caBundleSecret.name` and `caBundle` are set, `caBundleSecret` takes precedence.

## Volumes

Two volumes are always attached to run Pods:

- **Data Volume**

  The data volume stores temporary workspace data needed for processing a run, including run metadata and source code.

  The default configuration uses ephemeral `emptyDir` storage with a 4GB limit.

- **Cache Volume**

  The cache volume stores software binaries, OpenTofu/Terraform providers and modules (TBD). This volume is mounted to both the worker (full access) and runner (read-only access to some directories) containers.

  The default configuration uses ephemeral `emptyDir` storage with a 1GB limit. By default, this is used only for the software binaries cache (since it is the default location for these tools), and the OpenTofu/Terraform provider cache is disabled by default.

### Cache Volume Persistence

It's recommended to enable persistent storage with `ReadWriteMany` access mode to share the cache across all task pods. This significantly improves performance by avoiding repeated downloads (saves 1-5 minutes per task).

Benefits of persistent cache:

- Faster task execution (no provider/binaries re-downloads)
- Reduced network bandwidth usage
- Better fault tolerance during module/provider registry outages

When enabling a persistent cache directory, it is recommended to also enable provider cache (`providerCache.enabled=true`). Otherwise, only software binaries (Terraform/OpenTofu/OPA/Infracost/etc.) will be cached.

Learn more about [Provider Cache](https://docs.scalr.io/docs/providers-cache).

**Configuration Example with PVC**:

```yaml
persistence:
  cache:
    enabled: true
    persistentVolumeClaim:
      # Use existing PVC
      claimName: "my-cache-pvc"
      # Or create new PVC (omit claimName)
      storageClassName: "nfs-client"
      storage: 40Gi
      accessMode: ReadWriteMany
agent:
  providerCache:
    enabled: true
    sizeLimit: 20Gi # soft-limit
```

If configured correctly, you should see confirmation in the Scalr Run console that plugins are being used from cache:

```shell
Initializing plugins and modules...
Initialized 20 plugins and 0 modules in 6.09s (20 plugins used from cache)
```

See detailed guides:

- [GKE Filestore](docs/cache-persistence-filestore.md)

### Data Volume Persistence

The default configuration uses ephemeral `emptyDir` storage. Since the workspace volume does not need to be shared or persisted between runs, we recommend using an ephemeral volume so that it is bound to the lifetime of the run and automatically destroyed when the Job is deleted.

Optionally, you can configure a PVC using `persistence.data.enabled` and `persistence.data.persistentVolumeClaim` options, similar to the [cache volume configuration](#cache-volume-persistence).

## Security

### Runner Security Context

Runner pods inherit their Linux user, group, seccomp, and capability settings from `task.runner.securityContext`. The defaults run the container as the non-root UID/GID `1000`, drop all Linux capabilities, and enforce a read-only root filesystem.

The default is strict and compatible with Terraform/OpenTofu workloads, and it’s generally not recommended to change it. However, it can be useful to disable `readOnlyRootFilesystem` and switch the user to root if you need to install packages via package managers like `apt-get` or `dnf` from Workspace hooks.

### Restrict Access to VM Metadata Service

The chart includes a feature to restrict task pods from accessing the VM metadata service at 169.254.169.254, which is common for both AWS and GCP environments.

By default this option is enabled, and a Kubernetes NetworkPolicy is applied to task pods that denies egress traffic to 169.254.169.254/32, blocking access to the VM metadata service. All other outbound traffic is allowed.

To disable this restriction, set `task.allowMetadataService` to `true`:

```shell
$~ helm upgrade ... \
    --set task.allowMetadataService=true
```

**Note**: The controller pod is not affected by this NetworkPolicy and retains full network access.

> [!WARNING]
> Ensure that your cluster is using a CNI plugin that supports egress NetworkPolicies. Example: Calico, Cilium, or native GKE NetworkPolicy provider for supported versions.
>
> If your cluster doesn't currently support egress NetworkPolicies, you may need to recreate it with the appropriate settings.

## Job History Management

Kubernetes automatically removes Jobs after `task.job.ttlSecondsAfterFinished` seconds (default: 60). Increase this value for debugging or to preserve job history longer, or decrease it to optimize cluster resource usage.

## Metrics and Observability

The agent can be configured to send telemetry data, including both trace spans and metrics, using [OpenTelemetry](https://opentelemetry.io/).

OpenTelemetry is an extensible, open-source telemetry protocol and platform that enables the Scalr Agent to remain vendor-neutral while producing telemetry data for a wide range of platforms.

Enable telemetry for both the agent controller deployment and the agent worker by configuring an OpenTelemetry collector endpoint:

```yaml
otel:
  enabled: true
  endpoint: "otel-collector:4317"  # gRPC endpoint
  metricsEnabled: true
  tracesEnabled: false  # Optional: enable distributed tracing
```

See [all configuration options](#opentelemetry).

Learn more about [available metrics](https://docs.scalr.io/docs/metrics).

## Custom Resource Definitions

This chart bundles the **AgentTask CRD** (`atasks.scalr.io`) and installs or upgrades it automatically via Helm. The CRD defines the job template that the controller uses to create task pods, so no separate manual step is required in most environments.

**Verify installation:**

```shell
kubectl get crd atasks.scalr.io
```

## RBAC

By default the chart provisions:

- **ServiceAccount** used by the controller and task pods
- **Role/RoleBinding** with namespaced access to manage pods/jobs and related resources needed for task execution
- **ClusterRole/ClusterRoleBinding** granting read access to `AgentTask` resources (`atasks.scalr.io`)

Set `rbac.create=false` to bring your own ServiceAccount/Rules, or adjust permissions with `rbac.rules` and `rbac.clusterRules`.

## Troubleshooting and Support

### Debug Logging

If you encounter internal system errors or unexpected behavior, enable debug logs:

```shell
helm upgrade scalr-agent scalr-agent-helm/agent-job \
  --reuse-values \
  --set agent.debug="1"
```

Then collect logs ([see below](#collecting-logs)) and open a support request at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31).

### Collecting Logs

When inspecting logs, you'll need both the agent log (from the `scalr-agent-*` deployment pod) and the task log (from an `atask-*` job pod). Job pods are available for 60 seconds after completion. You may want to increase this time window using `task.job.ttlSecondsAfterFinished` to allow more time for log collection.

Use `kubectl logs` to retrieve logs from the `scalr-agent-*` and `atask-*` pods (if any):

```shell
kubectl logs -n <namespace> <task-pod-name> --all-containers
```

### Getting Support

For issues not covered above:

1. Enable [debug logging](#debug-logging)
2. [Collect logs](#collecting-logs) from the incident timeframe
3. Open a support ticket at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31)

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

### Agent

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.affinity | object | `{}` | Node affinity for the controller pod. |
| agent.cacheDir | string | `"/var/lib/scalr-agent/cache"` | Cache directory where the agent stores provider binaries, plugin cache, and metadata. This directory must be readable, writable, and executable. |
| agent.controller | object | `{"extraEnv":[],"extraEnvFrom":[],"securityContext":{}}` | Controller-specific configuration. |
| agent.controller.extraEnv | list | `[]` | Additional environment variables for the controller container only. |
| agent.controller.extraEnvFrom | list | `[]` | Additional environment variable sources for the controller container. |
| agent.controller.securityContext | object | `{}` | Default security context for agent controller container. |
| agent.dataDir | string | `"/var/lib/scalr-agent/data"` | Data directory where the agent stores workspace data (configuration versions, modules, and providers). This directory must be readable, writable, and executable. |
| agent.debug | string | `"0"` | Enable debug logging. |
| agent.extraEnv | object | `{}` | Additional environment variables for agent controller and worker containers. |
| agent.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/agent","tag":""}` | Agent image configuration (used by both controller and worker containers). |
| agent.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| agent.image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| agent.image.tag | string | `""` | Image tag. Defaults to the chart appVersion if not specified. |
| agent.logFormat | string | `"json"` | The log formatter. Options: plain, dev or json. Defaults to json. |
| agent.moduleCache.enabled | bool | `false` | Enable module caching. Disabled by default since the default configuration uses an ephemeral volume for the cache directory. |
| agent.moduleCache.sizeLimit | string | `"40Gi"` | Module cache soft limit. Must be tuned according to cache directory size. |
| agent.nodeSelector | object | `{}` | Node selector for assigning the controller pod to specific nodes. Example: `--set agent.nodeSelector."node-type"="agent-controller"` |
| agent.podAnnotations | object | `{}` | Controller-specific pod annotations (merged with global.podAnnotations, overrides duplicate keys). |
| agent.podDisruptionBudget | object | `{"enabled":true,"maxUnavailable":null,"minAvailable":1}` | PodDisruptionBudget configuration for controller high availability. Only applied when replicaCount > 1. Ensures minimum availability during voluntary disruptions. |
| agent.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for the controller. |
| agent.podDisruptionBudget.maxUnavailable | string | `nil` | Maximum number of controller pods that can be unavailable. Either minAvailable or maxUnavailable must be set, not both. |
| agent.podDisruptionBudget.minAvailable | int | `1` | Minimum number of controller pods that must be available. Either minAvailable or maxUnavailable must be set, not both. |
| agent.podLabels | object | `{}` | Controller-specific pod labels (merged with global.podLabels, overrides duplicate keys). |
| agent.podSecurityContext | object | `{}` | Controller-specific pod security context (merged with global.podAnnotations, overrides duplicate keys). |
| agent.providerCache.enabled | bool | `false` | Enable provider caching. Disabled by default since the default configuration uses an ephemeral volume for the cache directory. |
| agent.providerCache.sizeLimit | string | `"40Gi"` | Provider cache soft limit. Must be tuned according to cache directory size. |
| agent.replicaCount | int | `1` | Number of agent controller replicas. |
| agent.resources | object | `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource limits and requests for the agent controller container. |
| agent.terminationGracePeriodSeconds | int | `180` | Grace period in seconds before forcibly terminating the controller container. |
| agent.token | string | `""` | The agent pool token for authentication. |
| agent.tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| agent.tolerations | list | `[]` | Node tolerations for the controller pod. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set agent.tolerations[0].key=dedicated,agent.tolerations[0].operator=Equal,agent.tolerations[0].value=agent-controller,agent.tolerations[0].effect=NoSchedule` |
| agent.url | string | `""` | The Scalr URL to connect the agent to. |

### Global

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.imagePullSecrets | list | `[]` | Global image pull secrets for private registries. |
| global.imageRegistry | string | `""` | Global Docker registry to prepend to all image repositories. |
| global.podAnnotations | object | `{}` | Global pod annotations applied to all pods. |
| global.podLabels | object | `{}` | Global pod labels applied to all pods. |
| global.podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"},"supplementalGroups":[],"sysctls":[]}` | Security context applied to all pods. |
| global.podSecurityContext.fsGroup | int | `1000` | File system group for volume ownership. |
| global.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` | File system group change policy. |
| global.podSecurityContext.runAsGroup | int | `1000` | Group ID for all containers in the pod. |
| global.podSecurityContext.runAsNonRoot | bool | `true` | Run pod as non-root for security. |
| global.podSecurityContext.runAsUser | int | `1000` | User ID for all containers in the pod. |
| global.podSecurityContext.seLinuxOptions | object | `{}` | SELinux options for the pod. |
| global.podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for enhanced security. |
| global.podSecurityContext.supplementalGroups | list | `[]` | Supplemental groups for the containers. |
| global.podSecurityContext.sysctls | list | `[]` | Sysctls for the pod. |

### Global.Proxy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.proxy | object | `{"enabled":false,"httpProxy":"","httpsProxy":"","noProxy":""}` | HTTP proxy configuration for external connectivity. |
| global.proxy.enabled | bool | `false` | Enable injection of HTTP(S) proxy settings into all agent pods. |
| global.proxy.httpProxy | string | `""` | HTTP proxy URL applied to all agent containers (HTTP_PROXY). Example: "http://proxy.example.com:8080" |
| global.proxy.httpsProxy | string | `""` | HTTPS proxy URL applied to all agent containers (HTTPS_PROXY). Example: "http://proxy.example.com:8080" |
| global.proxy.noProxy | string | `""` | Comma-separated domains/IPs that bypass the proxy (NO_PROXY). Recommended to include Kubernetes internal domains to avoid routing cluster traffic through the proxy. Example: "localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" |

### Global.TLS

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.tls | object | `{"caBundle":"","caBundleSecret":{"key":"ca-bundle.crt","name":""}}` | TLS/SSL configuration for custom certificate authorities. |
| global.tls.caBundle | string | `""` | Inline CA bundle content as an alternative to caBundleSecret. Provide the complete CA certificate chain in PEM format. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. Example: caBundle: |   -----BEGIN CERTIFICATE-----   MIIDXTCCAkWgAwIBAgIJAKZ...   -----END CERTIFICATE-----   -----BEGIN CERTIFICATE-----   MIIEFzCCAv+gAwIBAgIUDiCT...   -----END CERTIFICATE----- |
| global.tls.caBundleSecret | object | `{"key":"ca-bundle.crt","name":""}` | Reference to an existing Kubernetes secret containing a CA bundle. This CA bundle is mounted to all agent pods and used for outbound TLS validation (e.g., Scalr API, VCS, registries). The secret must exist in the same namespace as the chart installation. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. |
| global.tls.caBundleSecret.key | string | `"ca-bundle.crt"` | Key within the secret that contains the CA bundle file. |
| global.tls.caBundleSecret.name | string | `""` | Name of the Kubernetes secret containing the CA bundle. Leave empty to use the inline caBundle or system certificates. |

### OpenTelemetry

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| otel.enabled | bool | `false` | Enable OpenTelemetry integration. |
| otel.endpoint | string | `"http://otel-collector:4317"` | OpenTelemetry collector endpoint. |
| otel.metricsEnabled | bool | `true` | Collect and export metrics. |
| otel.tracesEnabled | bool | `false` | Collect and export traces. |

### Persistence

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| persistence.cache | object | `{"emptyDir":{"sizeLimit":"1Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteMany","claimName":"","storage":"90Gi","storageClassName":"","subPath":""}}` | Cache directory storage configuration. Stores provider binaries, plugin cache, and downloaded tools to speed up runs. Mounted to both worker (for agent cache) and runner (for binary/plugin cache) containers. |
| persistence.cache.emptyDir | object | `{"sizeLimit":"1Gi"}` | EmptyDir volume configuration (used when enabled is false). |
| persistence.cache.emptyDir.sizeLimit | string | `"1Gi"` | Size limit for the emptyDir volume. |
| persistence.cache.enabled | bool | `false` | Enable persistent storage for cache directory. Highly recommended: Avoids re-downloading providers and binaries (saves 1-5 minutes per run). When false, providers and binaries are downloaded fresh for each task. When true, cache is shared across all task pods for significant performance improvement (may vary depending on NFS performace). |
| persistence.cache.persistentVolumeClaim | object | `{"accessMode":"ReadWriteMany","claimName":"","storage":"90Gi","storageClassName":"","subPath":""}` | PersistentVolumeClaim configuration (used when enabled is true). |
| persistence.cache.persistentVolumeClaim.accessMode | string | `"ReadWriteMany"` | Access mode for the PVC. Use ReadWriteMany to share cache across multiple task pods. Note: ReadWriteMany requires compatible storage class (e.g., NFS, EFS, Filestore). |
| persistence.cache.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC named `<release-name>-cache` is created. |
| persistence.cache.persistentVolumeClaim.storage | string | `"90Gi"` | Storage size for the PVC. |
| persistence.cache.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. |
| persistence.cache.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. Useful when sharing a single PVC across multiple installations. |
| persistence.data | object | `{"emptyDir":{"sizeLimit":"4Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteOnce","claimName":"","storage":"4Gi","storageClassName":"","subPath":""}}` | Data directory storage configuration. Stores workspace data including configuration versions, modules, and run metadata. This directory is mounted to the worker sidecar container. |
| persistence.data.emptyDir | object | `{"sizeLimit":"4Gi"}` | EmptyDir volume configuration (used when enabled is false). |
| persistence.data.emptyDir.sizeLimit | string | `"4Gi"` | Size limit for the emptyDir volume. |
| persistence.data.enabled | bool | `false` | Enable persistent storage for data directory. When false, uses emptyDir (ephemeral, recommended for most use cases as each run gets fresh workspace). When true, uses PVC (persistent across pod restarts, useful for debugging or sharing data between runs). |
| persistence.data.persistentVolumeClaim | object | `{"accessMode":"ReadWriteOnce","claimName":"","storage":"4Gi","storageClassName":"","subPath":""}` | PersistentVolumeClaim configuration (used when enabled is true). |
| persistence.data.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC. |
| persistence.data.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC named `<release-name>-data` is created. |
| persistence.data.persistentVolumeClaim.storage | string | `"4Gi"` | Storage size for the PVC. |
| persistence.data.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. |
| persistence.data.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |

### RBAC

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| rbac.clusterRules | list | `[{"apiGroups":["scalr.io"],"resources":["atasks"],"verbs":["get","list","watch"]}]` | Cluster-wide RBAC rules (applied via ClusterRole bound in the release namespace). |
| rbac.create | bool | `true` | Create the namespaced Role/RoleBinding and cluster-scope RoleBinding. |
| rbac.rules | list | `[{"apiGroups":[""],"resources":["pods"],"verbs":["get","list","watch","create","delete","deletecollection","patch","update"]},{"apiGroups":[""],"resources":["pods/log"],"verbs":["get"]},{"apiGroups":[""],"resources":["pods/exec"],"verbs":["get","create"]},{"apiGroups":[""],"resources":["pods/status"],"verbs":["get","patch","update"]},{"apiGroups":["apps"],"resources":["deployments"],"verbs":["get","list","watch"]},{"apiGroups":["batch"],"resources":["jobs"],"verbs":["get","list","watch","create","delete","deletecollection","patch","update"]},{"apiGroups":["batch"],"resources":["jobs/status"],"verbs":["get","patch","update"]}]` | Namespaced RBAC rules granted to the controller ServiceAccount. |

### Service account

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| serviceAccount.annotations | object | `{}` | Annotations for the service account. |
| serviceAccount.automountToken | bool | `true` | Whether to automount the service account token in pods. |
| serviceAccount.create | bool | `true` | Create a Kubernetes service account for the Scalr Agent. |
| serviceAccount.labels | object | `{}` | Additional labels for the service account. |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and create is true. |
| serviceAccount.tokenTTL | int | `3600` | Token expiration period in seconds. |

### Task

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| task.affinity | object | `{}` | Node affinity for task job pods. |
| task.allowMetadataService | bool | `false` | Disables a NetworkPolicy to the task containers that denies access to VM metadata service (169.254.169.254). |
| task.extraVolumes | list | `[]` | Additional volumes for task job pods. |
| task.job | object | `{"ttlSecondsAfterFinished":60}` | Job configuration for task execution. |
| task.job.ttlSecondsAfterFinished | int | `60` | Time in seconds after job completion before it is automatically deleted. |
| task.nodeSelector | object | `{}` | Node selector for assigning task job pods to specific nodes. Example: `--set task.nodeSelector."node-type"="agent-worker"` |
| task.podAnnotations | object | `{}` | Task-specific pod annotations (merged with global.podAnnotations, overrides duplicate keys). |
| task.podLabels | object | `{}` | Task-specific pod labels (merged with global.podLabels, overrides duplicate keys). |
| task.podSecurityContext | object | `{}` | Task-specific pod security context (merged with global.podAnnotations, overrides duplicate keys). |
| task.runner | object | `{"extraEnv":{},"extraVolumeMounts":[],"image":{"pullPolicy":"IfNotPresent","repository":"scalr/agent-runner","tag":""},"resources":{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seLinuxOptions":{}}}` | Runner container configuration (environment where Terraform/OpenTofu commands are executed). |
| task.runner.extraEnv | object | `{}` | Additional environment variables for the runner container. |
| task.runner.extraVolumeMounts | list | `[]` | Additional volume mounts for the runner container. |
| task.runner.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/agent-runner","tag":""}` | Runner container image settings. |
| task.runner.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| task.runner.image.repository | string | `"scalr/agent-runner"` | Docker repository for the runner image. |
| task.runner.image.tag | string | `""` | Image tag. Defaults to the chart appVersion if not specified. |
| task.runner.resources | object | `{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}}` | Resource limits and requests for the runner container. Note: For system agent controllers, this may be overridden by Scalr platform billing resource tier presets. |
| task.runner.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seLinuxOptions":{}}` | Security context for the runner container. The default declaration duplicates some critical options from podSecurityContext to keep them independent. |
| task.runner.securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation. |
| task.runner.securityContext.capabilities | object | `{"drop":["ALL"]}` | Container capabilities restrictions for security. |
| task.runner.securityContext.privileged | bool | `false` | Run container in privileged mode. |
| task.runner.securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem. |
| task.runner.securityContext.runAsNonRoot | bool | `true` | Run container as non-root user for security. |
| task.runner.securityContext.seLinuxOptions | object | `{}` | SELinux options for the container. |
| task.sidecars | list | `[]` | Additional sidecar containers for task job pods. |
| task.terminationGracePeriodSeconds | int | `360` | Grace period in seconds before forcibly terminating task job containers. |
| task.tolerations | list | `[]` | Node tolerations for task job pods. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set task.tolerations[0].key=dedicated,task.tolerations[0].operator=Equal,task.tolerations[0].value=agent-worker,task.tolerations[0].effect=NoSchedule` |
| task.worker | object | `{"extraEnv":{},"extraVolumeMounts":[],"image":{"pullPolicy":"","repository":"","tag":""},"resources":{"limits":{"cpu":"2000m","memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}},"securityContext":{}}` | Worker container configuration (sidecar that supervises task execution). |
| task.worker.extraEnv | object | `{}` | Additional environment variables for the worker container (merged with agent.extraEnv). |
| task.worker.extraVolumeMounts | list | `[]` | Additional volume mounts for the worker container. |
| task.worker.image | object | `{"pullPolicy":"","repository":"","tag":""}` | Worker container image settings (inherits from agent.image if not specified). |
| task.worker.image.pullPolicy | string | `""` | Image pull policy. Inherits from agent.image.pullPolicy if empty. |
| task.worker.image.repository | string | `""` | Docker repository for the worker image. Inherits from agent.image.repository if empty. |
| task.worker.image.tag | string | `""` | Image tag. Inherits from agent.image.tag if empty. |
| task.worker.resources | object | `{"limits":{"cpu":"2000m","memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}}` | Resource limits and requests for the worker container. |
| task.worker.securityContext | object | `{}` | Security context for the worker container (inherits from agent.securityContext if not specified). |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Override the full name of resources (takes precedence over nameOverride). |
| nameOverride | string | `""` | Override the chart name portion of resource names. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
