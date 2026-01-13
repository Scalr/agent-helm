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

- [agent-local](./charts/agent-local) – Deploys a static number of agents and executes runs in shared agent pods. **This is the recommended default option.**
- [agent-k8s](./charts/agent-k8s) – Deploys an agent controller with a set of agent workers and executes runs in isolated pods. Suitable for environments with strict multi-tenancy requirements. Requires more complex configuration and a separate node pool.

## Development

- Install [pre-commit](https://pre-commit.com/).
- Install Node.js for building and testing GitHub Actions: [https://nodejs.org/en/download/package-manager](https://nodejs.org/en/download/package-manager)
- Install additional dependencies: `make dev`
- Rebuild documentation from templates using [helm-docs](https://github.com/norwoodj/helm-docs): `make docs`

## Contributing

We'd love to have you contribute! Please refer to our [contribution guidelines](./CONTRIBUTING.md) for details.
