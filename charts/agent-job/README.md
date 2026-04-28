# agent-job

![Version: 0.5.75](https://img.shields.io/badge/Version-0.5.75-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.65.1](https://img.shields.io/badge/AppVersion-0.65.1-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
It uses a job-based model, where each Scalr Run is isolated
in its own Kubernetes Job.

See the [official documentation](https://docs.scalr.io/docs/agent-pools) for more information about Scalr Agents.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Versioning Policy](#versioning-policy)
- [Agent Task Naming](#agent-task-naming)
- [Custom Runner Images](#custom-runner-images)
- [High Availability](#high-availability)
- [Performance Optimization](#performance-optimization)
- [Termination](#termination)
- [HTTP Proxy](#http-proxy)
- [Custom Certificate Authorities](#custom-certificate-authorities)
- [Mutual TLS (mTLS)](#mutual-tls-mtls)
- [Volumes](#volumes)
- [Security](#security)
- [Network Requirements](#network-requirements)
- [Job History Management](#job-history-management)
- [Metrics and Observability](#metrics-and-observability)
- [RBAC](#rbac)
- [Custom Resource Definitions](#custom-resource-definitions)
- [Planned Changes](#planned-changes)
- [Troubleshooting and Support](#troubleshooting-and-support)

## Prerequisites

- Kubernetes 1.35+
- Helm 3.0+
- Optional: [ReadWriteMany](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) volume for [Cache Volume Persistence](#cache-volume-persistence)

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

## Versioning Policy

This chart deploys the [Scalr Agent](https://docs.scalr.io/docs/agent-pools) using the [`scalr/agent`](https://hub.docker.com/r/scalr/agent) image. The agent supports multiple runtimes beyond Kubernetes and is versioned independently from this chart.

Each new agent release triggers a new chart release with an updated `appVersion`. The two changelogs cover different scopes:

- [Scalr Agent changelog](https://docs.scalr.io/docs/changelog) — application-level changes and new Scalr platform functionality
- [CHANGELOG.md](CHANGELOG.md) — chart-level changes: Kubernetes resources, values, and defaults

> [!WARNING]
> Overriding `appVersion` to a version other than the one shipped with the chart is not recommended. Releases are tested and coordinated with a specific agent version, and mismatched combinations may include breaking changes between application and infrastructure code.

## Agent Task Naming

When the agent controller spawns a Kubernetes Job for a Scalr Run, the Job is named using the pattern:

```shell
<basename>-<run-id>-<stage>
```

Where:

- **basename**: Configurable prefix derived from the chart's fullname (defaults to `scalr-agent`). Override with `task.job.basename`.
- **run-id**: Unique identifier assigned by the Scalr platform (e.g., `run-v0p500fu3s9ban8s8`).
- **stage**: The execution stage (e.g., `plan`, `apply`, `policy`, etc).

If the final Job name after concatenation exceeds 63 characters (the Kubernetes Job name limit), the basename prefix will be omitted.

Examples:

| Release Name | `task.job.basename` | Resulting Job Name |
|--------------|---------------------|-------------------|
| scalr-agent | (empty) | scalr-agent-run-abcd1234-plan |
| prod-agent | (empty) | prod-agent-run-abcd1234-apply |
| scalr-agent | my-jobs | my-jobs-run-abcd1234-policy |
| scalr-agent | my-extra-long-....-basename | run-abcd1234-policy |

To customize the basename:

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --set task.job.basename="custom-prefix"
```

## Custom Runner Images

The chart uses the [scalr/runner](https://hub.docker.com/r/scalr/runner) image by default to provision run environments.

The image source code: https://github.com/Scalr/runner

You can override `task.runner.image.*` to use a custom runner image.

If you are using a custom runner image, it **must**:

- Include a user with UID/GID `1000`. By default, Scalr images include a `scalr` user with `1000:1000`.
- Include `/bin/sh`.
- Include glibc 2.32 or later.

For OpenTofu/Terraform operations, it is recommended to include basic tools such as `git`, `ssh`, and `curl`, which may be used by the OpenTofu/Terraform CLI when downloading modules from remote Git servers.

Example override:

```shell
helm upgrade --install scalr-agent scalr-charts/agent-job \
  --set agent.token="<agent-token>" \
  --set task.runner.image.repository="registry.example.com/custom-runner" \
  --set task.runner.image.tag="v1.2.3"
```

## High Availability

This section describes strategies for hardening the deployment for high availability.

### Multiple Controller Replicas

By default the chart runs a single controller replica (`agent.replicaCount: 1`). Increasing the replica count distributes the run scheduling load and ensures the agent pool remains available during voluntary disruptions such as node upgrades or pod restarts.

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --set agent.replicaCount=2
```

When `agent.replicaCount > 1`, the chart automatically creates a `PodDisruptionBudget` (controlled by `agent.podDisruptionBudget`) that keeps at least one controller available during voluntary disruptions.

### Separate Controllers and Task Pods

It is recommended to run agent controller pods and task job pods on separate node pools. This prevents resource-intensive run workloads from competing with controllers for CPU and memory, which could delay run scheduling or cause controller eviction. It also allows upgrading or resizing the task node pool without interrupting controllers which is responsible for scheduling incoming runs.

Use `agent.nodeSelector` and `task.nodeSelector` to pin each to its own node pool:

```yaml
agent:
  nodeSelector:
    role: main
task:
  nodeSelector:
    role: scalr-agent-runs
```

With task pods on a dedicated node pool, you can also scale that pool down to zero during periods of inactivity and let the cluster autoscaler provision nodes on demand when runs arrive.

### Deploy Multiple Installations Within a Scalr Agent Pool

You can connect multiple `agent-job` Helm releases to the same Scalr agent pool, each targeting a different node pool or availability zone.

This allows the pool to scale horizontally across infrastructure boundaries without a single point of failure.

## Performance Optimization

The following additional configurations are recommended to optimize Scalr Run startup time and overall chart performance.

### Optimize Run Startup Time

This chart uses Jobs to launch Scalr Runs, so fast Job launch is critical for low Scalr Run startup latency. Common bottlenecks that may introduce latency include slow image pull times on cold nodes. To optimize this, you can:

- Use image copies in an OCI-compatible registry mirror (Google Container Registry, Amazon Elastic Container Registry, Azure Container Registry, and similar) located in the same region as your node pool. This enables faster pull times and reduces the risk of hitting Docker Hub rate limits.
- Enable [Image Streaming](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/image-streaming) (GKE only) to improve Job launch time.
- [Build](#custom-runner-images) and use a smaller runner image tailored to your requirements. The default `task.runner.image` includes a wide variety of tools, including cloud CLIs (GCE, AWS, Azure), scripting language interpreters, and more, which makes it a relatively large image and may negatively impact image pull times.
- Use a [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/) to preemptively cache all images used in this chart (`scalr/agent`, `scalr/runner`) on clusters with a fixed number of nodes.
- Use [buffer pods](docs/buffer-pods.md) on clusters with autoscaling enabled - buffer pods keep nodes warm to eliminate cluster autoscaler cold-start delays and pre-cache images at the same time.

You can configure [OTLP monitoring](#metrics-and-observability) and use the [scalr_agent.core.kubernetes_job_startup_latency_seconds](https://docs.scalr.io/docs/metrics#scalr_agentcorekubernetes_job_startup_latency_seconds) metric to track run startup time. You may observe spikes during node scaling, but good average values range from 3 to 5 seconds.

### Use Persistent Cache

A major performance bottleneck in any IaC pipeline is the time spent re-downloading binaries, providers, and modules during each run. To optimize this, we recommend enabling [Cache Directory Persistence](#cache-volume-persistence).

## Termination

Both the controller (long-lived service) and worker (short-lived, one per run) agents maintain a registration and liveness indicator within the Scalr Agent Pool throughout their entire runtime. When an agent stops, it deregisters itself from the Scalr platform as part of its shutdown procedure after receiving a SIGTERM signal.

Because agents may be managing an active run stage, it is important to allow them to terminate gracefully rather than being abruptly stopped with SIGKILL, which would leave no opportunity to perform a graceful shutdown of the underlying OpenTofu/Terraform workload or push a status update to the Scalr platform, and can lead to undefined behavior — ranging from degraded performance and Scalr Run processing delays to agent capacity issues, stuck runs, or even OpenTofu/Terraform state loss.

### Pod Eviction

To reduce the risk of Pod eviction for active Scalr agents, the default configuration applies the following annotations for common autoscalers such as Cluster Autoscaler, GKE Autopilot, and Karpenter:

```yaml
cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
karpenter.sh/do-not-evict: "true"
karpenter.sh/do-not-disrupt: "true"
autopilot.gke.io/priority: "high"
```

Monitor node resource pressure and eviction events to ensure stable operation.

### Scalr Run Out-of-Memory Termination

The runner container executes Scalr Run workloads and processes end-user IaC configuration and code, resulting in highly variable memory utilization and an elevated risk of exceeding the memory limit and triggering an OOM kill.

When a runner container exceeds its memory limit, Kubernetes sends SIGKILL directly to the process with no opportunity to clean up. For OpenTofu/Terraform workloads, this can result in state loss or corruption if the process is killed before it can push state.

To address this, the Scalr agent monitors memory usage inside the runner container and sends SIGTERM before the hard limit is reached, giving OpenTofu/Terraform time to push state and exit cleanly.

The agent uses a two-tier memory limit model:

- **Warn threshold** (`task.runner.memoryWarnPercent`, default 90% of soft limit) — when exceeded, a warning is logged to the run console after the run completes, indicating the workload is approaching its memory limit.
- **Soft limit** (`task.runner.memorySoftLimitPercent`, default 80% of hard limit) — when exceeded, the agent sends SIGTERM to the workload. OpenTofu/Terraform handles SIGTERM gracefully by pushing state before exiting. The headroom between the soft and hard limits gives the process time to complete the state push.
- **Hard limit** (`task.runner.resources.limits.memory`) — enforced by Kubernetes. If the process does not exit after SIGTERM and memory continues to grow, the container is killed with SIGKILL.

The gap between the soft limit and the hard limit is the memory budget available for the state push after SIGTERM is sent. OOM termination is not precise and may fail during sudden memory spikes, so sufficient headroom is important to handle the race between graceful termination and the Kubernetes hard kill.

- Setting `task.runner.memorySoftLimitPercent` too high (e.g., 95%) leaves little headroom — if memory continues to grow after SIGTERM, the process may be killed before the state push completes.
- Setting `task.runner.memorySoftLimitPercent` too low (e.g., 50%) may cause premature termination of workloads that would otherwise have completed successfully.

The default of 80% is a reasonable balance for most workloads. If you are experiencing state loss during OOM events, consider lowering this value or increasing `task.runner.resources.limits.memory`.

> [!NOTE]
> `task.runner.memorySoftLimitPercent` and `task.runner.memoryWarnPercent` have no effect when `task.runner.resources.limits.memory` is not set.

## HTTP Proxy

Configure HTTP proxy settings for external connectivity:

```yaml
global:
  proxy:
    enabled: true
    httpProxy: "http://proxy.example.com:8080"
    httpsProxy: "http://proxy.example.com:8080"
    noProxy: "localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,169.254.169.254"
```

The `noProxy` setting should include Kubernetes internal domains to avoid routing cluster traffic through the proxy.

**NetworkPolicy and proxy port**

When `task.allowMetadataService` is false (the default), the chart creates a NetworkPolicy for task pods that allows DNS (port 53) and egress to the internet while blocking the VM metadata service. That policy does not allow egress to arbitrary ports (such as a proxy). If you use an HTTP proxy (e.g. on port 3128 or 8080), task pods must be allowed to reach it.

Create a **separate** NetworkPolicy that allows egress from task pods to the proxy (by port and, if you want, by pod or namespace selector). Do not edit the policy created by the chart. Chart upgrades or redeploys can overwrite that policy; keeping proxy egress in your own policy keeps it under your control and avoids it being reverted.

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

## Mutual TLS (mTLS)

> [!IMPORTANT]
> mTLS is an upcoming Enterprise feature.
> See the [Scalr mTLS documentation](https://docs.scalr.io/docs/mtls) for details.

Mutual TLS (mTLS) adds transport-layer identity verification on top of the existing JWT authentication. With standard TLS only the server is verified; mTLS requires the agent to also present a client certificate during the TLS handshake, proving to Scalr that the request originates from a legitimate agent host. This means a stolen JWT alone is no longer sufficient — the attacker also needs the pool private key, which stays on operator-managed infrastructure. This is separate from the [Custom Certificate Authorities](#custom-certificate-authorities) configuration, which controls CA trust for outbound connections.

The bootstrap certificate and private key are mounted read-only at `/etc/scalr-agent/ssl/` and mapped to `SCALR_AGENT_TLS_CERT_FILE` and `SCALR_AGENT_TLS_KEY_FILE`. The configuration applies to the controller and worker containers; the runner container is not affected.

To obtain an mTLS certificate, generate an EC P-256 private key and CSR (Certificate Signing Request):

```shell
openssl ecparam -genkey -name prime256v1 -noout -out scalr-agent.key
openssl req -new -key scalr-agent.key -out scalr-agent.csr -subj "/CN=agent-pool"
```

Then submit the CSR via the Agent Pool UI when registering a new agent, or via the **Certificates** tab on the Agent Pool page. Scalr signs the CSR and returns a certificate. The private key never leaves the operator host.

Once you have both the private key and the signed certificate, configure the chart using one of the following options:

**Option 1: Reference existing secret**

Works with both `kubernetes.io/tls` and `Opaque` secret types. A `kubernetes.io/tls` secret uses `tls.crt` and `tls.key` keys by default, so no extra configuration is needed.

```yaml
global:
  tls:
    clientCertSecret:
      name: "scalr-agent-mtls"
```

To create the secret:

```shell
kubectl create secret tls scalr-agent-mtls \
  --cert=/path/to/scalr-agent.crt \
  --key=/path/to/scalr-agent.key \
  -n scalr-agent
```

For an Opaque secret with non-standard keys, specify the key names:

```yaml
global:
  tls:
    clientCertSecret:
      name: "my-mtls-secret"
      certKey: "client.crt"
      keyKey: "client.key"
```

**Option 2: Inline PEM values from files**

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --set-file global.tls.clientCert=/path/to/scalr-agent.crt \
  --set-file global.tls.clientKey=/path/to/scalr-agent.key
```

Or in a values file:

```yaml
global:
  tls:
    clientCert: |
      -----BEGIN CERTIFICATE-----
      MIIDXTCCAkWgAwIBAgIJAKZ...
      -----END CERTIFICATE-----
    clientKey: |
      -----BEGIN EC PRIVATE KEY-----
      MHQCAQEEIIr...
      -----END EC PRIVATE KEY-----
```

If both `clientCertSecret.name` and `clientCert`/`clientKey` are set, `clientCertSecret` takes precedence.

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

This section describes the security model of the chart, covering how the agent authenticates with the Scalr platform, how run workloads are isolated, and how access to cloud credentials is controlled.

### Authentication and Authorization

The agent authenticates with the Scalr platform using a token hierarchy with progressively narrower scopes — each token is a JWT and carries only the permissions required for its specific role:

1. Agent Pool Token — a long-lived token configured via the `agent.token` Helm value (passed to agent services as `SCALR_AGENT_TOKEN`). It identifies the agent to the Scalr platform and is used only during initial registration and startup.
2. Agent Task Token — a token generated by the Scalr platform during task acquisition for the agent worker, valid only for that specific task execution. Used for task-specific API calls, downloading the configuration version, and streaming logs. Scoped to the run's workspace. Exists only for the lifetime of the task.
3. Scalr Run Token — a token generated by the Scalr platform during task acquisition for the runner container, valid only for that specific task execution. Passed to the run environment as the `SCALR_TOKEN` environment variable for the OpenTofu/Terraform remote state backend. Scoped to the minimum permissions required for a run: `workspaces:read`, `workspaces:lock`, `module-versions:read`, `state-versions:read`, and `state-versions:create` within the context of the run's workspace. Exists only for the lifetime of the task.

All API calls authenticate via `Authorization: Bearer <token>` headers. All tokens are passed to containers via Kubernetes Secrets and mounted as environment variables — they are never embedded in plaintext in Pod specs, ConfigMaps, or chart values.

Communication with the Scalr platform uses HTTPS exclusively, making all traffic transparent for proxying and monitoring by agent operators. All connections are outbound — the Scalr platform never initiates inbound connections to the agent, and the agent never exposes any TCP ports.

In addition to regular HTTP API calls, the agent establishes an outbound connection to the Scalr relay service (`relay.<scalr-url>`) — an HTTP long-polling channel used for Scalr-to-agent messaging. The Scalr platform pushes messages about available tasks and cancellation signals through this relay.

If an Agent Pool Token is revoked (e.g. from the Scalr Agent Pool tokens page), subsequent API calls return `401`, which causes the agents using it to shut down.

### Multi-tenant Isolation

This chart provides strong isolation for multi-tenant environments by deploying each run in a separate container with restricted filesystem access.

The agent worker process and the run environment process (where OpenTofu/Terraform is executed) are separated into different containers and communicate via a minimalistic IPC mechanism.
The run environment process has no filesystem access except to its own data directory, ensuring runs cannot interfere with each other or access shared system resources.

### Runner Security Context

Runner pods inherit their Linux user, group, seccomp, and capability settings from `task.runner.securityContext`. The defaults run the container as the non-root UID/GID `1000`, drop all Linux capabilities, and enforce a read-only root filesystem.

The default is strict and compatible with Terraform/OpenTofu workloads, and it’s generally not recommended to change it. However, it can be useful to disable `readOnlyRootFilesystem` and switch the user to root if you need to install packages via package managers like `apt-get` or `dnf` from Workspace hooks.

### Access to VM Metadata Service

> [!WARNING]
> This feature has known [limitations](#limitations). Verify that it is effective for your setup before relying on it.

The chart includes an `task.allowMetadataService` configuration option to control task pod access to the VM metadata service at `169.254.169.254`, used by AWS, GCP, and Azure to expose instance metadata and credentials.

By default, the chart creates a [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) for task pods that blocks egress traffic to `169.254.169.254/32`. All other outbound traffic is allowed. Controller pods are not affected.

To disable this policy and allow access to the VM metadata service, set:

```shell
$~ helm upgrade ... \
    --set task.allowMetadataService=true
```

#### Limitations

This feature relies on egress NetworkPolicy enforcement, which requires a compatible [CNI plugin](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy#plugins). Effectiveness may vary depending on how your cloud provider implements the Instance Metadata Service (IMDS).

Ensure your cluster uses a CNI plugin that supports egress NetworkPolicies. Tested configurations:

| Cluster   | CNI / network setup                                                                 | IMDS blocked |
|-----------|--------------------------------------------------------------------------------------|:------------:|
| AWS EKS   | Amazon VPC CNI (data plane) + Calico for network policy only (tigera-operator with `cni.type: AmazonVPC`) | ✅ |
| GKE       | Dataplane V1 (Calico)                                                               | ❌ |
| GKE       | [Dataplane V2](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2) (Cilium/eBPF) | ✅ |
| Azure AKS | Azure CNI (network plugin) + Cilium (network data-plane)                          | ✅ |

**Note (EKS):** Pod networking is provided by Amazon VPC CNI. Calico is used only as the network policy engine (no Calico data plane); the VPC CNI is patched so Calico can enforce policy (e.g. `ANNOTATE_POD_IP=true` on the aws-node DaemonSet)

## Network Requirements

The agent requires outbound HTTPS access to the following endpoints:

| Hostname                              | Port | Purpose                                                                                                                                                              |
| ------------------------------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| scalr.io                              | 443  | Polling for new tasks, posting status updates and logs, downloading IaC configuration versions, private modules, and software binary releases |
| docker.io, docker.com, cloudfront.net | 443  | Pulling the [scalr/agent](https://hub.docker.com/r/scalr/agent) and [scalr/runner](https://hub.docker.com/r/scalr/runner) images                                    |
| registry.opentofu.org                 | 443  | Downloading public providers and modules from the OpenTofu Registry                                                                                                  |
| registry.terraform.io                 | 443  | Downloading public providers and modules from the Terraform Registry                                                                                                 |

Ensure the agent can also reach any services required by your OpenTofu/Terraform configurations or hook scripts, such as cloud provider APIs, VCS providers, or custom software distribution endpoints.

If you use custom module or provider registries, or Docker registry mirrors, additional network access rules may be required.

## Job History Management

Kubernetes automatically removes Jobs after `task.job.ttlSecondsAfterFinished` seconds (default: 60). Increase this value for debugging or to preserve job history longer, or decrease it to optimize cluster resource usage.

## Metrics and Observability

The agent can be configured to send telemetry data, including both trace spans and metrics, using [OpenTelemetry](https://opentelemetry.io/).

OpenTelemetry is an extensible, open-source telemetry protocol and platform that enables the Scalr Agent to remain vendor-neutral while producing telemetry data for a wide range of platforms.

Enable telemetry for both the agent controller deployment and the agent worker jobs by configuring an OpenTelemetry collector endpoint:

```yaml
otel:
  enabled: true
  endpoint: "otel-collector:4317"  # gRPC endpoint
  metricsEnabled: true
  tracesEnabled: false  # Optional: enable distributed tracing
```

See [all configuration options](#values).

Learn more about [available metrics](https://docs.scalr.io/docs/metrics).

### Resource Attributes Autodiscovery

When running in Kubernetes, the agent automatically discovers and enriches OTLP resource attributes
from pod labels and annotations mounted via the Downward API.

#### Scalr Tag Autodiscovery

The following pod labels are mapped to OTLP resource attributes:

| Label | Default | OTLP Attribute |
|---|---|---|
| `infra.scalr.io/app` | — | `app` |
| `infra.scalr.io/env` | — | `deployment.environment.name` |
| `infra.scalr.io/service` | `scalr-agent` | `service.name` |

#### Datadog Tag Autodiscovery

The agent supports [Datadog Tag Autodiscovery](https://docs.datadoghq.com/containers/kubernetes/tag/?tab=datadogoperator#tag-autodiscovery) via the `ad.datadoghq.com/tags` pod annotation. Tags defined in this annotation are parsed as a JSON object and merged into the OTLP resource attributes.

Example:

```yaml
annotations:
  ad.datadoghq.com/tags: '{"env":"production","team":"backend"}'
```

When the annotation is present on task pods, it is automatically extended with account and workspace context:

```yaml
annotations:
  ad.datadoghq.com/tags: '{"env":"production","team":"backend","account_name":"mainiacp","account_id":"acc-svrcncgh453bi8g","workspace_name":"main","workspace_id":"ws-v0p5qsps90tv7tvuc"}'
```

### Sentry Error Tracking

To enable error reporting to [Sentry](https://sentry.io/), configure the DSN for both the agent controller and task pods:

```yaml
agent:
  sentryDsn: "https://<key>@<org>.ingest.sentry.io/<project>"
```

Leave `sentryDsn` empty (the default) to disable Sentry integration.

## RBAC

By default the chart provisions:

- **ServiceAccount** used by the controller and task pods
- **Role/RoleBinding** with namespaced access to manage pods/jobs and related resources needed for task execution
- **ClusterRole/ClusterRoleBinding** granting read access to `AgentTaskTemplate` resources (`agenttasktemplates.scalr.io`)

Set `rbac.create=false` to bring your own ServiceAccount/Rules, or adjust permissions with `rbac.rules` and `rbac.clusterRules`.

## Custom Resource Definitions

This chart bundles the `agenttasktemplates.scalr.io` CRD and installs or upgrades it automatically via Helm. The CRD defines the job template that the controller uses to create task pods.

Installing the CRD requires cluster-admin permissions or a role with `customresourcedefinitions` create/update at cluster scope. The identity running `helm install` must have these permissions.

Verify installation:

```shell
kubectl get crd agenttasktemplates.scalr.io
```

## Planned Changes

This section outlines planned architecture changes that may be relevant for long-term chart maintenance.

### Update Minimum Requirements to Kubernetes 1.36 Once GA

Update the minimum required Kubernetes version to 1.36, which includes the stable [ImageVolume](https://kubernetes.io/docs/tasks/configure-pod-container/image-volumes/) feature and containerd 2.2+ with [subPath](https://github.com/containerd/containerd/pull/11578) support for ImageVolume.
In Kubernetes 1.35 (current minimal required version), ImageVolume is in Beta status but enabled by default, and we consider it ready for limited usage.
This chart relies on ImageVolume to provision application components via OCI registry and plans to use this feature more heavily in the future.

## Troubleshooting and Support

### CRD Installation Fails: Insufficient Permissions

If `helm install` fails with an error like:

```
Error: failed to install CRD crds/agenttasktemplate.yaml: 1 error occurred:
    * customresourcedefinitions.apiextensions.k8s.io is forbidden: User "..." cannot create resource
      "customresourcedefinitions" in API group "apiextensions.k8s.io" at the cluster scope
```

The identity running `helm install` does not have cluster-admin permissions. This chart installs the [CRD](#custom-resource-definitions) on first install, which requires cluster-scoped `customresourcedefinitions` create/update access.

**Fix:** Run `helm install` with a cluster-admin account (or an IAM role/user bound to `cluster-admin`). On EKS, this typically means using the IAM entity that created the cluster or one explicitly granted access via `aws-auth` / EKS access entries:

```shell
# Verify the current identity has sufficient permissions
kubectl auth can-i create customresourcedefinitions --all-namespaces
```

If the output is `yes`, proceed with the install. If `no`, switch to a cluster-admin context before running `helm install`.

### Debug Logging

If you encounter internal system errors or unexpected behavior, enable debug logs:

```shell
helm upgrade scalr-agent scalr-agent-helm/agent-job \
  --reuse-values \
  --set agent.debug="1"
```

Then collect logs ([see below](#collecting-logs)) and open a support request at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31) and attach them to your support ticket.

### Collecting Logs

When inspecting logs, you'll need both the agent log (from the `scalr-agent-*` deployment pod) and the task log (from an `scalr-agent-run-*` job pod). Job pods are available for 60 seconds after completion by default. You may want to increase this time window using `task.job.ttlSecondsAfterFinished` to allow more time for log collection.

Use `kubectl logs` to retrieve logs from the `scalr-agent-*` pods:

```shell
kubectl logs -n <namespace> <task-pod-name> --all-containers
```

### Getting Support

For issues not covered above, or if you need additional assistance, open a support ticket at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31).
For errors, see the detailed steps at https://docs.scalr.io/docs/troubleshooting#creating-a-support-ticket on how to gather the right information to speed up issue resolution.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

### Agent

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.affinity | object | `{}` | Node affinity for the controller pod. |
| agent.annotations | object | `{}` | Additional annotations for the Deployment (workload object). |
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
| agent.labels | object | `{}` | Additional labels for the Deployment (workload object). |
| agent.logFormat | string | `"json"` | The log formatter. Options: plain, dev or json. Defaults to json. |
| agent.moduleCache.concurrency | int | `10` | Maximum number of threads used for module cache operations (initialization and caching). This value is global for the Scalr service and applies across all concurrent runs. Increasing it will increase resource consumption and may improve module cache speed, but the effect depends on individual setups. |
| agent.moduleCache.enabled | bool | `false` | Enable module caching. Disabled by default since the default configuration uses an ephemeral volume for the cache directory. |
| agent.moduleCache.sizeLimit | string | `"40Gi"` | Module cache soft limit. Must be tuned according to cache directory size. |
| agent.nodeSelector | object | `{}` | Node selector for assigning the controller pod to specific nodes. Example: `--set agent.nodeSelector."node-type"="agent-controller"` |
| agent.podAnnotations | object | `{}` | Controller-specific pod annotations (merged with global.podAnnotations, overrides duplicate keys). |
| agent.podDisruptionBudget | object | `{"enabled":true,"maxUnavailable":null,"minAvailable":1}` | PodDisruptionBudget configuration for controller high availability. Only applied when replicaCount > 1. Ensures minimum availability during voluntary disruptions. |
| agent.podDisruptionBudget.enabled | bool | `true` | Enable PodDisruptionBudget for the controller. |
| agent.podDisruptionBudget.maxUnavailable | string | `nil` | Maximum number of controller pods that can be unavailable. Either minAvailable or maxUnavailable must be set, not both. |
| agent.podDisruptionBudget.minAvailable | int | `1` | Minimum number of controller pods that must be available. Either minAvailable or maxUnavailable must be set, not both. |
| agent.podLabels | object | `{}` | Controller-specific pod labels (merged with global.podLabels, overrides duplicate keys). |
| agent.podSecurityContext | object | `{}` | Controller-specific pod security context (merged with global.podSecurityContext, overrides duplicate keys). |
| agent.providerCache.concurrency | int | `10` | Maximum number of threads used for provider installations. This value is global for the Scalr service and applies across all concurrent runs. Increasing it will increase resource consumption and may improve provider installation speed, but the effect depends on individual setups. |
| agent.providerCache.enabled | bool | `false` | Enable provider caching. Disabled by default since the default configuration uses an ephemeral volume for the cache directory. |
| agent.providerCache.sizeLimit | string | `"40Gi"` | Provider cache soft limit. Must be tuned according to cache directory size. |
| agent.replicaCount | int | `1` | Number of agent controller replicas. |
| agent.resources | object | `{"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits for the agent controller container. |
| agent.sentryDsn | string | `""` | Sentry DSN for error tracking. Leave empty to disable. |
| agent.terminationGracePeriodSeconds | int | `180` | Grace period in seconds before forcibly terminating the controller container. |
| agent.token | string | `""` | The agent pool token for authentication. |
| agent.tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| agent.tolerations | list | `[]` | Node tolerations for the controller pod. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set agent.tolerations[0].key=dedicated,agent.tolerations[0].operator=Equal,agent.tolerations[0].value=agent-controller,agent.tolerations[0].effect=NoSchedule` |
| agent.topologySpreadConstraints | object | `{}` | Topology spread constraints for the controller pod. |
| agent.url | string | `""` | The Scalr URL to connect the agent to. |

### Global

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| global.annotations | object | `{}` | Global annotations applied to all chart resources (metadata.annotations). |
| global.imageNamespace | string | "" | Global image namespace/organization override for all images. Replaces the namespace in repositories (e.g., "myorg" changes "scalr/runner" to "myorg/runner"). Combined: registry="gcr.io/project" + namespace="myorg" + repo="scalr/runner" → "gcr.io/project/myorg/runner:tag" Leave empty to preserve original namespace. |
| global.imagePullSecrets | list | `[]` | Global image pull secrets for private registries. |
| global.imageRegistry | string | "" | Global Docker registry override for all images. Prepended to image repositories. Example: "us-central1-docker.pkg.dev/myorg/images" Leave empty to use default Docker Hub. |
| global.labels | object | `{}` | Global labels applied to all chart resources (metadata.labels). |
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
| global.tls | object | `{"caBundle":"","caBundleSecret":{"key":"ca-bundle.crt","name":""},"clientCert":"","clientCertSecret":{"certKey":"tls.crt","keyKey":"tls.key","name":""},"clientKey":""}` | TLS/SSL configuration for custom certificate authorities. |
| global.tls.caBundle | string | `""` | Inline CA bundle content as an alternative to caBundleSecret. Provide the complete CA certificate chain in PEM format. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. Example: caBundle: |   -----BEGIN CERTIFICATE-----   MIIDXTCCAkWgAwIBAgIJAKZ...   -----END CERTIFICATE-----   -----BEGIN CERTIFICATE-----   MIIEFzCCAv+gAwIBAgIUDiCT...   -----END CERTIFICATE----- |
| global.tls.caBundleSecret | object | `{"key":"ca-bundle.crt","name":""}` | Reference to an existing Kubernetes secret containing a CA bundle. This CA bundle is mounted to all agent pods and used for outbound TLS validation (e.g., Scalr API, VCS, registries). The secret must exist in the same namespace as the chart installation. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. |
| global.tls.caBundleSecret.key | string | `"ca-bundle.crt"` | Key within the secret that contains the CA bundle file. |
| global.tls.caBundleSecret.name | string | `""` | Name of the Kubernetes secret containing the CA bundle. Leave empty to use the inline caBundle or system certificates. |
| global.tls.clientCert | string | `""` | Inline PEM-encoded client certificate for mTLS. Creates a chart-managed secret. If both clientCertSecret.name and clientCert are set, clientCertSecret takes precedence. Example: clientCert: |   -----BEGIN CERTIFICATE-----   MIIDXTCCAkWgAwIBAgIJAKZ...   -----END CERTIFICATE----- |
| global.tls.clientCertSecret | object | `{"certKey":"tls.crt","keyKey":"tls.key","name":""}` | Reference to an existing Kubernetes secret containing the mTLS client certificate and private key. Used for mutual TLS authentication between the agent and Scalr. The secret must exist in the same namespace as the chart installation. Supports both `kubernetes.io/tls` and `Opaque` secret types. If both clientCertSecret.name and clientCert/clientKey are set, clientCertSecret takes precedence. Maps to SCALR_AGENT_TLS_CERT_FILE and SCALR_AGENT_TLS_KEY_FILE environment variables. |
| global.tls.clientCertSecret.certKey | string | `"tls.crt"` | Key within the secret that contains the PEM-encoded client certificate. |
| global.tls.clientCertSecret.keyKey | string | `"tls.key"` | Key within the secret that contains the PEM-encoded private key. |
| global.tls.clientCertSecret.name | string | `""` | Name of the Kubernetes secret containing the client certificate and key. Leave empty to use inline clientCert/clientKey or to disable mTLS. |
| global.tls.clientKey | string | `""` | Inline PEM-encoded private key for mTLS. Creates a chart-managed secret. Must be provided together with clientCert. Example: clientKey: |   -----BEGIN EC PRIVATE KEY-----   MHQCAQEEIIr...   -----END EC PRIVATE KEY----- |

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
| persistence.cache | object | `{"emptyDir":{"sizeLimit":"1Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteMany","claimName":"","storage":"90Gi","storageClassName":"","subPath":""}}` | Cache directory storage configuration. Stores OpenTofu/Terraform providers, modules and binaries. Mounted to both worker (for agent cache) and runner (for binary/plugin cache) containers. |
| persistence.cache.emptyDir | object | `{"sizeLimit":"1Gi"}` | EmptyDir volume configuration (used when enabled is false). |
| persistence.cache.emptyDir.sizeLimit | string | `"1Gi"` | Size limit for the emptyDir volume. |
| persistence.cache.enabled | bool | `false` | Enable persistent storage for cache directory. Highly recommended: Avoids re-downloading providers and binaries (saves 1-5 minutes per run). When false, providers and binaries are downloaded fresh for each task. When true, cache is shared across all task pods for significant performance improvement (may vary depending on RWM volume performace). |
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
| rbac.clusterRules | list | `[{"apiGroups":["scalr.io"],"resources":["agenttasktemplates"],"verbs":["get","list","watch"]}]` | Cluster-wide RBAC rules (applied via ClusterRole bound in the release namespace). |
| rbac.create | bool | `true` | Create the namespaced Role/RoleBinding and cluster-scope RoleBinding. |
| rbac.rules | list | `[{"apiGroups":[""],"resources":["pods"],"verbs":["get","list","watch","create","delete","deletecollection","patch","update"]},{"apiGroups":[""],"resources":["pods/log"],"verbs":["get"]},{"apiGroups":[""],"resources":["pods/exec"],"verbs":["get","create"]},{"apiGroups":[""],"resources":["pods/status"],"verbs":["get","patch","update"]},{"apiGroups":["apps"],"resources":["deployments"],"verbs":["get","list","watch"]},{"apiGroups":["batch"],"resources":["jobs"],"verbs":["get","list","watch","create","delete","deletecollection","patch","update"]},{"apiGroups":["batch"],"resources":["jobs/status"],"verbs":["get","patch","update"]},{"apiGroups":[""],"resources":["events"],"verbs":["list"]}]` | Namespaced RBAC rules granted to the controller ServiceAccount. |

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
| task.allowMetadataService | bool | `false` | When set to `true`, disables the NetworkPolicy that blocks access to the VM metadata service (`169.254.169.254`) for agent task containers. When set to `false` (default), a NetworkPolicy is created to prevent workloads from accessing cloud credentials or instance metadata. |
| task.extraVolumes | list | `[]` | Additional volumes for task job pods. |
| task.job | object | `{"basename":"","ttlSecondsAfterFinished":60}` | Job configuration for task execution. |
| task.job.basename | string | `""` | Base name prefix for spawned Kubernetes Jobs (defaults to fullname, e.g., "scalr-agent"). Jobs are named as `<basename>-<run-id>`. See README for details on task naming. |
| task.job.ttlSecondsAfterFinished | int | `60` | Time in seconds after job completion before it is automatically deleted. |
| task.jobAnnotations | object | `{}` | Additional annotations for the Job (workload object). |
| task.jobLabels | object | `{}` | Additional labels for the Job (workload object). |
| task.nodeSelector | object | `{}` | Node selector for assigning task job pods to specific nodes. Example: `--set task.nodeSelector."node-type"="agent-worker"` |
| task.podAnnotations | object | `{}` | Task-specific pod annotations (merged with global.podAnnotations, overrides duplicate keys). |
| task.podLabels | object | `{}` | Task-specific pod labels (merged with global.podLabels, overrides duplicate keys). |
| task.podSecurityContext | object | `{}` | Task-specific pod security context (merged with global.podSecurityContext, overrides duplicate keys). |
| task.runner | object | `{"extraEnv":{},"extraVolumeMounts":[],"image":{"pullPolicy":"IfNotPresent","repository":"scalr/runner","tag":"0.2.0"},"memorySoftLimitPercent":80,"memoryWarnPercent":90,"resources":{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seLinuxOptions":{}}}` | Runner container configuration (environment where Terraform/OpenTofu commands are executed). |
| task.runner.extraEnv | object | `{}` | Additional environment variables for the runner container. |
| task.runner.extraVolumeMounts | list | `[]` | Additional volume mounts for the runner container. |
| task.runner.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/runner","tag":"0.2.0"}` | Runner container image settings. Default image: https://hub.docker.com/r/scalr/runner, repository: https://github.com/Scalr/runner Note: For Scalr-managed agents, this may be overridden by Scalr account image settings. |
| task.runner.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| task.runner.image.repository | string | `"scalr/runner"` | Default repository for the runner image. |
| task.runner.image.tag | string | `"0.2.0"` | Default tag for the runner image. |
| task.runner.memorySoftLimitPercent | int | `80` | Memory soft limit as a percentage of the hard limit (task.runner.resources.limits.memory). When memory usage exceeds this value, the process will be gracefully terminated by the agent. Graceful termination ensures that OpenTofu/Terraform workloads push state before exiting, preventing state loss. Setting this value too high reduces the memory headroom available for state push and increases the risk of state loss. Have no effect when task.runner.resources.limits.memory is not set. For example, when task.runner.resources.limits.memory is set to 1000Mi and memorySoftLimitPercent is 80%, the workload will be gracefully terminated when memory usage reaches 800Mi. |
| task.runner.memoryWarnPercent | int | `90` | Memory warning threshold as a percentage of the soft limit (task.runner.memorySoftLimitPercent). A warning is logged to the run console when memory usage exceeds this value, indicating that the workload is at risk of being terminated due to high memory usage. The warning is reported after the run completes. Has no effect when task.runner.memorySoftLimitPercent or task.runner.resources.limits.memory are not set. |
| task.runner.resources | object | `{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}}` | Resource requests and limits for the runner container. Note: For scalr-managed agents, this may be overridden by Scalr platform billing resource tier presets. |
| task.runner.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsNonRoot":true,"seLinuxOptions":{}}` | Security context for the runner container. The default declaration duplicates some critical options from podSecurityContext to keep them independent. |
| task.runner.securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation. |
| task.runner.securityContext.capabilities | object | `{"drop":["ALL"]}` | Container capabilities restrictions for security. |
| task.runner.securityContext.privileged | bool | `false` | Run container in privileged mode. |
| task.runner.securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem. |
| task.runner.securityContext.runAsNonRoot | bool | `true` | Run container as non-root user for security. |
| task.runner.securityContext.seLinuxOptions | object | `{}` | SELinux options for the container. |
| task.sidecars | list | `[]` | Additional sidecar containers for task job pods. |
| task.startupTimeoutSeconds | int | `180` | Maximum time in seconds for the agent worker container to become ready and begin Scalr run execution. If the pod does not start within this period, the controller fails the Scalr run and deletes the job. |
| task.terminationGracePeriodSeconds | int | `360` | Grace period in seconds before forcibly terminating task job containers. |
| task.tolerations | list | `[]` | Node tolerations for task job pods. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set task.tolerations[0].key=dedicated,task.tolerations[0].operator=Equal,task.tolerations[0].value=agent-worker,task.tolerations[0].effect=NoSchedule` |
| task.worker | object | `{"extraEnv":{},"extraVolumeMounts":[],"resources":{"limits":{"memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}},"securityContext":{}}` | Worker container configuration (sidecar that supervises task execution). |
| task.worker.extraEnv | object | `{}` | Additional environment variables for the worker container (merged with agent.extraEnv). |
| task.worker.extraVolumeMounts | list | `[]` | Additional volume mounts for the worker container. |
| task.worker.resources | object | `{"limits":{"memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}}` | Resource requests and limits for the worker container. |
| task.worker.securityContext | object | `{}` | Security context for the worker container. |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Override the full name of resources (takes precedence over nameOverride). |
| nameOverride | string | `""` | Override the base name used in resource names (defaults to "scalr-agent"). |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
