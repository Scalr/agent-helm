# List available commands.
default:
    @just --list

# Install development tools and locked Python dependencies (Linux/macOS).
dev:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v uv >/dev/null || { echo "Install uv: https://docs.astral.sh/uv/getting-started/installation/"; exit 1; }
    command -v npm >/dev/null || { echo "Install Node.js: https://nodejs.org/en/download/package-manager"; exit 1; }

    platform=$(uname -s)
    case $(uname -m) in
        x86_64) helm_arch=amd64; docs_arch=x86_64 ;;
        aarch64|arm64) helm_arch=arm64; docs_arch=arm64 ;;
        *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
    esac

    helm_version=3.12.0
    docs_version=1.14.2
    ct_version=3.8.0
    case "$platform" in
        Linux)
            if ! command -v curl >/dev/null; then
                apt-get update -yq
                apt-get install -yq curl
            fi
            download_dir=$(mktemp -d)
            trap 'rm -rf "$download_dir"' EXIT

            curl -fsSL "https://get.helm.sh/helm-v${helm_version}-linux-${helm_arch}.tar.gz" -o "$download_dir/helm.tar.gz"
            tar -xz -C /usr/local/bin -f "$download_dir/helm.tar.gz" --strip-components 1 "linux-${helm_arch}/helm"
            chmod +x /usr/local/bin/helm

            curl -fsSL "https://github.com/norwoodj/helm-docs/releases/download/v${docs_version}/helm-docs_${docs_version}_Linux_${docs_arch}.tar.gz" -o "$download_dir/helm-docs.tar.gz"
            tar -xz -C /usr/local/bin -f "$download_dir/helm-docs.tar.gz" helm-docs
            chmod +x /usr/local/bin/helm-docs

            curl -fsSL "https://github.com/helm/chart-testing/releases/download/v${ct_version}/chart-testing_${ct_version}_linux_${helm_arch}.tar.gz" -o "$download_dir/chart-testing.tar.gz"
            tar -xz -C /usr/local/bin -f "$download_dir/chart-testing.tar.gz" ct
            chmod +x /usr/local/bin/ct
            ;;
        Darwin)
            command -v brew >/dev/null || { echo "Install Homebrew: https://brew.sh/"; exit 1; }
            brew install helm norwoodj/tap/helm-docs chart-testing
            ;;
        *) echo "Unsupported platform: $platform"; exit 1 ;;
    esac

    helm version
    helm-docs --version
    ct version

    mkdir -p .ct
    curl -fsSL "https://raw.githubusercontent.com/helm/chart-testing/v${ct_version}/etc/chart_schema.yaml" -o .ct/chart_schema.yaml
    curl -fsSL "https://raw.githubusercontent.com/helm/chart-testing/v${ct_version}/etc/lintconf.yaml" -o .ct/lintconf.yaml
    npm --prefix .github/actions install
    uv sync --locked

# Generate documentation using helm-docs >= 1.14.
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v helm-docs >/dev/null || { echo "helm-docs not found. Run 'just dev' to install it."; exit 1; }
    version=$(helm-docs --version)
    if [[ ! "$version" =~ ([0-9]+)\.([0-9]+)\.[0-9]+ ]]; then
        echo "Cannot determine helm-docs version: $version"
        exit 1
    fi
    if (( BASH_REMATCH[1] < 1 || (BASH_REMATCH[1] == 1 && BASH_REMATCH[2] < 14) )); then
        echo "helm-docs >= 1.14 required, found $version. Run 'just dev' to install a compatible version."
        exit 1
    fi
    helm-docs

# Check documentation links online, including remote fragments (requires network).
lychee:
    @command -v lychee >/dev/null || { echo "lychee not found. See https://github.com/lycheeverse/lychee#installation"; exit 1; }
    lychee --no-progress --include-fragments --extensions md .

# Run chart rendering and validation tests without a cluster.
test:
    uv run --locked pytest

# Format Python tests and apply safe lint fixes.
fmt:
    uv run --locked ruff check --fix tests
    uv run --locked ruff format tests

# Check Python test lint, formatting, and types.
lint-tests:
    uv run --locked ruff check tests
    uv run --locked ruff format --check tests
    uv run --locked ty check tests

# Check Python tests and lint changed charts.
lint: lint-tests
    env CT_CONFIG=.ct ct lint --target-branch master --check-version-increment=false --helm-lint-extra-args '--set agent.token=dummy'
