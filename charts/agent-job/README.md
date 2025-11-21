# agent-job

![Version: 0.5.63](https://img.shields.io/badge/Version-0.5.63-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.56.0](https://img.shields.io/badge/AppVersion-0.56.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
Uses a controller/worker model. Each run stage is isolated
in Kubernetes containers with specified resource limits.

## Overview

> [!WARNING]
> This charts is in Alpha, and implementation details are subject to change.

The Agent deploys as two components: a controller and a worker. The controller
consumes jobs from Scalr and schedules pods, while the worker supervises the jobs.

When a run is assigned to an agent pool by Scalr, the agent controller will create a new Kubernetes Job to handle it. This Job will include the following containers:

- runner: The environment where the run is executed, based on the golden `scalr/runner` image.
- worker: The Scalr Agent process that supervises task execution, using the `scalr/agent` image.
The runner and worker containers will share a single disk volume, allowing the worker to provision the configuration version, providers, and binaries required by the runner.

This chart aims to provide a more cloud-native deployment compared to [agent-k8s](/charts/agent-k8s/) by removing hostPath, simplifying maintenance through the elimination of DaemonSet-based persistent workers, and improving robustness with individual, fully isolated, stateless per-run workers.

It also improves customizability of the run environment, since the job template is managed via the Helm chart rather than being built programmatically, giving users full access to customize it — for example, by injecting sidecar containers.

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
$ helm repo add scalr-charts https://scalr.github.io/agent-helm/
$ helm upgrade --install scalr-agent scalr-charts/agent-job --set agent.token="<agent-pool-token>"
```

## Restrict Access to VM Metadata Service

The chart includes an optional feature to restrict the pods from accessing the VM metadata service at 169.254.169.254, that is common for both AWS and GCP environments.

To enable it, use the `restrictMetadataService` option:

```console
$ helm upgrade ... \
    --set restrictMetadataService=true
```

With this option enabled, a Kubernetes NetworkPolicy is applied to the agent pods that denies egress traffic to 169.254.169.254/32, blocking access to the VM metadata service. All other outbound traffic is allowed.

### Troubleshooting

If you encounter internal system errors or unexpected behavior, please open a Scalr Support request at [Scalr Support Center](https://scalr-labs.atlassian.net/servicedesk/customer/portal/31).

Before doing so, enable debug logs using the `agent.debug` option. Then collect the debug-level application logs covering the time window when the incident occurred, and attach them to your support ticket.

This chart uses a controller-worker model with one controller pod and zero or more worker pods. Be sure to include logs from at least the controller pod and any affected worker pods.

To archive all logs from the Scalr agent namespace in a single bundle, replace the `ns` variable with the name of your Helm release namespace and run:

```shell
ns="scalr-agent"
mkdir -p logs && for pod in $(kubectl get pods -n $ns -o name); do kubectl logs -n $ns $pod > "logs/${pod##*/}.log"; done && zip -r agent-k8s-logs.zip logs && rm -rf logs
```

It's best to pull the logs immediately after an incident, since this command will not retrieve logs from restarted or terminated pods.

### Limitations

Ensure that your cluster is using a CNI plugin that supports egress NetworkPolicies. Example: Calico, Cilium, or native GKE NetworkPolicy provider for supported versions.

If your cluster doesn't currently support egress NetworkPolicies, you may need to recreate it with the appropriate settings.

### Disk

To enable [provider cache](https://docs.scalr.io/docs/providers-cache), a `ReadWriteMany` volume can be attached via the `persistence` configuration:

```console
helm upgrade --install scalr-agent scalr-agent-helm/agent-job \
  ...
  --set persistence.enabled=true \
  --set persistence.persistentVolumeClaim.claimName="nfs-disk-pvc"
```

PVCs can be provisioned using AWS EFS, Google Filestore, or similar solutions.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.dataDir | string | `"/var/lib/scalr-agent"` | The directory where the Scalr Agent stores run data, configuration versions, and the OpenTofu/Terraform provider cache. This directory must be readable, writable, and executable to support the execution of OpenTofu/Terraform provider binaries. It is mounted to the volume defined in the persistence section. |
| agent.token | string | `""` | The agent pool token. |
| agent.tokenExistingSecret | string | `""` | The name of the secret containing the agent pool token. Secret is created if left empty. |
| agent.tokenExistingSecretKey | string | `"token"` | The key of the secret containing the agent pool token. |
| agent.url | string | `""` | The Scalr url. |
| controller.image.pullPolicy | string | `"IfNotPresent"` | The pullPolicy for a container and the tag of the image. |
| controller.image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| controller.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| controllerNodeSelector | object | `{}` | Kubernetes Node Selector for assigning controller agent to specific node in the cluster. Example: `--set controllerNodeSelector."cloud\\.google\\.com\\/gke-nodepool"="scalr-agent-controller-pool"` |
| controllerPodAnnotations | object | `{}` | Controller specific pod annotations (merged with podAnnotations, overrides duplicate keys) |
| controllerTolerations | list | `[]` | Kubernetes Node Selector for assigning worker agents and scheduling agent tasks to specific nodes in the cluster. The selector must match a node's labels for the pod to be scheduled on that node. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set controllerTolerations[0].operator=Equal,controllerTolerations[0].effect=NoSchedule,controllerTolerations[0].key=dedicated,controllerTolerations[0].value=scalr-agent-controller-pool` |
| efsMountOptions | list | `["acregmin=1","acregmax=3","acdirmin=1","acdirmax=3"]` | Amazon EFS mount options to define how the EFS storage volume should be mounted. |
| efsVolumeHandle | string | `""` | Amazon EFS file system ID to use EFS storage as data home directory. |
| extraEnv | object | `{}` |  |
| fullnameOverride | string | `""` | Override the full name of resources (takes precedence over nameOverride). |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries. |
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
| podAnnotations | object | `{}` | The Agent Pods annotations. |
| podSecurityContext | object | `{"fsGroup":0,"runAsNonRoot":false}` | Security context for Scalr Agent pod. |
| resources.limits.cpu | string | `"2000m"` |  |
| resources.limits.memory | string | `"1024Mi"` |  |
| resources.requests.cpu | string | `"250m"` |  |
| resources.requests.memory | string | `"256Mi"` |  |
| restrictMetadataService | bool | `false` | Apply NetworkPolicy to an agent pod that denies access to VM metadata service address (169.254.169.254) |
| securityContext | object | `{"capabilities":{"drop":["ALL"]},"privileged":false,"procMount":"Default","runAsGroup":0,"runAsNonRoot":false,"runAsUser":0}` | Security context for Scalr Agent container. |
| securityContext.capabilities | object | `{"drop":["ALL"]}` | Restrict container capabilities for security. |
| securityContext.privileged | bool | `false` | Run container in privileged mode. Enable only if required. |
| securityContext.procMount | string | `"Default"` | Proc mount type. Valid values: Default, Unmasked, Host. |
| serviceAccount.annotations | object | `{}` | Annotations for the service account. |
| serviceAccount.automountToken | bool | `true` | Whether to automount the service account token in the Scalr Agent pod. |
| serviceAccount.create | bool | `true` | Create a Kubernetes service account for the Scalr Agent. |
| serviceAccount.labels | object | `{}` | Additional labels for the service account. |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and 'create' is true. |
| serviceAccount.tokenTTL | int | `3600` | The token expiration period. |
| terminationGracePeriodSeconds | int | `360` | Provides the amount of grace time prior to the agent-k8s container being forcibly terminated when marked for deletion or restarted. |
| worker.image.pullPolicy | string | `"IfNotPresent"` | The pullPolicy for a container and the tag of the image. |
| worker.image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| worker.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| worker.runner.image.pullPolicy | string | `"IfNotPresent"` | The pullPolicy for a container and the tag of the image. |
| worker.runner.image.repository | string | `"scalr/agent-runner"` | Docker repository for the Scalr Agent runner image. |
| worker.runner.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| workerNodeSelector | object | `{}` | Kubernetes Node Selector for the agent worker and the agent task pods. Example: `--set workerNodeSelector."cloud\\.google\\.com\\/gke-nodepool"="scalr-agent-worker-pool"` |
| workerPodAnnotations | object | `{}` | Worker specific pod annotations (merged with podAnnotations, overrides duplicate keys) |
| workerTolerations | list | `[]` | Kubernetes Node Tolerations for the agent worker and the agent task pods. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set workerTolerations[0].operator=Equal,workerTolerations[0].effect=NoSchedule,workerTolerations[0].key=dedicated,workerTolerations[0].value=scalr-agent-worker-pool` |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.11.0](https://github.com/norwoodj/helm-docs/releases/v1.11.0)
