# agent-local

![Version: 0.5.40](https://img.shields.io/badge/Version-0.5.40-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.42.0](https://img.shields.io/badge/AppVersion-0.42.0-informational?style=flat-square)

A Helm chart for deploying the Scalr Agent on a Kubernetes cluster.
Best suited for simple deployments and VCS agents.

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

## Deployment Diagram

<p align="center">
  <img src="assets/deploy-diagram.drawio.svg" />
</p>

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
| extraEnv | list | `[]` | Additional environment variables for Scalr Agent containers. Use to configure proxies or other runtime parameters. See: https://docs.scalr.io/docs/self-hosted-agents-pools#docker--vm-deployments |
| fullnameOverride | string | `""` | Fully override the resource name for all resources. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. 'IfNotPresent' is efficient for stable deployments. |
| image.repository | string | `"scalr/agent"` | Docker repository for the Scalr Agent image. |
| image.tag | string | `""` | Image tag. Overrides the default (chart appVersion). Leave empty to use chart default. |
| imagePullSecrets | list | `[]` | List of Kubernetes secrets for pulling images from private registries. |
| nameOverride | string | `""` | Override the default resource name prefix for all resources. |
| nodeSelector | object | `{}` | Node selector for scheduling Scalr Agent pods. |
| podAnnotations | object | `{}` | Annotations for Scalr Agent pods (e.g., for monitoring or logging). |
| podSecurityContext | object | `{"fsGroup":1000,"runAsNonRoot":true}` | Pod security context for Scalr Agent pods. |
| replicaCount | int | `1` | Number of replicas for the Scalr Agent deployment. Adjust for high availability. |
| resources | object | `{"limits":{"cpu":"1000m","memory":"2048Mi"},"requests":{"cpu":"500m","memory":"1024Mi"}}` | Resource limits and requests for Scalr Agent pods. |
| secret | object | `{"annotations":{},"labels":{}}` | Secret configuration for storing the Scalr Agent token. |
| secret.annotations | object | `{}` | Annotations for the Secret resource. |
| secret.labels | object | `{}` | Additional labels for the Secret resource. |
| securityContext.capabilities | object | `{"drop":["ALL"]}` | Restrict container capabilities for security. |
| securityContext.privileged | bool | `false` | Run container in privileged mode. Enable only if required. |
| securityContext.procMount | string | `"Default"` | Proc mount type. Valid values: Default, Unmasked, Host. |
| securityContext.runAsGroup | int | `1000` |  |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `1000` |  |
| serviceAccount.annotations | object | `{}` | Annotations for the service account. |
| serviceAccount.create | bool | `false` | Create a Kubernetes service account for the Scalr Agent. |
| serviceAccount.labels | object | `{}` | Additional labels for the service account. |
| serviceAccount.name | string | `""` | Name of the service account. Generated if not set and 'create' is true. |
| strategy | object | `{"rollingUpdate":{"maxSurge":"25%","maxUnavailable":"50%"},"type":"RollingUpdate"}` | Deployment strategy configuration. |
| strategy.rollingUpdate | object | `{"maxSurge":"25%","maxUnavailable":"50%"}` | Rolling update parameters. |
| strategy.rollingUpdate.maxSurge | string | `"25%"` | Maximum number of pods that can be created above the desired number during an update. |
| strategy.rollingUpdate.maxUnavailable | string | `"50%"` | Maximum number of pods that can be unavailable during an update. |
| strategy.type | string | `"RollingUpdate"` | Type of deployment strategy. Options: RollingUpdate, Recreate. |
| terminationGracePeriodSeconds | int | `360` | Termination grace period (in seconds) for pod shutdown. |
| token | string | `""` | Scalr Agent authentication token (required unless tokenExistingSecret is used). |
| tokenExistingSecret | object | `{"key":"token","name":""}` | Pre-existing Kubernetes secret for the Scalr Agent token. |
| tokenExistingSecret.key | string | `"token"` | Key within the secret that holds the token value. |
| tokenExistingSecret.name | string | `""` | Name of the secret containing the token. |
| tolerations | list | `[]` | Tolerations for scheduling pods on tainted nodes. |
| url | string | `""` | Scalr API endpoint URL (required). |
| volume | object | `{"emptyDir":{"sizeLimit":"2Gi"}}` | Volume configuration for Scalr Agent data. |
| volume.emptyDir | object | `{"sizeLimit":"2Gi"}` | Use an emptyDir volume for data storage. Can be replaced with persistentVolumeClaim. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
