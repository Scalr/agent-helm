set positional-arguments

# List available commands.
default:
    @just --list

# Generate documentation using helm-docs >= 1.14.
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v helm-docs >/dev/null || { echo "helm-docs not found. See https://github.com/norwoodj/helm-docs#installation"; exit 1; }
    version=$(helm-docs --version)
    if [[ ! "$version" =~ ([0-9]+)\.([0-9]+)\.[0-9]+ ]]; then
        echo "Cannot determine helm-docs version: $version"
        exit 1
    fi
    if (( BASH_REMATCH[1] < 1 || (BASH_REMATCH[1] == 1 && BASH_REMATCH[2] < 14) )); then
        echo "helm-docs >= 1.14 required, found $version. See https://github.com/norwoodj/helm-docs#installation"
        exit 1
    fi
    helm-docs

# Check local documentation links and anchors offline.
lychee:
    @command -v lychee >/dev/null || { echo "lychee not found. See https://github.com/lycheeverse/lychee#installation"; exit 1; }
    lychee --no-progress --offline --include-fragments --extensions md .

# Check local and external documentation links and anchors after confirmation.
[confirm('Check external documentation links over the network (y/n)?')]
lychee-online:
    @command -v lychee >/dev/null || { echo "lychee not found. See https://github.com/lycheeverse/lychee#installation"; exit 1; }
    lychee --no-progress --include-fragments --extensions md .

# Run Helm unit tests without a cluster. Accepts helm-unittest flags.
test *args:
    @command -v helm >/dev/null || { echo "helm not found. See https://helm.sh/docs/intro/install/"; exit 1; }
    @helm plugin list | awk '$1 == "unittest" { found=1 } END { exit !found }' || { echo "helm-unittest not found. Install: helm plugin install https://github.com/helm-unittest/helm-unittest/releases/download/v1.2.1/unittest-1.2.1.tgz --verify=false"; exit 1; }
    helm unittest --strict "$@" charts/*

# Lint all charts using pre-commit's managed dependencies.
lint:
    @command -v pre-commit >/dev/null || { echo "pre-commit not found. See https://pre-commit.com/#install"; exit 1; }
    @command -v ct >/dev/null || { echo "ct not found. See https://github.com/helm/chart-testing#installation"; exit 1; }
    @command -v git >/dev/null || { echo "git not found. See https://git-scm.com/downloads"; exit 1; }
    @command -v helm >/dev/null || { echo "helm not found. See https://helm.sh/docs/intro/install/"; exit 1; }
    pre-commit run chart-lint --all-files

# Install and upgrade charts in the disposable kind-agent-helm-test context.
test-install *args:
    @command -v ct >/dev/null || { echo "ct not found. See https://github.com/helm/chart-testing#installation"; exit 1; }
    @command -v git >/dev/null || { echo "git not found. See https://git-scm.com/downloads"; exit 1; }
    @command -v helm >/dev/null || { echo "helm not found. See https://helm.sh/docs/intro/install/"; exit 1; }
    @command -v kubectl >/dev/null || { echo "kubectl not found. See https://kubernetes.io/docs/tasks/tools/"; exit 1; }
    @test "$(kubectl config current-context)" = kind-agent-helm-test || { echo "Select the disposable kind-agent-helm-test context. See TESTING.md for setup."; exit 1; }
    ct install --config .ct/ct.yaml --upgrade "$@"
