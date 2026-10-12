# Testing

Complete [development setup](README.md#development) first. Run commands from the repository root.

## Test kinds

| Test kind | Command | Kubernetes cluster |
| --- | --- | --- |
| [Static testing](#static-testing) | `just lint` | No |
| [Unit testing](#unit-testing) | `just test` | No |
| [Installation and upgrade testing](#installation-and-upgrade-testing) | `just test-install --charts charts/agent-local` | Disposable cluster |

Static and unit checks run as separate pre-commit hooks for relevant changes and on every pull request.
Both must pass in the [CI workflow](.github/workflows/lint-test-chart.yaml).

## Static testing

`just lint` uses chart-testing (`ct`) to validate chart metadata, check YAML formatting,
and run Helm lint. Configuration lives in [.ct/](.ct/). Version-increment checks are disabled
because release automation handles chart versions.

Pre-commit also runs Ruff and ty when Python scripts or their tooling configuration change.
Run these checks directly with:

```console
uv run ruff check
uv run ruff format --check
uv run ty check
```

## Unit testing

`just test` uses helm-unittest to render templates with test values and assert resource fields
and expected validation errors. Tests run without a cluster.

Unit tests live in `charts/*/tests/*_test.yaml`. To run one suite:

```console
helm unittest --strict -f tests/storage_test.yaml charts/agent-local
```

## Installation and upgrade testing

`just test-install` uses `ct install --upgrade` to check Kubernetes resource creation,
pod readiness, and upgrades with the chart's `ci/*-values.yaml` profiles. CI runs these checks in kind.

Upgrade checks cover the target branch's profiles and an in-place upgrade of each current profile.
Workload-kind and storage-mode transitions require separate tests. Deprecated charts are excluded.

These tests use dummy credentials and create and remove releases. The command requires the
`kind-agent-helm-test` context. Create a disposable cluster:

```console
kind create cluster --name agent-helm-test --config .ct/kind.yaml --image kindest/node:v1.37.0
kubectl config use-context kind-agent-helm-test
just test-install --charts charts/agent-local
kind delete cluster --name agent-helm-test
```
