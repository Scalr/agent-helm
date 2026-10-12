# agent-local

![Version: 0.6.8](https://img.shields.io/badge/Version-0.6.8-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.7.0](https://img.shields.io/badge/AppVersion-1.7.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
Deploys a static number of agents and executes runs in shared agent pods.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Versioning Policy](#versioning-policy)
- [Custom Certificate Authorities](#custom-certificate-authorities)
- [Mutual TLS (mTLS)](#mutual-tls-mtls)
- [Custom Agent Image](#custom-agent-image)
- [Volumes](#volumes)
- [Workload Selection](#workload-selection)
- [Migrate to StatefulSet](#migrate-to-statefulset)
- [Security](#security)
- [Metrics and Observability](#metrics-and-observability)
- [Provider Network Mirrors](#provider-network-mirrors)
- [Network Requirements](#network-requirements)
- [Termination](#termination)
- [Troubleshooting](#troubleshooting)
- [Configuration](#configuration)
- [Maintainers](#maintainers)

## Prerequisites

- Kubernetes 1.33+
- Helm 3.0+
- A compatible StorageClass or pre-provisioned PVs for PVC-backed storage (optional)
- Scalr Agent >= 0.45.0

## Installation

To install the chart with the release name `scalr-agent`:

```console
$ helm repo add scalr-charts https://scalr.github.io/agent-helm/
$ helm install scalr-agent scalr-charts/agent-local --set agent.token="<agent-token>"
```

_See [configuration](#configuration) below._

_See [helm install](https://helm.sh/docs/helm/helm_install/) for command documentation._

## Overview

The agent-local chart deploys the Scalr Agent as a Deployment by default, with `emptyDir` storage
for workspace data and caching. You can select a StatefulSet and configure shared PVCs,
generic ephemeral PVCs, or persistent PVCs per StatefulSet replica.

The chart uses the `local` Scalr Agent driver, where all operations are executed in local subprocesses.
As a result, it uses the `scalr/agent` image as the base environment for runs instead of [scalr/runner](https://docs.scalr.io/docs/run-environment#runner-image) image.

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

## Versioning Policy

This chart deploys the [Scalr Agent](https://docs.scalr.io/docs/agent-pools) using the [`scalr/agent`](https://hub.docker.com/r/scalr/agent) image. The agent supports multiple runtimes beyond Kubernetes and is versioned independently from this chart.

Each new agent release triggers a new chart release with an updated `appVersion`. By default the chart deploys the matching agent image: `image.tag` is empty and falls back to `.Chart.AppVersion`. Upgrade the agent by upgrading the chart to a release that ships the agent version you want.

The two changelogs cover different scopes:

- [Scalr Agent changelog](https://docs.scalr.io/docs/changelog) — application-level changes and new Scalr platform functionality
- [CHANGELOG.md](CHANGELOG.md) — chart-level changes: Kubernetes resources, values, and defaults

> [!WARNING]
> Setting `image.tag` to an agent version other than the chart's `appVersion` is not recommended. Each chart release is tested and coordinated with a specific agent version, and mismatched combinations may include breaking changes between the application and the chart's Kubernetes resources.

## Custom Certificate Authorities

If your environment uses custom or self-signed certificates, you can configure the CA bundle used by the agent for TLS validation. This configuration sets the **primary CA bundle** for all agent HTTPS connections (to Scalr API, VCS providers, provider registries, etc.).

> [!IMPORTANT]
> This replaces the system default CA certificates. If you need to trust both custom CAs and public CAs, include the complete certificate chain with both your custom certificates and standard root CAs in the bundle.

You can provide the CA bundle in two ways:

**Option 1: Inline CA bundle**

```yaml
agent:
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
agent:
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

Mutual TLS (mTLS) adds transport-layer identity verification on top of the existing JWT authentication. With standard TLS only the server is verified; mTLS requires the agent to also present a client certificate during the TLS handshake, proving to Scalr that the request originates from a legitimate agent host. This means a stolen JWT alone is no longer sufficient — the attacker also needs the pool private key, which stays on operator-managed infrastructure.

The bootstrap certificate and private key are mounted read-only at `/etc/scalr-agent/ssl/` and mapped to `SCALR_AGENT_TLS_CERT_FILE` and `SCALR_AGENT_TLS_KEY_FILE`.

To obtain an mTLS certificate, generate an EC P-256 private key and CSR (Certificate Signing Request):

```shell
openssl ecparam -genkey -name prime256v1 -noout -out scalr-agent.key
openssl req -new -key scalr-agent.key -out scalr-agent.csr -subj "/CN=agent-pool"
```

Then submit the CSR via the Agent Pool UI when registering a new agent, or via the **Certificates** tab on the Agent Pool page. Scalr signs the CSR and returns a certificate. The private key never leaves the operator host.

Once you have both the private key and the signed certificate, configure the chart using one of the following options:

**Option 1: Reference existing secret**

Works with both `kubernetes.io/tls` and `Opaque` secret types. A `kubernetes.io/tls` secret uses `tls.crt` and `tls.key` keys by default:

```yaml
agent:
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
agent:
  tls:
    clientCertSecret:
      name: "my-mtls-secret"
      certKey: "client.crt"
      keyKey: "client.key"
```

**Option 2: Inline PEM values from files**

```shell
helm upgrade --install scalr-agent scalr-agent/agent-local \
  --set-file agent.tls.clientCert=/path/to/scalr-agent.crt \
  --set-file agent.tls.clientKey=/path/to/scalr-agent.key
```

Or in a values file:

```yaml
agent:
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

## Custom Agent Image

This chart uses the [local driver](https://docs.scalr.io/docs/drivers#local-driver), meaning runs (Terraform/OpenTofu operations, OPA policies, shell hooks, etc.) execute directly inside the agent container. The image therefore needs to ship everything those runs depend on.

By default the chart uses the [`scalr/agent`](https://hub.docker.com/r/scalr/agent) image, which includes the Scalr Agent service, the OpenTofu/Terraform runtime, and basic tooling (`git`, `curl`, `openssl`, `ca-certificates`, etc.).

If your workflows require additional software, you can build your own image on top of `scalr/agent` with the extra tools pre-installed. Follow the contract from the [Scalr Build Custom Agent Image guide](https://docs.scalr.io/docs/run-environment#build-custom-agent-image):

- Base the image on `scalr/agent` and **do not** modify the existing `ENTRYPOINT` / `CMD` — the image must keep running the agent service.
- Only **additive** changes are supported: installing extra software, files, executables, configs, certificate bundles, or environment variables. Deeper modifications (changing module paths, replacing the entrypoint, etc.) are not supported across agent updates.

Example:

```dockerfile
FROM scalr/agent:<version>
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    awscli kubectl && \
    rm -rf /var/lib/apt/lists/*
USER 1000
```

Then point the chart at the resulting image:

```yaml
image:
    repository: registry.example.com/my-scalr-agent
    tag: "1.0.5"
```

## Volumes

Each agent has two writable volumes:

- **Data:** temporary run files, mounted at `agent.dataDir`. Defaults to a 4Gi `emptyDir`.
- **Cache:** binaries, providers, and modules, mounted at `agent.cacheDir`. Defaults to a 20Gi `emptyDir`.

### Storage modes

Set `persistence.data.mode` and `persistence.cache.mode` independently:

| Mode | Workload | Storage lifetime |
|------|----------|------------------|
| `emptyDir` | Either | Node storage, lost when the pod is deleted. |
| `persistentVolumeClaim` | Either | One shared PVC per volume, created by Helm or supplied through `claimName`. |
| `ephemeral` | Either | One PVC per pod, deleted with the pod. |
| `volumeClaimTemplate` | StatefulSet | One PVC per replica, reused after pod replacement. |

All modes survive container restarts. An empty `mode` keeps the existing `enabled` behavior:
`false` selects `emptyDir`, and `true` selects a shared PVC. An explicit mode overrides `enabled`.
Set `emptyDir.sizeLimit` to `null` or `""` for unlimited storage.

PVC modes use the corresponding `persistentVolumeClaim` settings. `storage` is the size of
**each claim**. An empty `storageClassName` uses the cluster default. `"-"` requires a
pre-provisioned volume. For dynamic provisioning, prefer `WaitForFirstConsumer`.
`claimName` selects an existing claim only in shared PVC mode.

Both volumes need writable storage. A shared `ReadWriteOnce` claim requires pods on one node.
Use per-pod claims or `ReadWriteMany` across nodes. A shared `ReadWriteOncePod` claim needs
`replicaCount: 1` and, for Deployment, `strategy.type: Recreate` to let the old pod release it.
Check the actual access mode when using an existing claim.

### Cache volume persistence

Use [StatefulSet storage](#workload-selection) to keep a separate cache for each replica.
To use an existing shared cache:

```yaml
persistence:
  cache:
    mode: persistentVolumeClaim
    persistentVolumeClaim:
      claimName: my-cache-pvc
```

See [Provider Cache](https://docs.scalr.io/docs/providers-cache) and
[Module Cache](https://docs.scalr.io/docs/modules-cache) for cache configuration.

The top-level `persistence.enabled` and `persistence.persistentVolumeClaim.*` keys are deprecated.
Use `persistence.cache.*` instead.

### Data volume persistence

Keep the default `emptyDir` for temporary run data. Use `persistence.data.mode: ephemeral`
for a dedicated disk, or `volumeClaimTemplate` to retain data across StatefulSet pod replacements.

### Generic ephemeral PVCs

Give each Deployment pod its own cache PVC:

```yaml
replicaCount: 3
persistence:
  cache:
    mode: ephemeral
```

Replacement pods get a fresh cache. Kubernetes deletes each PVC with its pod.
The StorageClass reclaim policy controls backing-volume cleanup. A `Retain` policy requires
manual cleanup. See [generic ephemeral volumes](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/#generic-ephemeral-volumes).

StatefulSet replacement pods reuse PVC names and may wait for the previous pod's ephemeral PVCs
to be garbage-collected. Use `volumeClaimTemplate` to reuse each replica's existing storage.

## Workload selection

`workload.kind` defaults to `Deployment`, including upgrades using `--reuse-values`.
Use `StatefulSet` with `volumeClaimTemplate` to retain each replica's cache across pod replacements:

```yaml
replicaCount: 3
workload:
  kind: StatefulSet
persistence:
  cache:
    mode: volumeClaimTemplate
```

This creates three 20Gi cache PVCs named `cache-dir-<statefulset-name>-<ordinal>`.
The StatefulSet name is limited to 52 characters. Names that need normalization or shortening
include a hash of the full name to avoid collisions.
Agent names follow `<statefulset-name>-<ordinal>`. Use distinct release names or
`fullnameOverride` values within each Scalr agent pool, including across namespaces and clusters.

Deployment uses `strategy`. StatefulSet uses `workload.statefulSet.updateStrategy`.
Its default `Parallel` policy scales agents together, while rolling updates replace one pod
at a time. Set `podManagementPolicy` before installation because it is immutable.
Claim templates are also immutable, including their size, storage class, and annotations.
Plan PVC expansion or controller recreation separately.

StatefulSet PVCs are retained after scale-down and uninstall by default. Configure
`workload.statefulSet.persistentVolumeClaimRetentionPolicy` to change this behavior.
Retained PVCs need manual cleanup. See [StatefulSet retention](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#persistentvolumeclaim-retention).

## Migrate to StatefulSet

Changing `workload.kind` from `Deployment` to `StatefulSet` replaces the controller and its
pods. Plan for a capacity interruption.

1. Stop assigning work to the old agents, wait for active runs to finish, and scale to zero.
2. Upgrade with `workload.kind: StatefulSet`, your storage modes, and replica count. Per-pod claims
   start empty.
3. Verify agent connections and mounted claims before resuming work.

For a gradual migration, install a separate release with distinct names and verify it before
draining the old agents.

## Security

### Multi-tenant Isolation

This chart deploys a set of static agent workers that process runs sequentially within the same container, which provides a simple and easy-to-maintain architecture but has important security implications for multi-tenant environments:

- **Container reuse**: Multiple runs may execute in the same container without cleanup between executions.
- **Shared filesystem**: The agent process and Scalr Run commands (OpenTofu/Terraform) execute in the same container without filesystem isolation, allowing runs to write to shared cache storage that will be reused by subsequent runs.
- **Cache tampering risk**: Runs can potentially modify cached providers or modules directly without verification.

This chart is suitable when deploying separate agent deployments (agent pools) for each RBAC perimeter (e.g., Scalr Environment). For example, you can ensure each team in your organization works on individual agent pools without having access to each other's resources.

If you want to manage a single agent deployment across different teams within your organization, consider using the [`agent-job`](../agent-job) chart.

### Agent Security Context

Agent pods inherit their Linux user, group, seccomp, and capability settings from `securityContext` configuration. The defaults run the container as the non-root UID/GID `1000`, drop all Linux capabilities, and enforce a read-only root filesystem.

The default is strict and compatible with Terraform/OpenTofu workloads, and it’s generally not recommended to change it. However, it can be useful to disable `readOnlyRootFilesystem` and switch the user to root if you need to install packages via package managers like `apt-get` or `dnf` from Workspace hooks.

### Access to VM Metadata Service

> [!WARNING]
> This feature has known [limitations](#limitations). Verify that it is effective for your setup before relying on it.

The chart includes an `allowMetadataService` configuration option to control agent pod access to the VM metadata service at `169.254.169.254`, used by AWS, GCP, and Azure to expose instance metadata and credentials.

By default, access to the VM metadata service is allowed. To block it, the chart can create a [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/) that denies egress traffic to `169.254.169.254/32` while allowing all other outbound traffic.

To enable this policy and block access to the VM metadata service, set:

```shell
$~ helm upgrade ... \
    --set allowMetadataService=false
```

#### Limitations

This feature relies on egress NetworkPolicy enforcement, which requires a compatible [CNI plugin](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/network-policy#plugins). Effectiveness may vary depending on how your cloud provider implements the Instance Metadata Service (IMDS).

Ensure your cluster uses a CNI plugin that supports egress NetworkPolicies. Tested configurations:

| Cluster | CNI | IMDS Blocked |
|---------|-----|:------------:|
| AWS EKS | Calico | ✅ |
| GKE | Dataplane V1 (Calico) | ❌ |
| GKE | [Dataplane V2](https://docs.cloud.google.com/kubernetes-engine/docs/how-to/dataplane-v2) (Cilium/eBPF) | ✅ |

## Metrics and Observability

The agent can be configured to send telemetry data, including both trace spans and metrics, using [OpenTelemetry](https://opentelemetry.io/).

OpenTelemetry is an extensible, open-source telemetry protocol and platform that enables the Scalr Agent to remain vendor-neutral while producing telemetry data for a wide range of platforms.

The agent emits OTLP over gRPC (default port `4317`) to an [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) that you deploy. The Collector receives the telemetry and forwards it to your observability backend (Datadog, Grafana Cloud, Prometheus + Tempo, etc.) — the agent does not push to backends directly.

The endpoint is a `host:port` reachable from the agent Pod, where `host` is the DNS name (or IP) of your Collector — not a fixed value. Common forms:

- `<collector-service>:4317` — Kubernetes Service in the same namespace (e.g. `my-otel-collector:4317`).
- `<collector-service>.<namespace>.svc.cluster.local:4317` — Service in a different namespace (e.g. `otel-collector.observability.svc.cluster.local:4317`).
- An external or vendor gateway hostname (e.g. `otel.example.com:4317`).

Enable telemetry agent by configuring an OpenTelemetry collector endpoint:

```yaml
extraEnv:
  SCALR_AGENT_OTLP_ENDPOINT: "<otel-collector-host>:4317"  # gRPC endpoint
  SCALR_AGENT_OTLP_METRICS_ENABLED: "true"
  SCALR_AGENT_OTLP_TRACES_ENABLED: "true"
```

See [all configuration options](https://docs.scalr.io/docs/configuration#telemetry).

Learn more about [available metrics](https://docs.scalr.io/docs/metrics).

### Verify

Once telemetry is configured, the agent emits a confirmation log event at startup:

```json
{
  "event": "OpenTelemetry metrics enabled",
  "level": "info",
  "logger_name": "tacoagent.telemetry",
  "timestamp": "2026-05-11 11:21:58.470827",
  "otlp_endpoint": "<your-otel-endpoint>:4317",
  "attrs": {
    "service.name": "agent",
    "service.version": "1.0.0",
    "deployment.environment.name": "",
    "app": "scalr.io"
  }
}
```

If the agent cannot push metrics to the collector, you will see OpenTelemetry warnings and errors in the logs:

```json
{
  "event": "Failed to export metrics to <your-otel-endpoint>:4317, error code: StatusCode.INTERNAL",
  "level": "error",
  "logger_name": "opentelemetry.exporter.otlp.proto.grpc.exporter",
  "timestamp": "2026-05-11 10:32:12.292258"
}
```

If you see this:

- Ensure the collector endpoint is reachable from the agent Pod.
- Ensure the collector is healthy and accepting OTLP gRPC traffic.
- Ensure no NetworkPolicy, service mesh, or egress firewall is blocking traffic between the agent and the collector.
- If using TLS or a vendor gateway, ensure credentials and any required headers are correctly set.

## Termination

Because agents may be managing an active run stage, it is important to allow them to terminate gracefully rather than being abruptly stopped with SIGKILL, which would leave no opportunity to perform a graceful shutdown of the underlying OpenTofu/Terraform workload or push a status update to the Scalr platform, and can lead to undefined behavior — ranging from degraded performance and Scalr Run processing delays to agent capacity issues, stuck runs, or even OpenTofu/Terraform state loss.

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

The agent container executes Scalr Run workloads and processes end-user IaC configuration and code, resulting in highly variable memory utilization and an elevated risk of exceeding the memory limit and triggering an OOM kill.

When a agent container exceeds its memory limit, Kubernetes sends SIGKILL directly to the process with no opportunity to clean up. For OpenTofu/Terraform workloads, this can result in state loss or corruption if the process is killed before it can push state.

Monitor your run's resource usage and configure resource requests and limits accordingly to mitigate the risk of unexpected termination.

## Provider Network Mirrors

The agent can install OpenTofu/Terraform providers from [provider network mirrors](https://opentofu.org/docs/internals/provider-network-mirror-protocol/) instead of the origin registries, for example when runs execute in a network without access to the public registries. When caching providers from the dependency lockfile, the agent downloads them from the mirrors in the configured order and falls back to the origin registry itself. During `init`, OpenTofu/Terraform consults the mirrors and falls back to the origin registry only when a mirror returns a clean 404 for a provider it does not serve. Static GCS/S3 bucket mirrors return 403 for missing objects, so they must replicate every provider matched by their `include` patterns. Requires Terraform >= 0.15 and is not supported for Terragrunt runs.

```yaml
agent:
  providerNetworkMirrors:
    - url: https://mirror.example.com/
      include:
        - registry.terraform.io/*/*
        - registry.opentofu.org/*/*
```

`include` limits a mirror to matching provider source addresses (`hostname/namespace/type`, where `*` matches a whole segment) and defaults to all providers. An optional `token` adds a bearer credential for the mirror. The token is rendered into the pod spec as a plain environment variable value:

```yaml
agent:
  providerNetworkMirrors:
    - url: https://private-mirror.example.com/
      token: "<bearer-token>"
```

## Network Requirements

The agent requires outbound HTTPS access to the following endpoints:

| Hostname                              | Port | Purpose                                                                                                                                                              |
| ------------------------------------- | ---- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| scalr.io                              | 443  | Polling for new tasks, posting status updates and logs, downloading IaC configuration versions, private modules, and software binary releases |
| docker.io, docker.com, cloudfront.net | 443  | Pulling the [scalr/agent](https://hub.docker.com/r/scalr/agent) image (or [scalr/agent-runner](https://hub.docker.com/r/scalr/agent-runner) if configured)                                    |
| registry.opentofu.org                 | 443  | Downloading public providers and modules from the OpenTofu Registry                                                                                                  |
| registry.terraform.io                 | 443  | Downloading public providers and modules from the Terraform Registry                                                                                                 |

Ensure the agent can also reach any services required by your OpenTofu/Terraform configurations or hook scripts, such as cloud provider APIs, VCS providers, or custom software distribution endpoints.

If you use custom module or provider registries, or Docker registry mirrors, additional network access rules may be required.

## Troubleshooting

If you encounter internal system errors or unexpected behavior, please open a Scalr Support request at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31).

Before doing so, enable debug logs using the `extraEnv.SCALR_AGENT_DEBUG` option. Then collect the debug-level application logs covering the time window when the incident occurred, and attach them to your support ticket.

To archive all logs from the Scalr agent namespace in a single bundle, replace the `ns` variable with the name of your Helm release namespace and run:

```shell
ns="scalr-agent"
mkdir -p logs && for pod in $(kubectl get pods -n $ns -o name); do kubectl logs -n $ns $pod > "logs/${pod##*/}.log"; done && zip -r agent-local-logs.zip logs && rm -rf logs
```

It's best to pull the logs immediately after an incident, since this command will not retrieve logs from restarted or terminated pods.

## Configuration

The chart is configured through the Helm values listed below — set them with `--set key=value` or a custom values YAML file.

The Scalr Agent process itself reads its configuration from `SCALR_AGENT_*` environment variables, documented in the [Scalr Agent configuration reference](https://docs.scalr.io/docs/configuration). Pass any of them to the agent through the `extraEnv` value:

```console
$ helm install scalr-agent scalr-charts/agent-local \
  --set agent.token="<agent-token>" \
  --set extraEnv.SCALR_AGENT_DEBUG=1 \
  --set extraEnv.HTTPS_PROXY="http://myproxy.com:3128"
```

> [!NOTE]
> Some variables are managed by the chart and are rejected if set through `extraEnv` (the chart render fails and lists them): `SCALR_AGENT_NAME`, `SCALR_URL`, `SCALR_AGENT_TOKEN`, `SCALR_AGENT_DRIVER`, `SCALR_AGENT_CONCURRENCY`, `SCALR_AGENT_DISCONNECT_ON_STOP`, `SCALR_AGENT_WORKER_ON_STOP_ACTION`, `SCALR_AGENT_WORKER_GRACE_SHUTDOWN_TIMEOUT`, `SCALR_AGENT_DATA_DIR`, `SCALR_AGENT_PROVIDER_NETWORK_MIRRORS`, `SCALR_AGENT_CA_CERT`, and `SSL_CERT_FILE`. Use the dedicated Helm values for those.

### Scheduling & Placement

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | <pre>{}</pre> | Affinity rules for pod scheduling. |
| nodeSelector | object | <pre>{}</pre> | Node selector for scheduling Scalr Agent pods. |
| replicaCount | int | `1` | Number of replicas for the Scalr Agent workload. Adjust for high availability. |
| tolerations | list | <pre>[]</pre> | Tolerations for scheduling pods on tainted nodes. |

### Agent

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.cacheDir | string | `"/var/lib/scalr-agent/cache"` | Cache directory where the agent stores provider binaries, plugin cache, and metadata. This directory must be readable, writable, and executable. <br>Exports [`SCALR_AGENT_CACHE_DIR`](https://docs.scalr.io/docs/configuration#scalr_agent_cache_dir). |
| agent.dataDir | string | `"/var/lib/scalr-agent/data"` | Data directory where the agent stores workspace data (configuration versions, modules, and providers). This directory must be readable, writable, and executable. <br>Exports [`SCALR_AGENT_DATA_DIR`](https://docs.scalr.io/docs/configuration#scalr_agent_data_dir). |
| agent.providerNetworkMirrors | list | <pre>[]</pre> | OpenTofu/Terraform provider network mirrors, as a list of mirror objects. Each entry has a required `url`, an optional `token` bearer credential, and an optional `include` list of provider source address patterns (`hostname/namespace/type`, `*` matches a whole segment; defaults to all providers). Note: a `token` set here is rendered into the pod spec as a plain env value. <br>Exports [`SCALR_AGENT_PROVIDER_NETWORK_MIRRORS`](https://docs.scalr.io/docs/configuration#scalr_agent_provider_network_mirrors). |
| agent.shutdownMode | string | `"graceful"` | The agent termination behaviour. Can be graceful, force or drain. <br>Exports [`SCALR_AGENT_WORKER_ON_STOP_ACTION`](https://docs.scalr.io/docs/configuration#scalr_agent_worker_on_stop_action). |
| agent.token | string | `""` | The agent pool token. <br>Exports [`SCALR_AGENT_TOKEN`](https://docs.scalr.io/docs/configuration#scalr_agent_token). |
| agent.tokenExistingSecret | object | <pre>{<br>&nbsp;&nbsp;"key":&nbsp;"token",<br>&nbsp;&nbsp;"name":&nbsp;""<br>}</pre> | Pre-existing Kubernetes secret for the Scalr Agent token. |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| agent.url | string | `""` | The Scalr API endpoint URL. For tokens generated after Scalr version 8.162.0, this value is optional, as the domain can be extracted from the token payload. However, it is recommended to specify the URL explicitly for long-lived services to avoid issues if the account is renamed. <br>Exports [`SCALR_URL`](https://docs.scalr.io/docs/configuration#scalr_url). |

### Agent.TLS

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.tls | object | <pre>{<br>&nbsp;&nbsp;"caBundle":&nbsp;"",<br>&nbsp;&nbsp;"caBundleSecret":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"key":&nbsp;"ca-bundle.crt",<br>&nbsp;&nbsp;&nbsp;&nbsp;"name":&nbsp;""<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"clientCert":&nbsp;"",<br>&nbsp;&nbsp;"clientCertSecret":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"certKey":&nbsp;"tls.crt",<br>&nbsp;&nbsp;&nbsp;&nbsp;"keyKey":&nbsp;"tls.key",<br>&nbsp;&nbsp;&nbsp;&nbsp;"name":&nbsp;""<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"clientKey":&nbsp;""<br>}</pre> | mTLS client certificate configuration for mutual TLS authentication with Scalr. <br>Exports [`SCALR_AGENT_TLS_CERT_FILE`](https://docs.scalr.io/docs/configuration#scalr_agent_tls_cert_file) and [`SCALR_AGENT_TLS_KEY_FILE`](https://docs.scalr.io/docs/configuration#scalr_agent_tls_key_file). |
| agent.tls.caBundle | string | `""` | Inline CA bundle content as an alternative to caBundleSecret. Provide the complete CA certificate chain in PEM format. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. Example: caBundle: |   -----BEGIN CERTIFICATE-----   MIIDXTCCAkWgAwIBAgIJAKZ...   -----END CERTIFICATE-----   -----BEGIN CERTIFICATE-----   MIIEFzCCAv+gAwIBAgIUDiCT...   -----END CERTIFICATE----- |
| agent.tls.caBundleSecret | object | <pre>{<br>&nbsp;&nbsp;"key":&nbsp;"ca-bundle.crt",<br>&nbsp;&nbsp;"name":&nbsp;""<br>}</pre> | Reference to an existing Kubernetes secret containing a CA bundle. This CA bundle is mounted to the agent pod and used for outbound TLS validation (e.g., Scalr API, VCS, registries). The secret must exist in the same namespace as the chart installation. If both caBundleSecret.name and caBundle are set, caBundleSecret takes precedence. <br>Exports [`SCALR_AGENT_CA_CERT`](https://docs.scalr.io/docs/configuration#scalr_agent_ca_cert). |
| agent.tls.caBundleSecret.key | string | `"ca-bundle.crt"` | Key within the secret that contains the CA bundle file. |
| agent.tls.caBundleSecret.name | string | `""` | Name of the Kubernetes secret containing the CA bundle. Leave empty to use the inline caBundle or system certificates. |
| agent.tls.clientCert | string | `""` | Inline PEM-encoded client certificate for mTLS. Creates a chart-managed secret. If both clientCertSecret.name and clientCert are set, clientCertSecret takes precedence. Example: clientCert: |   -----BEGIN CERTIFICATE-----   MIIDXTCCAkWgAwIBAgIJAKZ...   -----END CERTIFICATE----- |
| agent.tls.clientCertSecret | object | <pre>{<br>&nbsp;&nbsp;"certKey":&nbsp;"tls.crt",<br>&nbsp;&nbsp;"keyKey":&nbsp;"tls.key",<br>&nbsp;&nbsp;"name":&nbsp;""<br>}</pre> | Reference to an existing Kubernetes secret containing the client certificate and private key. Supports both `kubernetes.io/tls` and `Opaque` secret types. The secret must exist in the same namespace as the chart installation. If both clientCertSecret.name and clientCert/clientKey are set, clientCertSecret takes precedence. |
| agent.tls.clientCertSecret.certKey | string | `"tls.crt"` | Key within the secret that contains the PEM-encoded client certificate. |
| agent.tls.clientCertSecret.keyKey | string | `"tls.key"` | Key within the secret that contains the PEM-encoded private key. |
| agent.tls.clientCertSecret.name | string | `""` | Name of the Kubernetes secret containing the client certificate and key. Leave empty to use inline clientCert/clientKey or to disable mTLS. |
| agent.tls.clientKey | string | `""` | Inline PEM-encoded private key for mTLS. Creates a chart-managed secret. Must be provided together with clientCert. Example: clientKey: |   -----BEGIN EC PRIVATE KEY-----   MHQCAQEEIIr...   -----END EC PRIVATE KEY----- |

### Security

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| allowMetadataService | bool | `true` | When set to `true` (default), disables the NetworkPolicy that blocks access to the VM metadata service (`169.254.169.254`) for agent containers. When set to `false`, a NetworkPolicy is created to prevent workloads from accessing cloud credentials or instance metadata. |
| podSecurityContext | object | <pre>{<br>&nbsp;&nbsp;"fsGroup":&nbsp;1000,<br>&nbsp;&nbsp;"runAsNonRoot":&nbsp;true<br>}</pre> | Security context for Scalr Agent pod. |
| secret | object | <pre>{<br>&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;"labels":&nbsp;{}<br>}</pre> | Secret configuration for storing the Scalr Agent token. |
| secret.annotations | object | <pre>{}</pre> | Annotations for the Secret resource. |
| secret.labels | object | <pre>{}</pre> | Additional labels for the Secret resource. |
| securityContext | object | <pre>{<br>&nbsp;&nbsp;"capabilities":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"drop":&nbsp;[<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"ALL"<br>&nbsp;&nbsp;&nbsp;&nbsp;]<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"privileged":&nbsp;false,<br>&nbsp;&nbsp;"procMount":&nbsp;"Default",<br>&nbsp;&nbsp;"runAsGroup":&nbsp;1000,<br>&nbsp;&nbsp;"runAsNonRoot":&nbsp;true,<br>&nbsp;&nbsp;"runAsUser":&nbsp;1000<br>}</pre> | Security context for Scalr Agent container. |
| securityContext.capabilities | object | <pre>{<br>&nbsp;&nbsp;"drop":&nbsp;[<br>&nbsp;&nbsp;&nbsp;&nbsp;"ALL"<br>&nbsp;&nbsp;]<br>}</pre> | Restrict container capabilities for security. |
| securityContext.privileged | bool | `false` | Run container in privileged mode. Enable only if required. |
| securityContext.procMount | string | `"Default"` | Proc mount type. Valid values: Default, Unmasked, Host. |

### Pod Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| extraEnv | object | <pre>{}</pre> | Additional environment variables for Scalr Agent. Use to configure HTTP proxies or other runtime parameters. |
| extraVolumeMounts | list | <pre>[]</pre> | Additional volume mounts for the Scalr Agent container. Must reference volumes declared in `extraVolumes` (or other pod-level volumes). |
| extraVolumes | list | <pre>[]</pre> | Additional volumes mounted into the Scalr Agent pod. Use to mount extra secrets, configMaps, or other volumes alongside the chart-managed ones. |
| podAnnotations | object | <pre>{}</pre> | Annotations for Scalr Agent pods (e.g., for monitoring or logging). |
| podLabels | object | <pre>{}</pre> | Labels for Scalr Agent pods. Selector labels take precedence over duplicate keys. |

### Image

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. 'IfNotPresent' is efficient for stable deployments. |
| image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| image.tag | string | `""` | Image tag. Overrides the default (chart appVersion). Leave empty to use chart default. |
| imagePullSecrets | list | <pre>[]</pre> | Image pull secret to use for registry authentication. |

### Persistence

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| persistence.cache | object | <pre>{<br>&nbsp;&nbsp;"emptyDir":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"sizeLimit":&nbsp;"20Gi"<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"enabled":&nbsp;false,<br>&nbsp;&nbsp;"mode":&nbsp;"",<br>&nbsp;&nbsp;"persistentVolumeClaim":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;&nbsp;&nbsp;"storage":&nbsp;"20Gi",<br>&nbsp;&nbsp;&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;&nbsp;&nbsp;"subPath":&nbsp;""<br>&nbsp;&nbsp;}<br>}</pre> | Cache directory storage configuration. Stores OpenTofu/Terraform providers, modules and binaries. |
| persistence.cache.emptyDir | object | <pre>{<br>&nbsp;&nbsp;"sizeLimit":&nbsp;"20Gi"<br>}</pre> | EmptyDir volume configuration. |
| persistence.cache.emptyDir.sizeLimit | string | `"20Gi"` | Size limit for the emptyDir volume. Set to null or "" to leave it unlimited. |
| persistence.cache.enabled | bool | `false` | Enable persistent storage for the cache directory. When false, uses emptyDir (survives container restarts, lost when the pod is replaced). When true, uses a shared PVC. Only used when mode is empty. |
| persistence.cache.mode | string | `""` | Storage mode: emptyDir, persistentVolumeClaim (one shared claim), ephemeral (a PVC per pod), or volumeClaimTemplate (a persistent PVC per StatefulSet replica). When empty, enabled selects emptyDir (false) or persistentVolumeClaim (true). An explicit mode takes precedence over enabled. Legacy top-level settings retain precedence for claim options until removed. |
| persistence.cache.persistentVolumeClaim | object | <pre>{<br>&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;"storage":&nbsp;"20Gi",<br>&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;"subPath":&nbsp;""<br>}</pre> | Claim settings for shared, generic ephemeral, and StatefulSet per-replica PVCs. |
| persistence.cache.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC. Use "ReadWriteOnce" for per-pod/per-replica claims or a shared claim on one node. Use "ReadWriteMany" to share the cache across multiple agent pods (requires a compatible storage class). |
| persistence.cache.persistentVolumeClaim.annotations | object | <pre>{}</pre> | Annotations on chart-created PVCs or claim templates. helm.sh/resource-policy applies only to shared chart-managed PVCs. |
| persistence.cache.persistentVolumeClaim.claimName | string | `""` | Existing shared PVC name. If empty in persistentVolumeClaim mode, creates `<fullname>-cache`. Ignored by other storage modes. |
| persistence.cache.persistentVolumeClaim.storage | string | `"20Gi"` | Storage size for the PVC. |
| persistence.cache.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and bind a matching pre-provisioned PV. |
| persistence.cache.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |
| persistence.data | object | <pre>{<br>&nbsp;&nbsp;"emptyDir":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"sizeLimit":&nbsp;"4Gi"<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"enabled":&nbsp;false,<br>&nbsp;&nbsp;"mode":&nbsp;"",<br>&nbsp;&nbsp;"persistentVolumeClaim":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;&nbsp;&nbsp;"storage":&nbsp;"4Gi",<br>&nbsp;&nbsp;&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;&nbsp;&nbsp;"subPath":&nbsp;""<br>&nbsp;&nbsp;}<br>}</pre> | Data directory storage configuration. Stores workspace data including configuration versions, modules, and providers. |
| persistence.data.emptyDir | object | <pre>{<br>&nbsp;&nbsp;"sizeLimit":&nbsp;"4Gi"<br>}</pre> | EmptyDir volume configuration. |
| persistence.data.emptyDir.sizeLimit | string | `"4Gi"` | Size limit for the emptyDir volume. Set to null or "" to leave it unlimited. |
| persistence.data.enabled | bool | `false` | Enable persistent storage for the data directory. When false, uses emptyDir (ephemeral, recommended for most use cases as each pod gets fresh workspace). When true, uses a shared PVC. Only used when mode is empty. |
| persistence.data.mode | string | `""` | Storage mode: emptyDir, persistentVolumeClaim (one shared claim), ephemeral (a PVC per pod), or volumeClaimTemplate (a persistent PVC per StatefulSet replica). When empty, enabled selects emptyDir (false) or persistentVolumeClaim (true). An explicit mode takes precedence over enabled. All PVC modes use persistentVolumeClaim settings. |
| persistence.data.persistentVolumeClaim | object | <pre>{<br>&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;"storage":&nbsp;"4Gi",<br>&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;"subPath":&nbsp;""<br>}</pre> | Claim settings for shared, generic ephemeral, and StatefulSet per-replica PVCs. |
| persistence.data.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC. Use "ReadWriteOnce" for per-pod/per-replica claims or a shared claim on one node. Use "ReadWriteMany" only if the Scalr Agent supports shared storage (e.g., with NFS). |
| persistence.data.persistentVolumeClaim.annotations | object | <pre>{}</pre> | Annotations on chart-created PVCs or claim templates. helm.sh/resource-policy applies only to shared chart-managed PVCs. |
| persistence.data.persistentVolumeClaim.claimName | string | `""` | Existing shared PVC name. If empty in persistentVolumeClaim mode, creates `<fullname>-data`. Ignored by other storage modes. |
| persistence.data.persistentVolumeClaim.storage | string | `"4Gi"` | Storage size for the PVC. |
| persistence.data.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and bind a matching pre-provisioned PV. |
| persistence.data.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |
| persistence.enabled | bool | `false` | DEPRECATED: Use `persistence.cache.enabled` instead. Kept for backward compatibility; will be removed in a future release. When set to `true`, behaves as `persistence.cache.enabled: true` and emits a deprecation warning. |
| persistence.persistentVolumeClaim | object | <pre>{<br>&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;"storage":&nbsp;"20Gi",<br>&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;"subPath":&nbsp;""<br>}</pre> | DEPRECATED: Use `persistence.cache.persistentVolumeClaim` instead. Kept for backward compatibility; will be removed in a future release. When the legacy `persistence.enabled` (top-level) is `true`, these values are used for the cache PVC and a deprecation warning is emitted. |
| persistence.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | DEPRECATED: see `persistence.cache.persistentVolumeClaim.accessMode`. |
| persistence.persistentVolumeClaim.annotations | object | <pre>{}</pre> | DEPRECATED: see `persistence.cache.persistentVolumeClaim.annotations`. |
| persistence.persistentVolumeClaim.claimName | string | `""` | DEPRECATED: see `persistence.cache.persistentVolumeClaim.claimName`. |
| persistence.persistentVolumeClaim.storage | string | `"20Gi"` | DEPRECATED: see `persistence.cache.persistentVolumeClaim.storage`. |
| persistence.persistentVolumeClaim.storageClassName | string | `""` | DEPRECATED: see `persistence.cache.persistentVolumeClaim.storageClassName`. |
| persistence.persistentVolumeClaim.subPath | string | `""` | DEPRECATED: see `persistence.cache.persistentVolumeClaim.subPath`. |

### Resource Management

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| resources | object | <pre>{<br>&nbsp;&nbsp;"limits":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"cpu":&nbsp;"4000m",<br>&nbsp;&nbsp;&nbsp;&nbsp;"memory":&nbsp;"2048Mi"<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"requests":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"cpu":&nbsp;"1000m",<br>&nbsp;&nbsp;&nbsp;&nbsp;"memory":&nbsp;"1024Mi"<br>&nbsp;&nbsp;}<br>}</pre> | Resource limits and requests for Scalr Agent pods. Set identical resource limits and requests to enable Guaranteed QoS and minimize eviction risk. See: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/#quality-of-service-classes |

### Service account

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| serviceAccount.annotations | object | <pre>{}</pre> | Annotations for the service account. |
| serviceAccount.automountToken | bool | `false` | Whether to automount the service account token in the Scalr Agent pod. |
| serviceAccount.create | bool | `false` | Create a Kubernetes service account for the Scalr Agent. |
| serviceAccount.labels | object | <pre>{}</pre> | Additional labels for the service account. |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and 'create' is true. |

### Deployment & Scaling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| terminationGracePeriodSeconds | int | `120` | Termination grace period (in seconds) for pod shutdown. <br>Exports [`SCALR_AGENT_WORKER_GRACE_SHUTDOWN_TIMEOUT`](https://docs.scalr.io/docs/configuration#scalr_agent_worker_grace_shutdown_timeout). |
| workload.kind | string | `"Deployment"` | Workload controller. Supported values: Deployment, StatefulSet. Changing the kind replaces the controller and its pods. See the migration guide. |
| workload.statefulSet.persistentVolumeClaimRetentionPolicy | object | <pre>{<br>&nbsp;&nbsp;"whenDeleted":&nbsp;"Retain",<br>&nbsp;&nbsp;"whenScaled":&nbsp;"Retain"<br>}</pre> | Retention of StatefulSet volumeClaimTemplate PVCs. |
| workload.statefulSet.persistentVolumeClaimRetentionPolicy.whenDeleted | string | `"Retain"` | Retain or Delete per-replica PVCs when the StatefulSet is deleted. |
| workload.statefulSet.persistentVolumeClaimRetentionPolicy.whenScaled | string | `"Retain"` | Retain or Delete per-replica PVCs when replicas are scaled down. |
| workload.statefulSet.podManagementPolicy | string | `"Parallel"` | StatefulSet scaling policy: Parallel or OrderedReady. Agents can scale independently. Choose before installation. Changing this value requires recreating the StatefulSet. |
| workload.statefulSet.updateStrategy | object | <pre>{<br>&nbsp;&nbsp;"rollingUpdate":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"partition":&nbsp;0<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"type":&nbsp;"RollingUpdate"<br>}</pre> | StatefulSet update strategy. Deployment uses the top-level strategy instead. |
| workload.statefulSet.updateStrategy.rollingUpdate.partition | int | `0` | Lowest pod ordinal to update during a StatefulSet rolling update. |
| workload.statefulSet.updateStrategy.type | string | `"RollingUpdate"` | StatefulSet update type: RollingUpdate or OnDelete. |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Fully override the resource name for all resources. |
| nameOverride | string | `""` | Override the default resource name prefix for all resources. |
| strategy | object | <pre>{<br>&nbsp;&nbsp;"rollingUpdate":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"maxSurge":&nbsp;"25%",<br>&nbsp;&nbsp;&nbsp;&nbsp;"maxUnavailable":&nbsp;"50%"<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"type":&nbsp;"RollingUpdate"<br>}</pre> | Deployment strategy configuration. Only used with workload.kind=Deployment. |
| strategy.rollingUpdate | object | <pre>{<br>&nbsp;&nbsp;"maxSurge":&nbsp;"25%",<br>&nbsp;&nbsp;"maxUnavailable":&nbsp;"50%"<br>}</pre> | Rolling update parameters. |
| strategy.rollingUpdate.maxSurge | string | `"25%"` | Maximum number of pods that can be created above the desired number during an update. |
| strategy.rollingUpdate.maxUnavailable | string | `"50%"` | Maximum number of pods that can be unavailable during an update. |
| strategy.type | string | `"RollingUpdate"` | Type of deployment strategy. Options: RollingUpdate, Recreate. Use Recreate with replicaCount: 1 when sharing a ReadWriteOncePod claim. |

---

**Homepage:** <https://github.com/Scalr/agent-helm/tree/master/charts/agent-local>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
