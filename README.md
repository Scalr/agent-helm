# Scalr Agent Helm Charts

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

Once Helm is set up properly, add the repo as follows:

```console
helm repo add scalr-agent-helm https://scalr.github.io/agent-helm/
```

You can then run `helm search repo scalr-agent-helm` to see the charts.

## Releasing

Bump the version in `Chart.yaml`, commit and push.

> **Warning**
> do not create a tag yourself!

GitHub Action release workflow will then using [Helm chart releaser](https://github.com/helm/chart-releaser-action)

* create a tag `<chart-name>-<version>`
* create a [release](https://github.com/Scalr/agent-helm/releases) associated with the new tag
* commit an updated index.yaml with the new release
* redeploy the GitHub pages to serve the new index.yaml

> **Note**
> there might be a slight delay between the release and the `index.yaml` update, as GitHub pages have to be re-deployed.


## TODO
- Pre-commit hooks(lint, docs)
