# Scalr Agent Helm Charts

![GitHub Release](https://img.shields.io/github/v/release/Scalr/agent-helm?filter=agent-k8s*)
![GitHub Release](https://img.shields.io/github/v/release/Scalr/agent-helm?filter=agent-local*)
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

- [agent-local](./charts/agent-local) – Runs a fixed number of agents in shared pods. Recommended for Run agent pools and the only option for VCS agent pools.
- [agent-job](./charts/agent-job) – Deploys an agent controller and executes runs in isolated stateless jobs. Suitable for environments with strict multi-tenancy requirements.
- [agent-k8s](./charts/agent-k8s) – Deploys an agent controller with stateful workers and executes runs in isolated pods. Suitable for environments with strict multi-tenancy requirements. Requires more complex configuration and a separate node pool.

## Development

### Requirements

Install these tools using their installation guides or your package manager:

- [just](https://just.systems/man/en/packages.html) >= 1.23 for development commands.
- [Helm 4](https://helm.sh/docs/intro/install/) for chart tests.
- [chart-testing](https://github.com/helm/chart-testing#installation) (`ct`) >= 3.15.0 for chart linting and installation tests.
- [helm-docs](https://github.com/norwoodj/helm-docs#installation) >= 1.14 for generated documentation.
- [pre-commit](https://pre-commit.com/#install) and [lychee](https://github.com/lycheeverse/lychee#installation) for Git hooks and link checks.
- [uv](https://docs.astral.sh/uv/getting-started/installation/) >= 0.13 for Python 3.15 scripts.

Pre-commit installs the Python tools used by chart-testing.

For local installation tests, also install [Docker](https://docs.docker.com/get-started/get-docker/),
[kind](https://kind.sigs.k8s.io/docs/user/quick-start/), and [kubectl](https://kubernetes.io/docs/tasks/tools/).
See [Testing](./TESTING.md#installation-and-upgrade-testing) for cluster setup.

Editing the custom GitHub Action also requires [Node.js and npm](https://nodejs.org/en/download).
See [GitHub Actions development](./CONTRIBUTING.md#github-actions-development) for setup.

### Setup

Install the same [helm-unittest](https://github.com/helm-unittest/helm-unittest#install) release as CI, then enable Git hooks:

```console
helm plugin install https://github.com/helm-unittest/helm-unittest/releases/download/v1.2.1/unittest-1.2.1.tgz --verify=false
pre-commit install
```

Run `just` to list available commands. See [Testing](./TESTING.md) and
[Documentation](./CONTRIBUTING.md#documentation) for the checks to run for your changes.

## Contributing

We'd love to have you contribute! Please refer to our [contribution guidelines](./CONTRIBUTING.md) for details.
