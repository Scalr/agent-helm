# Agent Helm Chart

## Installing the Chart

Before you can install the chart you will need to add the `scalr-agent` repo to [Helm](https://helm.sh/).

```shell
helm repo add scalr-agent https://scalr.github.io/agent-helm
```

After you've installed the repo you can install the chart.

```shell
helm upgrade --install scalr-agent scalr-agent/scalr-agent --set agent.url=... --set agent.token=... 
```

## Configuration

Required values:

```yaml
agent:
  token: ...
  url: ...
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