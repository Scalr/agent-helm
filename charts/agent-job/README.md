# agent-job

![Version: 0.5.67](https://img.shields.io/badge/Version-0.5.67-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.60.0](https://img.shields.io/badge/AppVersion-0.60.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
It uses a job-based model, where each Scalr Run is isolated
in its own Kubernetes Job.

See the [official documentation](https://docs.scalr.io/docs/agent-pools) for more information about Scalr Agents.

> [!WARNING]
> This chart is in Beta, and implementation details are subject to change. See [Planned Changes for Stable](#planned-changes-for-stable).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Planned Changes for Stable](#planned-changes-for-stable)
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

- **runner**: The environment where the run (Terraform/OpenTofu operations, OPA policies, shell hooks, etc.) is executed, based on the [scalr/runner](https://hub.docker.com/r/scalr/runner) image.
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

## Planned Changes for Stable

- The `task.runner.image` entrypoint will be mouned using [ImageVolume](https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/). This change would require the [ImageVolume](https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/) Kubernetes feature and will be implemented after Kubernetes 1.35.0 becomes available on major cloud vendors (GKE Regular channel). As a result, the stable version will require Kubernetes 1.35.0 with the [ImageVolume](https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/) feature enabled.
- Changes to [Custom Resource Definitions](#custom-resource-definitions) are possible before the stable release.

## Custom Runner Images

The chart uses the [scalr/runner](https://hub.docker.com/r/scalr/runner) image by default to provision run environments.

The image source code: https://github.com/Scalr/runner

You can override `task.runner.image.*` to use a custom runner image.

If you are using a custom runner image, it **must**:

- Include a user with UID/GID `1000`. By default, Scalr images include a `scalr` user with `1000:1000`.
- Include `/bin/sh` and `curl` tools.

Example override:

```shell
helm upgrade --install scalr-agent scalr-charts/agent-job \
  --set agent.token="<agent-token>" \
  --set task.runner.image.repository="registry.example.com/custom-runner" \
  --set task.runner.image.tag="v1.2.3"
```

## Performance Optimization

The following additional configurations are recommended to optimize Scalr Run startup time and overall chart performance.

### Optimize Run Startup Time

This chart uses Jobs to launch Scalr Runs, so fast Job launch is critical for low Scalr Run startup latency. Common bottlenecks that may introduce latency include slow image pull times on cold nodes. To optimize this, you can:

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

  The volume is mounted at `agent.dataDir`, which must be readable, writable, and executable.

- **Cache Volume**

  The cache volume stores software binaries, OpenTofu/Terraform providers and modules. This volume is mounted to both the worker (full access) and runner (read-only access to some directories) containers.

  The default configuration uses ephemeral `emptyDir` storage with a 1GB limit. By default, this is used only for the software binaries cache (since it is the default location for these tools), and the OpenTofu/Terraform provider cache is disabled by default.

  The volume is mounted at `agent.cacheDir`, which must be readable, writable, and executable.

### Cache Volume Persistence

It's recommended to enable persistent storage with `ReadWriteMany` access mode to share the cache across all task pods. This significantly improves performance by avoiding repeated downloads (saves 1-5 minutes per task).

Benefits of persistent cache:

- Faster task execution (no provider/modules/binaries re-downloads)
- Reduced network bandwidth usage
- Better fault tolerance during module/provider registry outages

When enabling a persistent cache directory, it is recommended to also enable provider cache (`providerCache.enabled=true`) and module cache (`moduleCache.enabled=true`). Otherwise, only software binaries (Terraform/OpenTofu/OPA/Infracost/etc.) will be cached.

Learn more about [Provider Cache](https://docs.scalr.io/docs/providers-cache) and [Module Cache](https://docs.scalr.io/docs/modules-cache).

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
Initializing modules...
Initialized 8 modules in 4.12s (8 used from cache)
Initializing plugins...
Initialized 20 plugins in 6.09s (20 used from cache)
```

See detailed guides:

- [GKE Filestore](docs/cache-persistence-filestore.md)

### Data Volume Persistence

The default configuration uses ephemeral `emptyDir` storage. Since the workspace volume does not need to be shared or persisted between runs, we recommend using an ephemeral volume so that it is bound to the lifetime of the run and automatically destroyed when the Job is deleted.

Optionally, you can configure a PVC using `persistence.data.enabled` and `persistence.data.persistentVolumeClaim` options, similar to the [cache volume configuration](#cache-volume-persistence).

## Security

### Multi-tenant Isolation

This chart provides strong isolation for multi-tenant environments by deploying each run in a separate container with restricted filesystem access.

The agent worker process and the run environment process (where OpenTofu/Terraform is executed) are separated into different containers and communicate via a minimalistic IPC mechanism.
The run environment process has no filesystem access except to its own data directory, ensuring runs cannot interfere with each other or access shared system resources.

### Runner Security Context

Runner pods inherit their Linux user, group, seccomp, and capability settings from `task.runner.securityContext`. The defaults run the container as the non-root UID/GID `1000`, drop all Linux capabilities, and enforce a read-only root filesystem.

The default is strict and compatible with Terraform/OpenTofu workloads, and it’s generally not recommended to change it. However, it can be useful to disable `readOnlyRootFilesystem` and switch the user to root if you need to install packages via package managers like `apt-get` or `dnf` from Workspace hooks.

### Access to VM Metadata Service

The chart includes an `allowMetadataService` configuration option to control access to the VM metadata service at 169.254.169.254, which is common for AWS, GCP, and Azure environments.

When disabled, the chart creates a Kubernetes NetworkPolicy for task pods that denies egress traffic to 169.254.169.254/32, blocking access to the VM metadata service. All other outbound traffic is allowed.

Access is disabled by default. To enabled VM metadata service access, use:

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

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.affinity | object | `{}` | Node affinity for the controller pod. @section -- Agent |
| agent.cacheDir | string | `"/var/lib/scalr-agent/cache"` | Cache directory where the agent stores provider binaries, plugin cache, and metadata. This directory must be readable, writable, and executable. @section -- Agent |
| agent.controller | object | `{"extraEnv":[],"extraEnvFrom":[],"securityContext":{}}` | Controller-specific configuration. @section -- Agent |
| agent.controller.extraEnv | list | `[]` | Additional environment variables for the controller container only. @section -- Agent |
| agent.controller.extraEnvFrom | list | `[]` | Additional environment variable sources for the controller container. @section -- Agent |
| agent.controller.securityContext | object | `{}` | Default security context for agent controller container. @section -- Agent |
| agent.dataDir | string | `"/var/lib/scalr-agent/data"` | Data directory where the agent stores workspace data (configuration versions, modules, and providers). This directory must be readable, writable, and executable. @section -- Agent |
| agent.debug | string | `"0"` | Enable debug logging. @section -- Agent |
| agent.extraEnv | object | `{}` | Additional environment variables for agent controller and worker containers. @section -- Agent |
| agent.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/agent","tag":""}` | Agent image configuration (used by both controller and worker containers). @section -- Agent |
| agent.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. @section -- Agent |
| agent.image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. @section -- Agent |
| agent.image.tag | string | `""` | Image tag. Defaults to the chart appVersion if not specified. @section -- Agent |
| agent.logFormat | string | `"json"` | The log formatter. Options: plain, dev or json. Defaults to json. @section -- Agent |
| agent.moduleCache.enabled | bool | `false` | Enable module caching. Disabled by default since the default configuration uses an ephemeral volume for the cache directory. @section -- Agent |
| agent.moduleCache.sizeLimit | string | `"40Gi"` | Module cache soft limit. Must be tuned according to cache directory size. @section -- Agent |
| agent.nodeSelector | object | `{}` | Node selector for assigning the controller pod to specific nodes. Example: `--set agent.nodeSelector."node-type"="agent-controller"` @section -- Agent |
| agent.podAnnotations | object | `{}` | Controller-specific pod annotations (merged with global.podAnnotations, overrides duplicate keys). @section -- Agent |
| agent.podDisruptionBudget | object | `{"enabled":true,"maxUnavailable":null,"minAvailable":1}` | PodDisruptionBudget configuration for controller high availability. Only applied when replicaCount > 1. Ensures minimum availability during voluntary disruptions. @section -- Agent |
| agent.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for the controller. @section -- Agent |
| agent.podDisruptionBudget.maxUnavailable | string | `nil` | Maximum number of controller pods that can be unavailable. Either minAvailable or maxUnavailable must be set, not both. @section -- Agent |
| agent.podDisruptionBudget.minAvailable | int | `1` | Minimum number of controller pods that must be available. Either minAvailable or maxUnavailable must be set, not both. @section -- Agent |
| agent.podLabels | object | `{}` | Controller-specific pod labels (merged with global.podLabels, overrides duplicate keys). @section -- Agent |
| agent.podSecurityContext | object | `{}` | Controller-specific pod security context (merged with global.podAnnotations, overrides duplicate keys). @section -- Agent |
| agent.providerCache.enabled | bool | `false` | Enable provider caching. Disabled by default since the default configuration uses an ephemeral volume for the cache directory. @section -- Agent |
| agent.providerCache.sizeLimit | string | `"40Gi"` | Provider cache soft limit. Must be tuned according to cache directory size. @section -- Agent |
| agent.replicaCount | int | `1` | Number of agent controller replicas. @section -- Agent |
| agent.resources | object | `{"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits for the agent controller container. @section -- Agent |
| agent.terminationGracePeriodSeconds | int | `180` | Grace period in seconds before forcibly terminating the controller container. @section -- Agent |
| agent.token | string | `""` | The agent pool token for authentication. @section -- Agent |
| agent.tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. @section -- Agent |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. @section -- Agent |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. @section -- Agent |
| agent.tolerations | list | `[]` | Node tolerations for the controller pod. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set agent.tolerations[0].key=dedicated,agent.tolerations[0].operator=Equal,agent.tolerations[0].value=agent-controller,agent.tolerations[0].effect=NoSchedule` @section -- Agent |
| agent.topologySpreadConstraints | object | `{}` | Topology spread constraints for the controller pod. @section -- Agent |
| agent.url | string | `""` | The Scalr URL to connect the agent to. @section -- Agent |
| fullnameOverride | string | `""` | Override the full name of resources (takes precedence over nameOverride). |
| global.imageNamespace | string | "" | Global image namespace/organization override for all images. Replaces the namespace in repositories (e.g., "myorg" changes "scalr/runner" to "myorg/runner"). Combined: registry="gcr.io/project" + namespace="myorg" + repo="scalr/runner" → "gcr.io/project/myorg/runner:tag" Leave empty to preserve original namespace. @section -- Global |
| global.imagePullSecrets | list | `[]` | Global image pull secrets for private registries. @section -- Global |
| global.imageRegistry | string | "" | Global Docker registry override for all images. Prepended to image repositories. Example: "us-central1-docker.pkg.dev/myorg/images" Leave empty to use default Docker Hub. @section -- Global |
| global.podAnnotations | object | `{}` | Global pod annotations applied to all pods. @section -- Global |
| global.podLabels | object | `{}` | Global pod labels applied to all pods. @section -- Global |
| global.podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"},"supplementalGroups":[],"sysctls":[]}` | Security context applied to all pods. @section -- Global |
| global.podSecurityContext.fsGroup | int | `1000` | File system group for volume ownership. @section -- Global |
| global.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` | File system group change policy. @section -- Global |
| global.podSecurityContext.runAsGroup | int | `1000` | Group ID for all containers in the pod. @section -- Global |
| global.podSecurityContext.runAsNonRoot | bool | `true` | Run pod as non-root for security. @section -- Global |
| global.podSecurityContext.runAsUser | int | `1000` | User ID for all containers in the pod. @section -- Global |
| global.podSecurityContext.seLinuxOptions | object | `{}` | SELinux options for the pod. @section -- Global |
| global.podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for enhanced security. @section -- Global |
| global.podSecurityContext.supplementalGroups | list | `[]` | Supplemental groups for the containers. @section -- Global |
| global.podSecurityContext.sysctls | list | `[]` | Sysctls for the pod. @section -- Global |
| global.proxy | object | `{"enabled":false,"httpProxy":"","httpsProxy":"","noProxy":""}` | HTTP proxy configuration for external connectivity. @section -- Global.Proxy |
| global.proxy.enabled | bool | `false` | Enable injection of HTTP(S) proxy settings into all agent pods. @section -- Global.Proxy |
| global.proxy.httpProxy | string | `""` | HTTP proxy URL applied to all agent containers (HTTP_PROXY). Example: "http://proxy.example.com:8080" @section -- Global.Proxy |
| global.proxy.httpsProxy | string | `""` | HTTPS proxy URL applied to all agent containers (HTTPS_PROXY). Example: "http://proxy.example.com:8080" @section -- Global.Proxy |
| global.proxy.noProxy | string | `""` | Comma-separated domains/IPs that bypass the proxy (NO_PROXY). Recommended to include Kubernetes internal domains to avoid routing cluster traffic through the proxy. Example: "localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16" @section -- Global.Proxy |
| global.tls | object | `{"caBundle":"","caBundleSecret":{"key":"ca-bundle.crt","name":""}}` | TLS/SSL configuration for custom certificate authorities. @section -- Global.TLS |
| global.tls.caBundle | string | `""` | Inline CA bundle content as an alternative to caBundleSecret. Provide the complete CA certificate chain in PEM format. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. Example: caBundle: |   -----BEGIN CERTIFICATE-----   MIIDXTCCAkWgAwIBAgIJAKZ...   -----END CERTIFICATE-----   -----BEGIN CERTIFICATE-----   MIIEFzCCAv+gAwIBAgIUDiCT...   -----END CERTIFICATE----- @section -- Global.TLS |
| global.tls.caBundleSecret | object | `{"key":"ca-bundle.crt","name":""}` | Reference to an existing Kubernetes secret containing a CA bundle. This CA bundle is mounted to all agent pods and used for outbound TLS validation (e.g., Scalr API, VCS, registries). The secret must exist in the same namespace as the chart installation. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. @section -- Global.TLS |
| global.tls.caBundleSecret.key | string | `"ca-bundle.crt"` | Key within the secret that contains the CA bundle file. @section -- Global.TLS |
| global.tls.caBundleSecret.name | string | `""` | Name of the Kubernetes secret containing the CA bundle. Leave empty to use the inline caBundle or system certificates. @section -- Global.TLS |
| nameOverride | string | `""` | Override the chart name portion of resource names. |
| otel.enabled | bool | `false` | Enable OpenTelemetry integration. @section -- OpenTelemetry |
| otel.endpoint | string | `"http://otel-collector:4317"` | OpenTelemetry collector endpoint. @section -- OpenTelemetry |
| otel.metricsEnabled | bool | `true` | Collect and export metrics. @section -- OpenTelemetry |
| otel.tracesEnabled | bool | `false` | Collect and export traces. @section -- OpenTelemetry |
| persistence.cache | object | `{"emptyDir":{"sizeLimit":"1Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteMany","claimName":"","storage":"90Gi","storageClassName":"","subPath":""}}` | Cache directory storage configuration. Stores OpenTofu/Terraform providers, modules and binaries. Mounted to both worker (for agent cache) and runner (for binary/plugin cache) containers. @section -- Persistence |
| persistence.cache.emptyDir | object | `{"sizeLimit":"1Gi"}` | EmptyDir volume configuration (used when enabled is false). @section -- Persistence |
| persistence.cache.emptyDir.sizeLimit | string | `"1Gi"` | Size limit for the emptyDir volume. @section -- Persistence |
| persistence.cache.enabled | bool | `false` | Enable persistent storage for cache directory. Highly recommended: Avoids re-downloading providers and binaries (saves 1-5 minutes per run). When false, providers and binaries are downloaded fresh for each task. When true, cache is shared across all task pods for significant performance improvement (may vary depending on RWM volume performace). @section -- Persistence |
| persistence.cache.persistentVolumeClaim | object | `{"accessMode":"ReadWriteMany","claimName":"","storage":"90Gi","storageClassName":"","subPath":""}` | PersistentVolumeClaim configuration (used when enabled is true). @section -- Persistence |
| persistence.cache.persistentVolumeClaim.accessMode | string | `"ReadWriteMany"` | Access mode for the PVC. Use ReadWriteMany to share cache across multiple task pods. Note: ReadWriteMany requires compatible storage class (e.g., NFS, EFS, Filestore). @section -- Persistence |
| persistence.cache.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC named `<release-name>-cache` is created. @section -- Persistence |
| persistence.cache.persistentVolumeClaim.storage | string | `"90Gi"` | Storage size for the PVC. @section -- Persistence |
| persistence.cache.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. @section -- Persistence |
| persistence.cache.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. Useful when sharing a single PVC across multiple installations. @section -- Persistence |
| persistence.data | object | `{"emptyDir":{"sizeLimit":"4Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteOnce","claimName":"","storage":"4Gi","storageClassName":"","subPath":""}}` | Data directory storage configuration. Stores workspace data including configuration versions, modules, and run metadata. This directory is mounted to the worker sidecar container. @section -- Persistence |
| persistence.data.emptyDir | object | `{"sizeLimit":"4Gi"}` | EmptyDir volume configuration (used when enabled is false). @section -- Persistence |
| persistence.data.emptyDir.sizeLimit | string | `"4Gi"` | Size limit for the emptyDir volume. @section -- Persistence |
| persistence.data.enabled | bool | `false` | Enable persistent storage for data directory. When false, uses emptyDir (ephemeral, recommended for most use cases as each run gets fresh workspace). When true, uses PVC (persistent across pod restarts, useful for debugging or sharing data between runs). @section -- Persistence |
| persistence.data.persistentVolumeClaim | object | `{"accessMode":"ReadWriteOnce","claimName":"","storage":"4Gi","storageClassName":"","subPath":""}` | PersistentVolumeClaim configuration (used when enabled is true). @section -- Persistence |
| persistence.data.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC. @section -- Persistence |
| persistence.data.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC named `<release-name>-data` is created. @section -- Persistence |
| persistence.data.persistentVolumeClaim.storage | string | `"4Gi"` | Storage size for the PVC. @section -- Persistence |
| persistence.data.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. @section -- Persistence |
| persistence.data.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. @section -- Persistence |
| rbac.clusterRules | list | `[{"apiGroups":["scalr.io"],"resources":["atasks"],"verbs":["get","list","watch"]}]` | Cluster-wide RBAC rules (applied via ClusterRole bound in the release namespace). @section -- RBAC |
| rbac.create | bool | `true` | Create the namespaced Role/RoleBinding and cluster-scope RoleBinding. @section -- RBAC |
| rbac.rules | list | `[{"apiGroups":[""],"resources":["pods"],"verbs":["get","list","watch","create","delete","deletecollection","patch","update"]},{"apiGroups":[""],"resources":["pods/log"],"verbs":["get"]},{"apiGroups":[""],"resources":["pods/exec"],"verbs":["get","create"]},{"apiGroups":[""],"resources":["pods/status"],"verbs":["get","patch","update"]},{"apiGroups":["apps"],"resources":["deployments"],"verbs":["get","list","watch"]},{"apiGroups":["batch"],"resources":["jobs"],"verbs":["get","list","watch","create","delete","deletecollection","patch","update"]},{"apiGroups":["batch"],"resources":["jobs/status"],"verbs":["get","patch","update"]}]` | Namespaced RBAC rules granted to the controller ServiceAccount. @section -- RBAC |
| serviceAccount.annotations | object | `{}` | Annotations for the service account. @section -- Service account |
| serviceAccount.automountToken | bool | `true` | Whether to automount the service account token in pods. @section -- Service account |
| serviceAccount.create | bool | `true` | Create a Kubernetes service account for the Scalr Agent. @section -- Service account |
| serviceAccount.labels | object | `{}` | Additional labels for the service account. @section -- Service account |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and create is true. @section -- Service account |
| serviceAccount.tokenTTL | int | `3600` | Token expiration period in seconds. @section -- Service account |
| task.affinity | object | `{}` | Node affinity for task job pods. @section -- Task |
| task.allowMetadataService | bool | `false` | Disables a NetworkPolicy to the task containers that denies access to VM metadata service (169.254.169.254). @section -- Task |
| task.extraVolumes | list | `[]` | Additional volumes for task job pods. @section -- Task |
| task.job | object | `{"ttlSecondsAfterFinished":60}` | Job configuration for task execution. @section -- Task |
| task.job.ttlSecondsAfterFinished | int | `60` | Time in seconds after job completion before it is automatically deleted. @section -- Task |
| task.nodeSelector | object | `{}` | Node selector for assigning task job pods to specific nodes. Example: `--set task.nodeSelector."node-type"="agent-worker"` @section -- Task |
| task.podAnnotations | object | `{}` | Task-specific pod annotations (merged with global.podAnnotations, overrides duplicate keys). @section -- Task |
| task.podLabels | object | `{}` | Task-specific pod labels (merged with global.podLabels, overrides duplicate keys). @section -- Task |
| task.podSecurityContext | object | `{}` | Task-specific pod security context (merged with global.podAnnotations, overrides duplicate keys). @section -- Task |
| task.runner | object | `{"extraEnv":{},"extraVolumeMounts":[],"image":{"pullPolicy":"IfNotPresent","repository":"scalr/runner","tag":"0.2.0"},"resources":{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seLinuxOptions":{}}}` | Runner container configuration (environment where Terraform/OpenTofu commands are executed). @section -- Task |
| task.runner.extraEnv | object | `{}` | Additional environment variables for the runner container. @section -- Task |
| task.runner.extraVolumeMounts | list | `[]` | Additional volume mounts for the runner container. @section -- Task |
| task.runner.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/runner","tag":"0.2.0"}` | Runner container image settings. Default image: https://hub.docker.com/r/scalr/runner, repository: https://github.com/Scalr/runner Note: For Scalr-managed agents, this may be overridden by Scalr account image settings. @section -- Task |
| task.runner.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. @section -- Task |
| task.runner.image.repository | string | `"scalr/runner"` | Default repository for the runner image. @section -- Task |
| task.runner.image.tag | string | `"0.2.0"` | Default tag for the runner image. @section -- Task |
| task.runner.resources | object | `{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}}` | Resource requests and limits for the runner container. Note: For scalr-managed agents, this may be overridden by Scalr platform billing resource tier presets. @section -- Task |
| task.runner.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seLinuxOptions":{}}` | Security context for the runner container. The default declaration duplicates some critical options from podSecurityContext to keep them independent. @section -- Task |
| task.runner.securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation. @section -- Task |
| task.runner.securityContext.capabilities | object | `{"drop":["ALL"]}` | Container capabilities restrictions for security. @section -- Task |
| task.runner.securityContext.privileged | bool | `false` | Run container in privileged mode. @section -- Task |
| task.runner.securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem. @section -- Task |
| task.runner.securityContext.runAsNonRoot | bool | `true` | Run container as non-root user for security. @section -- Task |
| task.runner.securityContext.seLinuxOptions | object | `{}` | SELinux options for the container. @section -- Task |
| task.sidecars | list | `[]` | Additional sidecar containers for task job pods. @section -- Task |
| task.terminationGracePeriodSeconds | int | `360` | Grace period in seconds before forcibly terminating task job containers. @section -- Task |
| task.tolerations | list | `[]` | Node tolerations for task job pods. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set task.tolerations[0].key=dedicated,task.tolerations[0].operator=Equal,task.tolerations[0].value=agent-worker,task.tolerations[0].effect=NoSchedule` @section -- Task |
| task.worker | object | `{"extraEnv":{},"extraVolumeMounts":[],"resources":{"limits":{"memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}},"securityContext":{}}` | Worker container configuration (sidecar that supervises task execution). @section -- Task |
| task.worker.extraEnv | object | `{}` | Additional environment variables for the worker container (merged with agent.extraEnv). @section -- Task |
| task.worker.extraVolumeMounts | list | `[]` | Additional volume mounts for the worker container. @section -- Task |
| task.worker.resources | object | `{"limits":{"memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}}` | Resource requests and limits for the worker container. @section -- Task |
| task.worker.securityContext | object | `{}` | Security context for the worker container. @section -- Task |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.11.0](https://github.com/norwoodj/helm-docs/releases/v1.11.0)
