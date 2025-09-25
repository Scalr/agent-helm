# agent-job

![Version: 0.5.59](https://img.shields.io/badge/Version-0.5.59-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.54.0](https://img.shields.io/badge/AppVersion-0.54.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
Uses a controller/worker model. Each run stage is isolated
in Kubernetes containers with specified resource limits.

## Overview

> [!WARNING]
> This chart is in Alpha, and implementation details are subject to change.

The `agent-job` Helm chart deploys a Scalr Agent system that uses a job-based architecture for executing Terraform/OpenTofu infrastructure tasks in Kubernetes. The system consists of two main components: a controller that manages job lifecycle and task jobs that execute the actual infrastructure operations.

When a run is assigned to an agent pool by Scalr, the agent controller will create a new task - Kubernetes Job to handle it. This Job's pod will include the following containers:

- **runner**: The environment where the run is executed, based on the golden `scalr/runner` image.
- **worker**: The Scalr Agent process that supervises task execution, using the `scalr/agent` image.

The runner and worker containers will share a single disk volume, allowing the worker to provision the configuration version, providers, and binaries required by the runner.

### Pros

- Cost-efficient for bursty workloads — e.g., deployments with high number of Runs during short periods and low activity otherwise, as resources allocated on demand for each Scalr Run.
- High multi-tenant isolation, as each Scalr Run always has its own newly provisioned environment.
- Better observability, as each Scalr Run is tied to its own unique Pod.

### Cons

- Requires access to the Kubernetes API to launch new Pods.
- Requires a ReadWriteMany Persistent Volume configuration for provider/binary caching. This type of volume is generally vendor-specific and not widely available across all cloud providers.

## Deployment Diagram

<p align="center">
  <img src="assets/deploy-diagram.drawio.svg" />
</p>

## Installing

To install the chart with the release name `scalr-agent`:

```console
$~ helm repo add scalr-charts https://scalr.github.io/agent-helm/
$~ helm upgrade --install scalr-agent scalr-charts/agent-job --set agent.auth.token="<agent-pool-token>"
```

## Architecture Components

### Controller Component (Kubernetes Deployment)

- **Purpose**: Orchestrates and manages the lifecycle of infrastructure tasks
- **Responsibilities**:
  - Creates and monitors Kubernetes Jobs for task execution
  - Manages communication with the Scalr platform
  - Handles job scheduling and cleanup
- **Deployment**: Single replica Deployment that runs continuously
- **Resource Profile**: Lightweight (100m CPU, 128Mi memory) - primarily orchestration workload

### Task Component (Kubernetes Job)

The task component is deployed as Kubernetes Jobs on-demand, containing two containers working together:

#### Worker Container
- **Purpose**: Task coordination and communication
- **Responsibilities**:
  - Receives task instructions from the controller
  - Coordinates with the runner container
  - Reports task status and results back to the Scalr platform
- **Resource Profile**: Moderate (250m CPU, 256Mi memory) - coordination workload

#### Runner Container
- **Purpose**: Terraform/OpenTofu execution environment
- **Responsibilities**:
  - Executes terraform/tofu plan, apply, and destroy operations
  - Manages provider downloads and caching
  - Handles state file operations
- **Resource Profile**: High (500m CPU, 512Mi memory) - intensive execution workload

This chart uses a custom Kubernetes resource called AgentTask to manage task execution.
You can interact with AgentTask resources using kubectl:

```console
# List all agent tasks
$~ kubectl get atasks

# Describe a specific agent task
$~ kubectl describe atask atask-xxx

# View agent task with short name
$~ kubectl get at
```

### Configuration Inheritance Model

#### Global Configuration (`global.*`)

Settings that apply to every component across the entire chart:
- **Image Registry**: Prepended to all container images
- **Image Pull Secrets**: Used by all pods for private registry access
- **Pod Annotations**: Applied to all pods (merged with component-specific annotations)

#### Agent Configuration (`agent.*`)

Container-level settings shared between agent controller and agent worker containers only:

- **Authentication**: Scalr URL, tokens, credentials
- **Image Defaults**: Base image configuration for agent containers
- **Security Context**: Default security settings for agent containers
- **Environment Variables**: Agent-specific environment (merged with global)

**Note**: The runner container does NOT inherit from `agent.*` as it's a different execution environment.

#### Component-Specific Configuration

##### Controller (`controller.*`)

Pod-level settings for the controller Deployment:

- **Scheduling**: nodeSelector, tolerations, affinity
- **Pod Security**: podSecurityContext
- **Container Overrides**: image, resources, securityContext (inherits from `agent.*` if empty)

##### Task (`task.*`)

Pod-level settings for task Job pods:

- **Scheduling**: nodeSelector, tolerations, affinity for job placement
- **Pod Security**: podSecurityContext
- **Extensibility**: extraVolumes, sidecars
- **Container Configurations**: worker and runner container settings

## Configuration Examples

### Basic Configuration

```yaml
global:
  imageRegistry: "my-registry.com"

agent:
  url: "https://myorgaccount.scalr.op"
  auth:
    token: "my-agent-token"

controller:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi

task:
  nodeSelector:
    workload: "terraform"
  runner:
    resources:
      limits:
        cpu: 8000m
        memory: 4096Mi
```

## Storage and Persistence

### Provider Cache Configuration

To enable [provider cache](https://docs.scalr.io/docs/providers-cache), a `ReadWriteMany` volume can be attached via the `persistence` configuration:

```console
helm upgrade --install scalr-agent scalr-agent-helm/agent-job \
  ...
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.claimName="nfs-disk-pvc"
```

PVCs can be provisioned using AWS EFS, Google Filestore, or similar solutions.

## Security Features

### Restrict Access to VM Metadata Service

The chart includes an optional feature to restrict the pods from accessing the VM metadata service at 169.254.169.254, that is common for both AWS and GCP environments.

To enable it, use the `restrictMetadataService` option:

```console
$~ helm upgrade ... \
    --set restrictMetadataService=true
```

With this option enabled, a Kubernetes NetworkPolicy is applied to the agent pods that denies egress traffic to 169.254.169.254/32, blocking access to the VM metadata service. All other outbound traffic is allowed.

#### Limitations

Ensure that your cluster is using a CNI plugin that supports egress NetworkPolicies. Example: Calico, Cilium, or native GKE NetworkPolicy provider for supported versions.

If your cluster doesn't currently support egress NetworkPolicies, you may need to recreate it with the appropriate settings.

## Troubleshooting and Support

### Debug Logging

If you encounter internal system errors or unexpected behavior, please open a Scalr Support request at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31).

Before doing so, enable debug logs using the `agent.extraEnv.SCALR_AGENT_DEBUG=1` option. Then collect the debug-level application logs covering the time window when the incident occurred, and attach them to your support ticket.

### Collecting Logs

To archive all logs from the Scalr agent namespace in a single bundle, replace the `ns` variable with the name of your Helm release namespace and run:

```shell
ns="scalr-agent"
mkdir -p logs && for pod in $(kubectl get pods -n $ns -o name); do kubectl logs -n $ns $pod > "logs/${pod##*/}.log"; done && zip -r agent-k8s-logs.zip logs && rm -rf logs
```

It's best to pull the logs immediately after an incident, since this command will not retrieve logs from restarted or terminated pods.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.dataDir | string | `"/var/lib/scalr-agent"` | The directory where the Scalr Agent stores run data, configuration versions, and the OpenTofu/Terraform provider cache. This directory must be readable, writable, and executable to support the execution of OpenTofu/Terraform provider binaries. It is mounted to the volume defined in the persistence section. |
| agent.extraEnv | object | `{}` | Additional environment variables for agent containers (merged with global extraEnv). |
| agent.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/agent","tag":""}` | Default image configuration for agent containers (controller and worker). |
| agent.image.pullPolicy | string | `"IfNotPresent"` | The pullPolicy for a container and the tag of the image. |
| agent.image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| agent.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| agent.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":true,"runAsGroup":1001,"runAsNonRoot":true,"runAsUser":1001,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"}}` | Default security context for agent containers (controller and worker). |
| agent.securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation. |
| agent.securityContext.capabilities | object | `{"drop":["ALL"]}` | Restrict container capabilities for security. |
| agent.securityContext.privileged | bool | `false` | Run container in privileged mode. Enable only if required. |
| agent.securityContext.readOnlyRootFilesystem | bool | `true` | Read-only root filesystem for security. |
| agent.securityContext.runAsGroup | int | `1001` | Group ID to run the container as. |
| agent.securityContext.runAsNonRoot | bool | `true` | Run container as non-root user for security. |
| agent.securityContext.runAsUser | int | `1001` | User ID to run the container as. |
| agent.securityContext.seLinuxOptions | object | `{}` | SELinux options. |
| agent.securityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for enhanced security. |
| agent.token | string | `""` | The agent pool token. |
| agent.tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. |
| agent.tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| agent.tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| agent.url | string | `""` | The Scalr url. |
| controller.affinity | object | `{}` | Kubernetes Node Affinity for the controller agent. |
| controller.extraEnv | object | `{}` | Additional environment variables for controller container (merged with agent.extraEnv and global.extraEnv). |
| controller.image | object | `{"pullPolicy":"","repository":"","tag":""}` | Controller container image settings (inherits from agent.image if empty). |
| controller.image.pullPolicy | string | `""` | The pullPolicy for a container and the tag of the image. |
| controller.image.repository | string | `""` | Docker repository for the Scalr Agent controller image. |
| controller.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| controller.nodeSelector | object | `{}` | Kubernetes Node Selector for assigning controller agent to specific nodes in the cluster. Example: `--set controller.nodeSelector."cloud\\.google\\.com\\/gke-nodepool"="scalr-agent-controller-pool"` |
| controller.podAnnotations | object | `{}` | Controller specific pod annotations (merged with global podAnnotations, overrides duplicate keys). |
| controller.podSecurityContext | object | `{"fsGroup":1001,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":1001,"runAsNonRoot":true,"runAsUser":1001,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"},"supplementalGroups":[],"sysctls":[]}` | Security context for controller pod. |
| controller.podSecurityContext.fsGroup | int | `1001` | File system group for volume ownership. |
| controller.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` | Ensure non-root filesystem group. |
| controller.podSecurityContext.runAsGroup | int | `1001` | Group ID for all containers in the pod. |
| controller.podSecurityContext.runAsNonRoot | bool | `true` | Run pod as non-root for security. |
| controller.podSecurityContext.runAsUser | int | `1001` | User ID for all containers in the pod. |
| controller.podSecurityContext.seLinuxOptions | object | `{}` | SELinux options. |
| controller.podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for enhanced security. |
| controller.podSecurityContext.supplementalGroups | list | `[]` | Supplemental groups for the containers. |
| controller.podSecurityContext.sysctls | list | `[]` | Sysctls for the pod. |
| controller.resources | object | `{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Resource limits and requests for controller container. |
| controller.securityContext | object | `{}` | Security context for controller container (inherits from agent.securityContext if empty). |
| controller.terminationGracePeriodSeconds | int | `360` | Provides the amount of grace time prior to the controller container being forcibly terminated when marked for deletion or restarted. |
| controller.tolerations | list | `[]` | Kubernetes Node Tolerations for the controller agent. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set controller.tolerations[0].operator=Equal,controller.tolerations[0].effect=NoSchedule,controller.tolerations[0].key=dedicated,controller.tolerations[0].value=scalr-agent-controller-pool` |
| fullnameOverride | string | `""` | Override the full name of resources (takes precedence over nameOverride). |
| global.imagePullSecrets | list | `[]` | Global image pull secrets for private registries. |
| global.imageRegistry | string | `""` | Global Docker registry to prepend to all image repositories. |
| global.podAnnotations | object | `{}` | Global pod annotations applied to all pods. |
| nameOverride | string | `""` | Override the chart name portion of resource names. |
| persistence | object | `{"emptyDir":{"sizeLimit":"20Gi"},"enabled":false,"persistentVolumeClaim":{"accessMode":"ReadWriteMany","claimName":"","storage":"20Gi","storageClassName":"","subPath":""}}` | Persistent storage configuration for the Scalr Agent data directory. |
| persistence.emptyDir | object | `{"sizeLimit":"20Gi"}` | Configuration for emptyDir volume (used when persistence.enabled is false). |
| persistence.emptyDir.sizeLimit | string | `"20Gi"` | Size limit for the emptyDir volume. |
| persistence.enabled | bool | `false` | Enable persistent storage. If false, uses emptyDir (ephemeral storage). |
| persistence.persistentVolumeClaim | object | `{"accessMode":"ReadWriteMany","claimName":"","storage":"20Gi","storageClassName":"","subPath":""}` | Configuration for persistentVolumeClaim (used when persistence.enabled is true). |
| persistence.persistentVolumeClaim.accessMode | string | `"ReadWriteMany"` | Access mode for the PVC. The NFS disk is expected here, so ReadWriteMany is a default. |
| persistence.persistentVolumeClaim.claimName | string | `""` | Name of an existing PVC. If empty, a new PVC is created dynamically. |
| persistence.persistentVolumeClaim.storage | string | `"20Gi"` | Storage size for the PVC. |
| persistence.persistentVolumeClaim.storageClassName | string | `""` | Storage class for the PVC. Leave empty to use the cluster's default storage class. Set to "-" to disable dynamic provisioning and require a pre-existing PVC. |
| persistence.persistentVolumeClaim.subPath | string | `""` | Optional subPath for mounting a specific subdirectory of the volume. |
| restrictMetadataService | bool | `false` | Apply NetworkPolicy to an agent pod that denies access to VM metadata service address (169.254.169.254) |
| serviceAccount.annotations | object | `{}` | Annotations for the service account. |
| serviceAccount.automountToken | bool | `true` | Whether to automount the service account token in the Scalr Agent pod. |
| serviceAccount.create | bool | `true` | Create a Kubernetes service account for the Scalr Agent. |
| serviceAccount.labels | object | `{}` | Additional labels for the service account. |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and 'create' is true. |
| serviceAccount.tokenTTL | int | `3600` | The token expiration period. |
| task.affinity | object | `{}` | Kubernetes Node Affinity for the task job pods. |
| task.extraVolumes | list | `[]` | Additional volumes for the task pod. |
| task.job | object | `{"backoffLimit":0,"ttlSecondsAfterFinished":60}` | Job configuration for task execution. |
| task.job.backoffLimit | int | `0` | Number of retries before marking the job as failed. |
| task.job.ttlSecondsAfterFinished | int | `60` | Time in seconds after job completion before it's automatically deleted. |
| task.nodeSelector | object | `{}` | Kubernetes Node Selector for assigning task jobs to specific nodes in the cluster. The selector must match a node's labels for the pod to be scheduled on that node. |
| task.podAnnotations | object | `{}` | Task specific pod annotations (merged with global podAnnotations, overrides duplicate keys). |
| task.podSecurityContext | object | `{"fsGroup":1001,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":1001,"runAsNonRoot":true,"runAsUser":1001,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"},"supplementalGroups":[],"sysctls":[]}` | Security context for task job pod. |
| task.podSecurityContext.fsGroup | int | `1001` | File system group for volume ownership. |
| task.podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` | Ensure non-root filesystem group. |
| task.podSecurityContext.runAsGroup | int | `1001` | Group ID for all containers in the pod. |
| task.podSecurityContext.runAsNonRoot | bool | `true` | Run pod as non-root for security. |
| task.podSecurityContext.runAsUser | int | `1001` | User ID for all containers in the pod. |
| task.podSecurityContext.seLinuxOptions | object | `{}` | SELinux options. |
| task.podSecurityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for enhanced security. |
| task.podSecurityContext.supplementalGroups | list | `[]` | Supplemental groups for the containers. |
| task.podSecurityContext.sysctls | list | `[]` | Sysctls for the pod. |
| task.runner | object | `{"extraEnv":{},"extraVolumeMounts":[],"image":{"pullPolicy":"IfNotPresent","repository":"scalr/agent-runner","tag":""},"resources":{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":false,"runAsGroup":1001,"runAsNonRoot":true,"runAsUser":1001,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"}}}` | Runner environment container configuration where Terraform/OpenTofu commands are executed. |
| task.runner.extraEnv | object | `{}` | Additional environment variables for runner container (merged with global.extraEnv only, no agent inheritance). |
| task.runner.extraVolumeMounts | list | `[]` | Additional volume mounts for the runner container. |
| task.runner.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/agent-runner","tag":""}` | Runner container image settings. |
| task.runner.image.pullPolicy | string | `"IfNotPresent"` | The pullPolicy for a container and the tag of the image. |
| task.runner.image.repository | string | `"scalr/agent-runner"` | Docker repository for the Scalr Agent runner image. |
| task.runner.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| task.runner.resources | object | `{"limits":{"cpu":"4000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"512Mi"}}` | Resource limits and requests for runner container (independent configuration, no inheritance). For the system agent controller, this will be overridden with presets from the billing resource tier. |
| task.runner.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"privileged":false,"readOnlyRootFilesystem":false,"runAsGroup":1001,"runAsNonRoot":true,"runAsUser":1001,"seLinuxOptions":{},"seccompProfile":{"type":"RuntimeDefault"}}` | Security context for runner container (independent configuration, no inheritance). |
| task.runner.securityContext.allowPrivilegeEscalation | bool | `false` | Allow privilege escalation. |
| task.runner.securityContext.capabilities | object | `{"drop":["ALL"]}` | Restrict container capabilities for security. |
| task.runner.securityContext.privileged | bool | `false` | Run container in privileged mode. Only enable if Terraform providers require it. |
| task.runner.securityContext.readOnlyRootFilesystem | bool | `false` | Read-only root filesystem. May need to be false for Terraform cache and temp files. |
| task.runner.securityContext.runAsGroup | int | `1001` | Group ID to run the container as. |
| task.runner.securityContext.runAsNonRoot | bool | `true` | Run container as non-root user for security. |
| task.runner.securityContext.runAsUser | int | `1001` | User ID to run the container as. |
| task.runner.securityContext.seLinuxOptions | object | `{}` | SELinux options. |
| task.runner.securityContext.seccompProfile | object | `{"type":"RuntimeDefault"}` | Seccomp profile for enhanced security. |
| task.sidecars | list | `[]` | Additional sidecar containers for the task pod. |
| task.terminationGracePeriodSeconds | int | `360` | Provides the amount of grace time prior to the task job containers being forcibly terminated when marked for deletion or restarted. |
| task.tolerations | list | `[]` | Kubernetes Node Tolerations for the task job pods. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set task.tolerations[0].operator=Equal,task.tolerations[0].effect=NoSchedule,task.tolerations[0].key=dedicated,task.tolerations[0].value=scalr-agent-worker-pool` |
| task.worker | object | `{"extraEnv":{},"extraVolumeMounts":[],"image":{"pullPolicy":"","repository":"","tag":""},"resources":{"limits":{"cpu":"2000m","memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}},"securityContext":{}}` | Worker agent container configuration. |
| task.worker.extraEnv | object | `{}` | Additional environment variables for worker container (merged with agent.extraEnv and global.extraEnv). |
| task.worker.extraVolumeMounts | list | `[]` | Additional volume mounts for the worker container. |
| task.worker.image | object | `{"pullPolicy":"","repository":"","tag":""}` | Worker container image settings (inherits from agent.image if empty). |
| task.worker.image.pullPolicy | string | `""` | The pullPolicy for a container and the tag of the image. |
| task.worker.image.repository | string | `""` | Docker repository for the Scalr Agent worker image. |
| task.worker.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| task.worker.resources | object | `{"limits":{"cpu":"2000m","memory":"1024Mi"},"requests":{"cpu":"250m","memory":"256Mi"}}` | Resource limits and requests for worker container. |
| task.worker.securityContext | object | `{}` | Security context for worker container (inherits from agent.securityContext if empty). |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
