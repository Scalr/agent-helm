.PHONY: docs

# Configure development environment
dev:
# Install [helm-docs](https://github.com/norwoodj/helm-docs#installation) on Linux/MacOS
	platform=$$(uname -s); \
	arch=$$(uname -m); \
	case $$arch in \
		x86_64) ;; \
		aarch64|arm64) arch="arm64" ;; \
		*) echo "Unsupported architecture: $$arch"; exit 1 ;; \
	esac; \
	version="1.11.0"; \
	\
	if [ "$$platform" = "Linux" ]; then \
		which curl >/dev/null || { apt-get update -yq && apt-get install -yq curl; }; \
		curl -sSLo ./helm-docs.tar.gz \
			https://github.com/norwoodj/helm-docs/releases/download/v$${version}/helm-docs_$${version}_$${platform}_$${arch}.tar.gz \
		&& tar -xz -C /usr/local/bin -f helm-docs.tar.gz helm-docs  \
		&& chmod +x /usr/local/bin/helm-docs \
		&& rm -f helm-docs.tar.gz; \
	elif [ "$$platform" = "Darwin" ]; then \
		brew install norwoodj/tap/helm-docs; \
	else \
		echo "Unsupported platform: $$platform" \
		&& exit 1; \
	fi; \
	echo "Installed $$(helm-docs --version)"; \

# Generate documentation using helm-docs
docs:
	helm-docs
