# agent-local

![Version: 0.6.9](https://img.shields.io/badge/Version-0.6.9-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.8.0](https://img.shields.io/badge/AppVersion-1.8.0-informational?style=flat-square)

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
- Helm 3.5+
- A compatible StorageClass or existing persistent volumes for [PVC storage](#storage-modes) (optional)
- Scalr Agent >= 0.45.0

## Installation

To install the chart with the release name `scalr-agent`:

```console
$ helm repo add scalr-charts https://scalr.github.io/agent-helm/
$ helm install scalr-agent scalr-charts/agent-local --set agent.token="<agent-token>"
```

See [Configuration](#configuration) for chart settings and [helm install](https://helm.sh/docs/helm/helm_install/) for command options.

## Overview

The agent-local chart runs Scalr agents in a Deployment by default. Each pod uses `emptyDir`
storage for temporary run data and its cache. You can also use a [StatefulSet](#workload-selection)
and choose a [storage mode](#storage-modes) for each volume.

The chart uses the `local` driver, which runs all tasks inside the agent container.
It uses the `scalr/agent` image instead of the [scalr/runner](https://docs.scalr.io/docs/run-environment#runner-image) image.

Each agent handles one task at a time. Increase `replicaCount` to run more tasks at once.

### Pros

The chart is simple to deploy. Agents do not need access to the Kubernetes API.
Provider and binary caching are enabled by default.

### Cons

The chart does not configure autoscaling. Change `replicaCount` manually or configure a
Horizontal Pod Autoscaler. Pods keep their resources while idle, which can increase costs
during quiet periods.

Runs share the same container and storage. See [Multi-tenant Isolation](#multi-tenant-isolation)
before using one agent pool across teams.

## Architecture Diagram

<p align="center">
  <img src="assets/deploy-diagram.drawio.svg" />
</p>

## Versioning Policy

This chart deploys the [Scalr Agent](https://docs.scalr.io/docs/agent-pools) using the [`scalr/agent`](https://hub.docker.com/r/scalr/agent) image. The agent supports multiple runtimes beyond Kubernetes and is versioned independently from this chart.

Each new agent release triggers a new chart release with an updated `appVersion`. By default the chart deploys the matching agent image: `image.tag` is empty and falls back to `.Chart.AppVersion`. Upgrade the agent by upgrading the chart to a release that ships the agent version you want.

The [Scalr Agent changelog](https://docs.scalr.io/docs/changelog) covers agent and platform changes.
The chart's [CHANGELOG.md](CHANGELOG.md) covers Kubernetes resources, values, and defaults.

> [!WARNING]
> Setting `image.tag` to an agent version other than the chart's `appVersion` is not recommended. Each chart release is tested and coordinated with a specific agent version, and mismatched combinations may include breaking changes between the application and the chart's Kubernetes resources.

## Custom Certificate Authorities

If your environment uses custom or self-signed certificates, configure a CA bundle for the agent.
The agent uses this bundle for all HTTPS connections, including the Scalr API, VCS providers,
and provider registries.

> [!IMPORTANT]
> This replaces the system default CA certificates. If you need to trust both custom CAs and public CAs, include the complete certificate chain with both your custom certificates and standard root CAs in the bundle.

Provide the CA bundle inline:

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

Or reference an existing secret:

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

Once you have the private key and signed certificate, store them in a `kubernetes.io/tls`
or `Opaque` secret. A `kubernetes.io/tls` secret uses `tls.crt` and `tls.key` keys by default:

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

You can also pass the PEM files directly to Helm:

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

Base the image on `scalr/agent` and keep its `ENTRYPOINT` and `CMD` so it still runs the agent
service. You can add tools, files, configuration, certificates, and environment variables.
Changing existing module paths or replacing the entrypoint is not supported across agent updates.

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

Each agent has two writable volumes. The data volume holds temporary run files at
`agent.dataDir` and defaults to a 4Gi `emptyDir`. The cache volume holds binaries, providers,
and modules at `agent.cacheDir` and defaults to a 20Gi `emptyDir`.

### Storage modes

Enable storage with `persistence.data.enabled` or `persistence.cache.enabled`, then choose
the volume's `mode`. If mode is unset, Deployment uses `persistentVolumeClaim` and
StatefulSet uses `volumeClaimTemplate`.

| Mode | Workload | Storage |
|------|----------|---------|
| `persistentVolumeClaim` | Either | One shared PVC per volume, created by Helm or supplied through `claimName`. |
| `ephemeral` | Either | One [PVC per pod](#generic-ephemeral-pvcs), deleted with the pod. |
| `volumeClaimTemplate` | [StatefulSet](#workload-selection) | One PVC per replica, reused after pod replacement. |

To use `emptyDir`, keep `enabled: false` and leave mode unset.

Configure PVCs under `persistence.data.persistentVolumeClaim` or
`persistence.cache.persistentVolumeClaim`. All modes use these settings, except `claimName`,
which only applies to `persistentVolumeClaim` mode.

For replicas on different nodes, use per-pod storage or a shared `ReadWriteMany` claim.
The chart rejects multiple replicas with a chart-created shared `ReadWriteOncePod` claim.

Deployment rolling updates can stall with a shared `ReadWriteOnce` or `ReadWriteOncePod` claim.
Use `strategy.type: Recreate` or `strategy.rollingUpdate.maxSurge: 0` to release the claim first.

### Cache volume persistence

To use an existing shared cache:

```yaml
persistence:
  cache:
    enabled: true
    mode: persistentVolumeClaim
    persistentVolumeClaim:
      claimName: my-cache-pvc
```

See [Provider Cache](https://docs.scalr.io/docs/providers-cache) and
[Module Cache](https://docs.scalr.io/docs/modules-cache) for cache configuration.

### Data volume persistence

Keep the default `emptyDir` for temporary run data. Set `persistence.data.enabled: true` and
`persistence.data.mode: ephemeral` to give each pod a separate PVC, as in the
[ephemeral cache example](#generic-ephemeral-pvcs).

### Generic ephemeral PVCs

Use [generic ephemeral PVCs](https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/#generic-ephemeral-volumes)
to give each Deployment pod a fresh cache:

```yaml
replicaCount: 3
persistence:
  cache:
    enabled: true
    mode: ephemeral
```

## Workload selection

`workload.kind` defaults to `Deployment`.
Use `StatefulSet` and enable cache persistence to keep each replica's cache when its pod is
replaced:

```yaml
replicaCount: 3
workload:
  kind: StatefulSet
persistence:
  cache:
    enabled: true
```

Each replica gets its own 20Gi cache PVC.

StatefulSet agents append the first eight characters of the pod UID to the pod name,
so a recreated pod connects under a new name.

Deployment uses `strategy`. StatefulSet uses `workload.statefulSet.updateStrategy`.
Changing `workload.statefulSet.podManagementPolicy` or claim templates requires recreating
the StatefulSet.

Per-replica StatefulSet PVCs are retained after scaling down or uninstalling. Configure this with
`workload.statefulSet.persistentVolumeClaimRetentionPolicy`.

### Migrate to StatefulSet

Changing `workload.kind` from `Deployment` to `StatefulSet` replaces the controller and its
pods. Agents will be unavailable during the switch.

1. Stop assigning work to the old agents, wait for active runs to finish, and upgrade with `replicaCount: 0`.
2. Upgrade with `workload.kind: StatefulSet`, your storage modes, and the desired replica count.
   New PVCs start empty. Switching from shared PVCs to claim templates can delete chart-managed shared claims.
3. Check that agents connect to Scalr and mount the expected claims before resuming work.

For a gradual migration, install a separate release. Check that the new
agents work, then let the old agents finish their runs before removing them.

## Security

### Multi-tenant Isolation

Agents process runs one at a time in the same container. Runs can share files left by earlier
runs, and they share the agent's filesystem. A run can change cached providers or modules
that later runs use without verification.

Use separate agent pools for groups with different access permissions, such as teams or
Scalr Environments. Give each pool access only to the resources its group needs.

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

Set `podAnnotations` to configure eviction protection for your autoscaler.
The chart puts its default eviction annotations on the Deployment or StatefulSet itself.
These annotations do not protect its pods from eviction.

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
| persistence.cache.enabled | bool | `false` | Enable PVC storage for the cache directory. Uses emptyDir when false. |
| persistence.cache.mode | string | `""` | Storage mode: persistentVolumeClaim, ephemeral, or volumeClaimTemplate. Requires enabled: true. When empty, defaults to persistentVolumeClaim for Deployment or volumeClaimTemplate for StatefulSet. See [Storage modes](#storage-modes). |
| persistence.cache.persistentVolumeClaim | object | <pre>{<br>&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;"storage":&nbsp;"20Gi",<br>&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;"subPath":&nbsp;""<br>}</pre> | PVC settings for all storage modes. |
| persistence.cache.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | PVC access mode. See [Storage modes](#storage-modes) for shared PVC restrictions. |
| persistence.cache.persistentVolumeClaim.annotations | object | <pre>{}</pre> | Annotations on chart-created PVCs or claim templates. helm.sh/resource-policy applies only to shared chart-managed PVCs. |
| persistence.cache.persistentVolumeClaim.claimName | string | `""` | Existing PVC for persistentVolumeClaim mode. Leave empty to create a claim. Ignored by other modes. |
| persistence.cache.persistentVolumeClaim.storage | string | `"20Gi"` | Storage size for the PVC. |
| persistence.cache.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and bind a matching pre-provisioned PV. |
| persistence.cache.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |
| persistence.data | object | <pre>{<br>&nbsp;&nbsp;"emptyDir":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"sizeLimit":&nbsp;"4Gi"<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"enabled":&nbsp;false,<br>&nbsp;&nbsp;"mode":&nbsp;"",<br>&nbsp;&nbsp;"persistentVolumeClaim":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;&nbsp;&nbsp;"storage":&nbsp;"4Gi",<br>&nbsp;&nbsp;&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;&nbsp;&nbsp;"subPath":&nbsp;""<br>&nbsp;&nbsp;}<br>}</pre> | Data directory storage configuration. Stores workspace data including configuration versions, modules, and providers. |
| persistence.data.emptyDir | object | <pre>{<br>&nbsp;&nbsp;"sizeLimit":&nbsp;"4Gi"<br>}</pre> | EmptyDir volume configuration. |
| persistence.data.emptyDir.sizeLimit | string | `"4Gi"` | Size limit for the emptyDir volume. Set to null or "" to leave it unlimited. |
| persistence.data.enabled | bool | `false` | Enable PVC storage for the data directory. Uses emptyDir when false. |
| persistence.data.mode | string | `""` | Storage mode: persistentVolumeClaim, ephemeral, or volumeClaimTemplate. Requires enabled: true. When empty, defaults to persistentVolumeClaim for Deployment or volumeClaimTemplate for StatefulSet. See [Storage modes](#storage-modes). |
| persistence.data.persistentVolumeClaim | object | <pre>{<br>&nbsp;&nbsp;"accessMode":&nbsp;"ReadWriteOnce",<br>&nbsp;&nbsp;"annotations":&nbsp;{},<br>&nbsp;&nbsp;"claimName":&nbsp;"",<br>&nbsp;&nbsp;"storage":&nbsp;"4Gi",<br>&nbsp;&nbsp;"storageClassName":&nbsp;"",<br>&nbsp;&nbsp;"subPath":&nbsp;""<br>}</pre> | PVC settings for all storage modes. |
| persistence.data.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | PVC access mode. See [Storage modes](#storage-modes) for shared PVC restrictions. |
| persistence.data.persistentVolumeClaim.annotations | object | <pre>{}</pre> | Annotations on chart-created PVCs or claim templates. helm.sh/resource-policy applies only to shared chart-managed PVCs. |
| persistence.data.persistentVolumeClaim.claimName | string | `""` | Existing PVC for persistentVolumeClaim mode. Leave empty to create a claim. Ignored by other modes. |
| persistence.data.persistentVolumeClaim.storage | string | `"4Gi"` | Storage size for the PVC. |
| persistence.data.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and bind a matching pre-provisioned PV. |
| persistence.data.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |

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
| workload.kind | string | `"Deployment"` | Workload controller: Deployment or StatefulSet. See [Workload selection](#workload-selection). See [Migrate to StatefulSet](#migrate-to-statefulset) before changing an existing release. |
| workload.statefulSet.persistentVolumeClaimRetentionPolicy | object | <pre>{<br>&nbsp;&nbsp;"whenDeleted":&nbsp;"Retain",<br>&nbsp;&nbsp;"whenScaled":&nbsp;"Retain"<br>}</pre> | Retention policy for StatefulSet per-replica PVCs. |
| workload.statefulSet.persistentVolumeClaimRetentionPolicy.whenDeleted | string | `"Retain"` | Retain or Delete per-replica PVCs when the StatefulSet is deleted. |
| workload.statefulSet.persistentVolumeClaimRetentionPolicy.whenScaled | string | `"Retain"` | Retain or Delete per-replica PVCs when replicas are scaled down. |
| workload.statefulSet.podManagementPolicy | string | `"Parallel"` | StatefulSet pod management policy: Parallel or OrderedReady. Immutable after installation. |
| workload.statefulSet.updateStrategy | object | <pre>{<br>&nbsp;&nbsp;"rollingUpdate":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"partition":&nbsp;0<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"type":&nbsp;"RollingUpdate"<br>}</pre> | StatefulSet update strategy. |
| workload.statefulSet.updateStrategy.rollingUpdate.partition | int | `0` | Lowest pod number to update during a StatefulSet rolling update. |
| workload.statefulSet.updateStrategy.type | string | `"RollingUpdate"` | StatefulSet update type: RollingUpdate or OnDelete. |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fullnameOverride | string | `""` | Fully override the resource name for all resources. |
| nameOverride | string | `""` | Override the default resource name prefix for all resources. |
| strategy | object | <pre>{<br>&nbsp;&nbsp;"rollingUpdate":&nbsp;{<br>&nbsp;&nbsp;&nbsp;&nbsp;"maxSurge":&nbsp;"25%",<br>&nbsp;&nbsp;&nbsp;&nbsp;"maxUnavailable":&nbsp;"50%"<br>&nbsp;&nbsp;},<br>&nbsp;&nbsp;"type":&nbsp;"RollingUpdate"<br>}</pre> | Deployment update strategy. |
| strategy.rollingUpdate | object | <pre>{<br>&nbsp;&nbsp;"maxSurge":&nbsp;"25%",<br>&nbsp;&nbsp;"maxUnavailable":&nbsp;"50%"<br>}</pre> | Rolling update parameters. |
| strategy.rollingUpdate.maxSurge | string | `"25%"` | Maximum number of pods that can be created above the desired number during an update. |
| strategy.rollingUpdate.maxUnavailable | string | `"50%"` | Maximum number of pods that can be unavailable during an update. |
| strategy.type | string | `"RollingUpdate"` | Type of deployment strategy. Options: RollingUpdate, Recreate. See [Storage modes](#storage-modes) for shared PVC restrictions. |

---

Homepage: <https://github.com/Scalr/agent-helm/tree/master/charts/agent-local>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
