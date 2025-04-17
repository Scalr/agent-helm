# Scalr Agent Helm Charts

![GitHub Release](https://img.shields.io/github/v/release/Scalr/agent-helm?filter=agent-k8s*)
![GitHub Release](https://img.shields.io/github/v/release/Scalr/agent-helm?filter=agent-local*)
![GitHub Release](https://img.shields.io/github/v/release/Scalr/agent-helm?filter=agent-docker*)
![Docker Image Version](https://img.shields.io/docker/v/scalr/agent)
![GitHub Downloads (all assets, all releases)](https://img.shields.io/github/downloads/Scalr/agent-helm/total)

This repository contains Helm charts for the [Scalr Agent](https://docs.scalr.io/docs/self-hosted-agents-pools).

## Usage

[Helm](https://helm.sh) must be installed to use the charts.
Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

Once Helm is set up properly, add the repo as follows:

```console
helm repo add scalr-agent-helm https://scalr.github.io/agent-helm/
```

You can then run `helm search repo scalr-agent-helm` to see the charts.

## Charts

This repository contains multiple charts for different deployment types and use cases.

- [agent-local](./charts/agent-local) – Uses the `local` driver. Best suited for simple deployments and VCS agents.
- [agent-k8s](./charts/agent-k8s) – Uses the `kubernetes` driver with a controller/worker mode. Best suited for large-scale deployments and environments with strict multi-tenancy requirements. Requires more complex configuration and a separate node pool.
- [agent-docker](./charts/agent-docker) – Uses the `docker` driver with a Docker-in-Docker sidecar container. Originally built to run the Docker-based Agent on Kubernetes due to the lack of native Kubernetes support. It has been retained due to adoption challenges with the native agent-k8s chart, we recommend using the newer agent-local chart for new installations instead of agent-docker.

## Development

* Install [pre-commit](https://pre-commit.com/).
* Install Node.js for building and testing GitHub Actions: [https://nodejs.org/en/download/package-manager](https://nodejs.org/en/download/package-manager)
* Install additional dependencies: `make dev`
* Rebuild documentation from templates using [helm-docs](https://github.com/norwoodj/helm-docs): `make docs`

## Contributing

We'd love to have you contribute! Please refer to our [contribution guidelines](./CONTRIBUTING.md) for details.
