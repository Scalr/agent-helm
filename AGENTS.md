# Scalr Agent Helm Charts

Helm charts for deploying self-hosted Scalr agents on Kubernetes.

## Commands

Install tools from [Development requirements](README.md#requirements). Run commands from the repository root.

| Command | Purpose |
| --- | --- |
| `just lint` | Lint charts with chart-testing through pre-commit |
| `just test` | Run helm-unittest suites |
| `just test-install --charts charts/agent-local` | Test installation and upgrades in a disposable cluster |
| `just docs` | Regenerate chart READMEs with helm-docs |
| `just lychee` | Check local Markdown links and anchors offline |

Run one unit test suite:

```console
helm unittest --strict -f tests/storage_test.yaml charts/agent-local
```

See [Testing](TESTING.md#installation-and-upgrade-testing) for cluster setup.

## Architecture

- `charts/agent-local/`: agents execute runs in their own pods. The recommended default chart.
- `charts/agent-job/`: an agent controller creates isolated Jobs through `AgentTaskTemplate` resources.
- `charts/agent-k8s/`: an agent controller manages workers that execute runs in isolated pods.
- `charts/agent-docker/`: deprecated Docker-in-Docker chart, excluded from releases.

Each chart owns its templates, values, documentation, and changelog. In `agent-local`,
`templates/workload.yaml` shares pod configuration between Deployment and StatefulSet,
selected by `workload.kind`. Storage modes use explicit data and cache blocks in
`templates/workload.yaml` and `templates/pvc.yaml`, including legacy cache values.

`.ct/` holds chart-testing and kind configuration. `.github/workflows/` handles CI and releases.
The custom action in `.github/actions/update-app-version/` updates chart versions and changelogs.

## Values and templates

- Keep templates simple and value names consistent across charts.
- Prefer explicit YAML and some duplication over extra variables or template helpers.
  Keep helpers when they are broadly reused and add clear value.
- Preserve defaults, resource names, and upgrade behavior. New optional values need
  fallbacks for `helm upgrade --reuse-values`.
- Edit `values.schema.json` directly. Keep validation minimal and define each rule in one place.
- Preserve unrelated working tree changes.

## Testing

- Run static checks (`just lint`) and unit tests (`just test`) for chart changes.
  See [Test kinds](TESTING.md#test-kinds) for the scope of each check.
- Add focused rendering and regression tests in `charts/<chart>/tests/*_test.yaml`.
- Use `charts/<chart>/ci/*-values.yaml` and `just test-install` for installation and upgrade changes.
  Use dummy credentials and a disposable cluster.
- Exclude test suites and CI profiles from chart packages through `.helmignore`.

## Documentation

- Document values with helm-docs `# --` comments in `values.yaml`.
- Edit chart guides in `README.md.gotmpl`, then regenerate `README.md` with `just docs`.
- Keep tool requirements in README.md, test instructions in TESTING.md, and contribution
  guidance in CONTRIBUTING.md.
- Use short sentences, simple words, and active voice. Keep docstrings brief.

## Changelog

Update `charts/<chart>/CHANGELOG.md` for each chart whose users are affected.

- Add entries under the existing `## [UNRELEASED]` heading. Preserve its spelling for release automation.
- Use sections in this order: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.
  Omit empty sections.
- Describe the effect on users. Name affected values in backticks and show version changes as `old → new`.
- Mark breaking changes with `**BREAKING:**`, identify affected configurations, and explain
  the required action or link to a migration guide.
- Skip CI, test tooling, documentation-only changes, and refactors that preserve chart behavior.
- Leave `version`, `appVersion`, release headings, and generated `RELEASE.md` and Artifact Hub
  annotations to release automation. It moves unreleased entries into `## [vX.Y.Z]` sections.
