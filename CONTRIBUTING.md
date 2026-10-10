# Contributing Guidelines

Contributions are welcome via GitHub pull requests. This document outlines the process to help get your contribution accepted.

## How to Contribute

1. Fork this repository, develop, and test your changes
1. Submit a pull request

### Technical Requirements

* Must follow [Charts best practices](https://helm.sh/docs/topics/chart_best_practices/)
* Must pass CI jobs for linting and installing changed charts with the [chart-testing](https://github.com/helm/chart-testing) tool
* Variable naming and patterns should strive to be consistent across all charts. If certain options exist in a neighboring chart, they should be added or updated in sync to maintain consistency.
* All Helm variable declarations must be documented, and the documentation must be kept up to date using [helm-docs](https://github.com/norwoodj/helm-docs) via `just docs`.

The chart `version` follow [semver](https://semver.org/).

After [development setup](./README.md#development), run `just test` for the agent-local
Helm rendering tests. They run without a cluster. Filter cases with
`uv run --locked pytest -k statefulset`.

Use `just fmt` to format tests with Ruff and `just lint-tests` to check formatting,
lint, and types with Ruff and ty. `just lint` also lints changed charts.
Install hooks with `pre-commit install` to run these Python checks and verify `uv.lock`.
When changing test dependencies in `pyproject.toml`, run `uv lock` and include the lockfile.

There’s no need to manually change the chart version, as charts are released in sync with agent releases and version bumps are handled by automated workflows. After changes are merged, they may be further validated by internal end-to-end workflows that run before each release. Releases usually occur on a weekly basis.
