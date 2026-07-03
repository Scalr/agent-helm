.PHONY: docs linkcheck

# Configure development environment
platform = $(shell uname -s)
arch = $(shell uname -m)
ct_version = 3.8.0
kelik = "\\xF0\\x9F\\x8D\\xBA"

dev:
# Prerequisites
	if [ "$(platform)" = "Linux" ]; then \
		which curl >/dev/null || { apt-get update -yq && apt-get install -yq curl; }; \
	elif [ "$(platform)" = "Darwin" ]; then \
		which brew >/dev/null || { echo "Missing requirement: brew. Install Homebrew https://brew.sh/"; exit 1; } \
	fi;
# Install [helm](https://github.com/helm/helm#install)
	version=3.12.0; \
	set -e; \
	echo "=> Installing helm..."; \
	case $(arch) in \
		x86_64) normarch="amd64" ;; \
		aarch64|arm64) normarch="arm64" ;; \
		*) echo "Unsupported architecture: $(arch)"; exit 1 ;; \
	esac; \
	\
	if [ "$(platform)" = "Linux" ]; then \
		curl -sSLo helm.tar.gz \
			https://get.helm.sh/helm-v$${version}-linux-$${normarch}.tar.gz \
		&& tar -xz -C /usr/local/bin -f helm.tar.gz --strip-components 1 linux-$${normarch}/helm \
		&& chmod +x /usr/local/bin/helm \
		&& rm -f helm.tar.gz; \
	elif [ "$(platform)" = "Darwin" ]; then \
		brew install helm; \
	else \
		echo "Unsupported platform: $(platform)" \
		&& exit 1; \
	fi; \
	helm version; \
	echo "$(kelik) Installed helm";
# Install [helm-docs](https://github.com/norwoodj/helm-docs#installation)
	version="1.14.2"; \
	set -e; \
	echo "=> Installing helm-docs..."; \
	case $(arch) in \
		x86_64) normarch=$(arch) ;; \
		aarch64|arm64) normarch="arm64" ;; \
		*) echo "Unsupported architecture: $(arch)"; exit 1 ;; \
	esac; \
	\
	if [ "$(platform)" = "Linux" ]; then \
		curl -sSLo helm-docs.tar.gz \
			https://github.com/norwoodj/helm-docs/releases/download/v$${version}/helm-docs_$${version}_$(platform)_$${normarch}.tar.gz \
		&& tar -xz -C /usr/local/bin -f helm-docs.tar.gz helm-docs  \
		&& chmod +x /usr/local/bin/helm-docs \
		&& rm -f helm-docs.tar.gz; \
	elif [ "$(platform)" = "Darwin" ]; then \
		brew install norwoodj/tap/helm-docs; \
	else \
		echo "Unsupported platform: $(platform)" \
		&& exit 1; \
	fi; \
	helm-docs --version; \
	echo "$(kelik) Installed helm-docs";
# Install [chart-testing](https://github.com/helm/chart-testing#installation)
	set -e; \
	echo "=> Installing chart-testing..."; \
	case $(arch) in \
		x86_64) normarch="amd64" ;; \
		aarch64|arm64) normarch="arm64" ;; \
		*) echo "Unsupported architecture: $(arch)"; exit 1 ;; \
	esac; \
	\
	if [ "$(platform)" = "Linux" ]; then \
		curl -sSLo chart-testing.tar.gz \
			https://github.com/helm/chart-testing/releases/download/v$(ct_version)/chart-testing_$(ct_version)_$(platform)_$${normarch}.tar.gz \
		&& tar -xz -C /usr/local/bin -f chart-testing.tar.gz ct \
		&& chmod +x /usr/local/bin/ct \
		&& rm -f chart-testing.tar.gz; \
	elif [ "$(platform)" = "Darwin" ]; then \
		brew install chart-testing; \
	else \
		echo "Unsupported platform: $(platform)" \
		&& exit 1; \
	fi; \
	ct version; \
	echo "$(kelik) Installed chart-testing";
# Importing ct config from the chart-testing repository.
	set -e; \
	echo "=> Importing ct config..."; \
	ct_config_dir=".ct"; \
	mkdir -p $$ct_config_dir; \
	cd $$ct_config_dir; \
	curl -sSLO https://raw.githubusercontent.com/helm/chart-testing/v$(ct_version)/etc/chart_schema.yaml; \
	curl -sSLO https://raw.githubusercontent.com/helm/chart-testing/v$(ct_version)/etc/lintconf.yaml; \
	cd -;
	echo "$(kelik) Imported ct config";
	echo "=> Installing standard ESLint config..."; \
	npm --prefix .github/actions install


# Generate documentation using helm-docs (requires helm-docs >= 1.14)
docs:
	@command -v helm-docs >/dev/null 2>&1 || { echo "helm-docs not found. Run 'make dev' to install it."; exit 1; }; \
	ver=$$(helm-docs --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	major=$$(echo $$ver | cut -d. -f1); \
	minor=$$(echo $$ver | cut -d. -f2); \
	if [ "$$major" -lt 1 ] || { [ "$$major" -eq 1 ] && [ "$$minor" -lt 14 ]; }; then \
		echo "helm-docs >= 1.14 required, found $$ver. Run 'make dev' to install a compatible version."; \
		exit 1; \
	fi
	helm-docs

# Check documentation links online, including remote URL fragments/anchors.
# Unlike the pre-commit lychee hook (which runs --offline and skips remote URLs),
# this fetches external links and verifies their anchors. Requires network access.
lychee:
	@command -v lychee >/dev/null 2>&1 || { echo "lychee not found. See https://github.com/lycheeverse/lychee#installation"; exit 1; }
	lychee --no-progress --include-fragments --extensions md .

# Linting
lint:
	env CT_CONFIG=.ct ct lint --target-branch master --check-version-increment=false --helm-lint-extra-args '--set agent.token=dummy'
