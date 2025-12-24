# agent-local

![Version: 0.5.62](https://img.shields.io/badge/Version-0.5.62-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.58.0](https://img.shields.io/badge/AppVersion-0.58.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
Best suited for simple deployments and VCS agents.

> [!WARNING]
> This chart is compatible with Scalr Agent >= 0.45.0

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
- Low multi-tenant isolation. A sequence of Scalr Runs shares the same container and data storage. This chart should only be used within a single RBAC perimeter and is unsuitable for untrusted environments.

## Deployment Diagram

<p align="center">
  <img src="assets/deploy-diagram.drawio.svg" />
</p>

## Installing

To install the chart with the release name `scalr-agent`:

```console
$ helm repo add scalr-charts https://scalr.github.io/agent-helm/
$ helm install scalr-agent scalr-charts/agent-local --set agent.token="<agent-token>"
```

_See [configuration](#values) below._

_See [helm install](https://helm.sh/docs/helm/helm_install/) for command documentation._

## Agent Configuration

The Scalr Agent is configured using environment variables, which can be set using the `extraEnv` option in the Helm chart.

```console
$ helm install ...
  --set extraEnv.SCALR_DEBUG=1 \
  --set extraEnv.HTTPS_PROXY="http://myproxy.com:3128"
```

## Customizing Environment

This chart uses the local driver to run tasks directly within the container where the agent operates. Therefore, it requires an image that includes both the Scalr Agent service and the additional tooling provided by the [scalr/runner](https://hub.docker.com/r/scalr/runner) image. As a result, this chart uses the [scalr/agent-runner](https://hub.docker.com/r/scalr/agent-runner) image, which combines the minimal Scalr Agent image ([scalr/agent](https://hub.docker.com/r/scalr/agent)) with the extra tools from `scalr/runner`. You can use this image, or `scalr/agent` (as a minimal base for building your own lightweight images), as a starting point for customizing your environment.

## Volume Configuration

The Scalr Agent uses a data volume for caching run data, configuration versions,
and OpenTofu/Terraform plugins, stored in the directory specified by `dataHome` (default: `/var/lib/scalr-agent`).
This directory is mounted to a volume defined in the `persistence` section. Since the data volume is used for temporary files and caching, both ephemeral and persistent storage are suitable for production. However, persistent storage avoids re-downloading providers and binaries on pod restarts and positively impacts Run Stage initialization times.

### Storage Options

- **`emptyDir`**: Ephemeral storage is enabled by default. Data is lost on pod restarts, requiring providers and binaries to be re-downloaded each time.
- **`persistentVolumeClaim` (PVC)**: Persistent storage suitable for retaining cache across restarts or sharing it between different Scalr Agent replicas. Supports both dynamic PVC creation and use of existing PVCs.

The volume is mounted at `dataHome`, which must be readable, writable, and executable for OpenTofu/Terraform plugin execution.

### Configuration Examples

#### Single Replica with Persistent Storage

Use `ReadWriteOnce` for single-replica deployments (`replicaCount: 1`):

```yaml
persistence:
  enabled: true
  persistentVolumeClaim:
    storageClassName: gp2
    storage: 10Gi
    accessMode: ReadWriteOnce
```

#### Multi-Replica with Shared Storage

For multiple replicas (`replicaCount: >1`) in clusters with `ReadWriteMany` support (e.g., NFS, AWS EFS), you can optionally use a single shared PVC.

```yaml
persistence:
  enabled: true
  persistentVolumeClaim:
    storageClassName: nfs
    storage: 10Gi
    accessMode: ReadWriteMany
```

Using `ReadWriteMany` enables all replicas to access a shared provider and binary cache, preventing each replica from re-downloading providers and binaries and warming up its own cache, as happens with the default ephemeral volume.

You can also use `ReadWriteOnce` in a multi-replica setup, but it limits all replicas to a single node where the PVC is mounted.

#### Use Its Own PVC

If `persistence.enabled` is `true` and `persistentVolumeClaim.claimName` is empty, a PVC is created with the chart's full name (e.g., `{release-name}-agent-local`). To configure an existing PVC, use the `persistentVolumeClaim.claimName` option.

For more details, see the [Kubernetes storage documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).

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

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod scheduling. |
| agent.dataDir | string | `"/var/lib/scalr-agent"` | The directory where the Scalr Agent stores run data, configuration versions, and the OpenTofu/Terraform provider cache. This directory must be readable, writable, and executable to support the execution of OpenTofu/Terraform provider binaries. It is mounted to the volume defined in the persistence section. |
| agent.shutdownMode | string | `"graceful"` | The agent termination behaviour. Can be graceful, force or drain. See https://docs.scalr.io/docs/configuration#scalr_agent_worker_on_stop_action |
| agent.token | string | `""` | The agent pool token. |
| agent.tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| agent.url | string | `""` | The Scalr API endpoint URL. For tokens generated after Scalr version 8.162.0, this value is optional, as the domain can be extracted from the token payload. However, it is recommended to specify the URL explicitly for long-lived services to avoid issues if the account is renamed. |
| extraEnv | object | `{}` | Additional environment variables for Scalr Agent. Use to configure HTTP proxies or other runtime parameters. |
| fullnameOverride | string | `""` | Fully override the resource name for all resources. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. 'IfNotPresent' is efficient for stable deployments. |
| image.repository | string | `"scalr/agent-runner"` | Docker repository for the Scalr Agent image. |
| image.tag | string | `""` | Image tag. Overrides the default (chart appVersion). Leave empty to use chart default. |
| imagePullSecrets | list | `[]` | Image pull secret to use for registry authentication. |
| nameOverride | string | `""` | Override the default resource name prefix for all resources. |
| nodeSelector | object | `{}` | Node selector for scheduling Scalr Agent pods. |
| persistence | object | `{"emptyDir":{"sizeLimit":"20Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteOnce","claimName":"","storage":"20Gi","storageClassName":"","subPath":""}}` | Persistent storage configuration for the Scalr Agent data directory. |
| persistence.emptyDir | object | `{"sizeLimit":"20Gi"}` | Configuration for emptyDir volume (used when persistence.enabled is false). |
| persistence.emptyDir.sizeLimit | string | `"20Gi"` | Size limit for the emptyDir volume. |
| persistence.enabled | bool | `false` | Enable persistent storage. If false, uses emptyDir (ephemeral storage). |
| persistence.persistentVolumeClaim | object | `{"accessMode":"ReadWriteOnce","claimName":"","storage":"20Gi","storageClassName":"","subPath":""}` | Configuration for persistentVolumeClaim (used when persistence.enabled is true). |
| persistence.persistentVolumeClaim.accessMode | string | `"ReadWriteOnce"` | Access mode for the PVC. Use "ReadWriteOnce" for single-replica deployments. Use "ReadWriteMany" only if the Scalr Agent supports shared storage (e.g., with NFS). |
| persistence.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC is created dynamically. |
| persistence.persistentVolumeClaim.storage | string | `"20Gi"` | Storage size for the PVC. |
| persistence.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and require a pre-existing PVC. |
| persistence.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |
| podAnnotations | object | `{}` | Annotations for Scalr Agent pods (e.g., for monitoring or logging). |
| podSecurityContext | object | `{"fsGroup":1000,"runAsNonRoot":true}` | Security context for Scalr Agent pod. |
| replicaCount | int | `1` | Number of replicas for the Scalr Agent deployment. Adjust for high availability. |
| resources | object | `{"limits":{"cpu":"2000m","memory":"2048Mi"},"requests":{"cpu":"1000m","memory":"1024Mi"}}` | Resource limits and requests for Scalr Agent pods. Set identical resource limits and requests to enable Guaranteed QoS and minimize eviction risk. See: https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/#quality-of-service-classes |
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
| terminationGracePeriodSeconds | int | `360` | Termination grace period (in seconds) for pod shutdown. |
| tolerations | list | `[]` | Tolerations for scheduling pods on tainted nodes. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
