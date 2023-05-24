.PHONY: docs

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
	version="1.11.0"; \
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

# Generate documentation using helm-docs
docs:
	helm-docs

# Linting
lint:
	env CT_CONFIG=.ct ct lint
