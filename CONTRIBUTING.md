# Contributing Guide

Contributions are welcome through GitHub pull requests. Start with [development setup](README.md#development).

## Helm chart guidelines

- Follow [Helm chart best practices](https://helm.sh/docs/topics/chart_best_practices/).
- Keep value names consistent across charts and document them in `values.yaml`.
- Preserve existing defaults and upgrade behavior, including `helm upgrade --reuse-values`.
- Include tests for behavior changes and bug fixes.

## Testing

Run `just lint` and `just test` for chart changes. See [Testing](TESTING.md) for test kinds,
commands, and installation tests.

## Documentation

Edit chart documentation in `README.md.gotmpl` and value descriptions in `values.yaml`,
then run `just docs` to regenerate chart READMEs.

| Command | Checks |
| --- | --- |
| `just lychee` | Local Markdown links and anchors, offline |
| `just lychee-online` | Local and external links and anchors (makes external HTTP calls) |

The pre-commit link check runs offline.

## Changelog and releases

Add changes that affect chart users under `## [UNRELEASED]` in each affected chart's
`CHANGELOG.md`. Describe the effect on users and explain any migration needed for breaking changes.

Release automation handles chart `version` and `appVersion` bumps and creates release notes.
Mark breaking entries with `**BREAKING:**`. These trigger a minor bump.
Other releases use a patch bump.

## Pull requests

Keep each pull request focused on one change. Describe the problem, the resulting behavior,
and the checks you ran. Link the related issue when one exists.

## GitHub Actions development

When editing `.github/actions/update-app-version`, install the shared ESLint configuration
and the action's dependencies, then rebuild its bundle:

```console
npm --prefix .github/actions ci
npm --prefix .github/actions/update-app-version ci
npm --prefix .github/actions/update-app-version run all
```

Commit the updated `index.dist.js` with the source changes. The pre-commit hook rebuilds
the bundle when files under `.github/actions/` change.
