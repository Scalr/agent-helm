# agent-k8s

![Version: 0.5.6](https://img.shields.io/badge/Version-0.5.6-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.13.0](https://img.shields.io/badge/AppVersion-0.13.0-informational?style=flat-square)

A Helm chart for the scalr-agent deployment on the Kubernetes cluster,
where runs are executed in Pods in the same cluster.
Run phases are isolated in kubernetes containers with resource limits.

> **Note**
> This new deployment architecture is currently in preview.
> It has many advantages over the [`agent-docker`](/charts/agent-docker) chart and
> would eventually replace it.

## Additional Information

The Agent deploys as two components: a controller and a worker. The controller
consumes jobs from Scalr and schedules pods, while the worker supervises the jobs.

The agent worker is a DaemonSet that scales up/down with the cluster, registering
and deregistering agents from the pool. When an Agent controller receives a job from Scalr,
it schedules a Pod for execution. The Kubernetes workload scheduler assigns the Pod
to a specific Node, where the Agent worker running on that Node oversees the execution
of the job. By enabling the Kubernetes auto-scaler, Terraform workloads can scale
linearly based on the load.

![Agent in Kubernetes deployment diagram](/charts/agent-k8s/assets/agent-k8s-deploy-diagram.jpg)

## Installing the Chart

To install the chart with the release name `scalr-agent`:

```console
$ helm repo add scalr-agent-helm https://scalr.github.io/agent-helm/
$ helm upgrade --install scalr-agent scalr-agent-helm/agent-k8s \
    --set agent.url="https://<account>.scalr.io" \
    --set agent.token="<agent-pool-token>"
```

You can also control the placement of both the controller and the worker on the cluster using the `controllerNodeSelector`
and `workerNodeSelector` options. Here's an example using GKE specific labels:

```console
$ helm upgrade --install scalr-agent scalr-agent-helm/agent-k8s
    --set agent.url="https://<account>.scalr.io" \
    --set agent.token="<agent-pool-token>" \
    --set controllerNodeSelector."kubernetes\\.io\\/hostname"="<node-name>" \
    --set workerNodeSelector."cloud\\.google\\.com\\/gke-nodepool"="<node-pool-name>"
```

To use a separate agent pool for Scalr workloads, you may want to configure [Taint and Tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/).
Set up the taints on the Node Pool, and add tolerations to the agent worker with the `workerTolerations` option. An example:

```console
--set workerTolerations[0].operator=Equal,workerTolerations[0].effect=NoSchedule,workerTolerations[0].key=dedicated,workerTolerations[0].value=scalr-agent-worker-pool
```

## Disk Requirements

Currently, the Agent is not fully cloud-native and utilizes the [hostPath](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
volume for storing a shared Terraform plugin cache and managing configuration version artifacts
for agent task Pods.

The volume is configured via the `agent.data_home` option. The filesystem on this volume must be
writable, executable, and stateful (within the lifecycle of the Scalr Agent Pod).

### Choosing the Data Home Directory

In the default template example, the node disk is utilized at the path `/home/kubernetes/flexvolume/agent-k8s`.
This path is specific to Container-Optimized OS (GKE) and varies depending on the Kubernetes provider in use.

There is also a known [issue](https://github.com/Scalr/agent-helm/pull/32) with the default `agent.data_home` directory, which will be changed in the future.

It is recommended to alter the default directory to `/home/kubernetes/bin/scalr/{unique-name}`.

For EKS (Amazon Linux 2 or Bottlerocket OS), the recommended path is `/var/lib/{unique-name}`.

Using a unique name in the path is necessary when installing multiple agents on the cluster
to prevent collisions. Additionally, it is important to note that the Agent does not delete its
data when uninstalling the chart or modifying the `agent.data_home` option, which may result
in artifacts being left on the node's root disk.

Example of setting `agent.data_home`:

```console
$ helm upgrade ... \
    --set agent.data_home="/var/lib/{unique-name}"
```

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| scalr | <packages@scalr.com> |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| agent.container_task_cpu_limit | float | `8` | CPU resource limit defined in cores. If your container needs two full cores to run, you would put the value 2. If your container only needs ¼ of a core, you would put a value of 0.25 cores. |
| agent.container_task_cpu_request | float | `1` | CPU resource request defined in cores. If your container needs two full cores to run, you would put the value 2. If your container only needs ¼ of a core, you would put a value of 0.25 cores. |
| agent.container_task_mem_limit | int | `16384` | Memory resource limit defined in megabytes. |
| agent.container_task_mem_request | int | `1024` | Memory resource request defined in megabytes. |
| agent.container_task_scheduling_timeout | int | `120` | The container task's (e.g., Kubernetes Pod) scheduling timeout in seconds. The task will be waiting for the scheduling in the queued status; if the cluster does not allocate resources for the container in that timeout, the task will be switched to the errored status. |
| agent.data_home | string | `"/home/kubernetes/flexvolume/agent-k8s"` | The agent working directory on the cluster host node. |
| agent.debug | bool | `false` | Enable debug logs |
| agent.disconnect_on_stop | bool | `true` | Determines if the agent should automatically disconnect from the Scalr agent pool when the service is stopping. |
| agent.gc_plugins_global_size_limit | int | `2560` | Size limit (in megabytes) of the global plugin cache with providers from the public registries. |
| agent.gc_plugins_workspace_size_limit | int | `512` | Size limit (in megabytes) of the workspace plugin cache with providers from the private registries. |
| agent.grace_shutdown_timeout | int | `60` | The timeout in seconds for gracefully shutting down active tasks via the SIGTERM signal. After this timeout, tasks will be terminated with the SIGKILL signal. |
| agent.kubernetes_task_annotations | object | `{}` | Extra annotations to apply to the agent task pods. |
| agent.kubernetes_task_labels | object | `{}` | Extra labels to apply to the agent task pods. |
| agent.log_format | string | `"json"` | The log formatter. Options: "plain" or "dev" or "json". |
| agent.token | string | `""` | The agent pool token. |
| agent.tokenExistingSecret | string | `""` | The name of the secret containing the agent pool token. Secret is created if left empty. |
| agent.url | string | `""` | The Scalr url. |
| agent.worker_drain_timeout | int | `3600` | The timeout for draining worker tasks in seconds. After this timeout, tasks will be terminated via the SIGTERM signal. |
| agent.worker_on_stop_action | string | `"drain"` | Defines the SIGTERM/SIGHUP/SIGINT signal handler's shutdown behavior. Options: "drain" or "grace-shutdown" or "force-shutdown". |
| controllerNodeSelector | object | `{}` | Kubernetes Node Selector for assigning controller agent to specific node in the cluster. |
| controllerTolerations | list | `[]` | Kubernetes Node Selector for assigning worker agents and scheduling agent tasks to specific nodes in the cluster. The selector must match a node's labels for the pod to be scheduled on that node. |
| fullnameOverride | string | `""` |  |
| image.pullPolicy | string | `"Always"` | The pullPolicy for a container and the tag of the image. |
| image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion. |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| podAnnotations | object | `{}` |  |
| resources.limits.cpu | string | `"1000m"` |  |
| resources.limits.memory | string | `"1024Mi"` |  |
| resources.requests.cpu | string | `"250m"` |  |
| resources.requests.memory | string | `"256Mi"` |  |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | If not set and create is true, a name is generated using the fullname template |
| terminationGracePeriodSeconds | int | `3660` | Provides the amount of grace time prior to the agent-k8s container being forcibly terminated when marked for deletion or restarted. |
| workerNodeSelector | object | `{}` | Kubernetes Node Tolerations for the controller. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set controllerTolerations[0].operator=Equal,controllerTolerations[0].effect=NoSchedule,controllerTolerations[0].key=dedicated,controllerTolerations[0].value=scalr-agent-controller-pool` |
| workerTolerations | list | `[]` | Kubernetes Node Tolerations for the agent worker and the agent task pods. Expects input structure as per specification <https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core>. Example: `--set workerTolerations[0].operator=Equal,workerTolerations[0].effect=NoSchedule,workerTolerations[0].key=dedicated,workerTolerations[0].value=scalr-agent-worker-pool` |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.11.0](https://github.com/norwoodj/helm-docs/releases/v1.11.0)
