# Agent Helm Chart

## Installing the Chart

Before you can install the chart you will need to add the `scalr-agent` repo to [Helm](https://helm.sh/).

```shell
helm repo add scalr-agent https://scalr.github.io/agent-helm/
```

After you've installed the repo you can install the chart.

```shell
helm upgrade --install scalr-agent scalr-agent/scalr-agent --set agent.url=... --set agent.token=... 
```

## Release

Bump the version in [Chart.yaml](./charts/scalr-agent/Chart.yaml), commit and push.
**NOTE: do not create a tag yourself!**

Our release workflow will then using [Helm chart releaser action](https://github.com/helm/chart-releaser-action)

* create a tag `scalr-agent-<version>`
* create a [release](https://github.com/Scalr/agent-helm/releases) associated with the new tag
* commit an updated index.yaml with the new release
* redeploy the GitHub pages to serve the new index.yaml

Note: there might be a slight delay between the release and the `index.yaml`
file being updated as GitHub pages have to be re-deployed.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules to control how the Scalr Agent pods are scheduled on nodes |
| agent.image | object | `{"pullPolicy":"IfNotPresent","repository":"scalr/agent","tag":"0.1.30"}` | Docker image configuration for Scalr Agent |
| agent.token | string | `nil` | A value for agent.token must be provided for Scalr Agent authentication |
| agent.url | string | `nil` | A value for agent.url must be provided to specify the Scalr API endpoint |
| docker | object | `{"image":{"pullPolicy":"IfNotPresent","repository":"docker","tag":"20.10.23-dind"}}` | Docker configuration for running Docker-in-Docker containers |
| fullnameOverride | string | `""` | String to fully override the name used in resources |
| imagePullSecrets | list | `[]` | List of secrets for pulling images from private registries |
| nameOverride | string | `""` | String to partially override the name used in resources |
| nodeSelector | object | `{}` | NodeSelector for specifying which nodes the Scalr Agent pods should be deployed on |
| podAnnotations | object | `{}` | Additional annotations to be added to the Scalr Agent pods |
| podSecurityContext | object | `{}` | Pod security context for the Scalr Agent deployment |
| replicaCount | int | `1` | Number of replicas for the Scalr Agent deployment |
| resources | object | `{"limits":{"memory":"2048Mi"},"requests":{"cpu":"500m","memory":"2048Mi"}}` | Resource limits and requests for the Scalr Agent containers |
| securityContext | object | `{"privileged":true,"procMount":"Default"}` | Security context for the Scalr Agent containers |
| serviceAccount | object | `{"annotations":{},"create":true,"name":""}` | ServiceAccount configuration for Scalr Agent |
| tolerations | list | `[]` | Tolerations for the Scalr Agent pods, allowing them to run on tainted nodes |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.11.0](https://github.com/norwoodj/helm-docs/releases/v1.11.0)


## TODO
- Pre-commit hooks(lint, docs)
- Autogenerated Values section
