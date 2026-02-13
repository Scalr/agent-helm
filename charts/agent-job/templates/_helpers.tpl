{{/*
Expand the name of the chart.
*/}}
{{- define "agent-job.name" -}}
{{- default "scalr-agent" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "agent-job.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "scalr-agent" .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "agent-job.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agent-job.labels" -}}
helm.sh/chart: {{ include "agent-job.chart" . }}
{{ include "agent-job.selectorLabels" . }}
{{- with .Values.global.labels }}
{{- toYaml . }}
{{- end }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "agent-job.annotations" -}}
{{- with .Values.global.annotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "agent-job.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agent-job.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "agent-job.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "agent-job.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{/*
Convert Kubernetes quantity to megabytes
Supports: Gi, Mi, G, M
*/}}
{{- define "agent-job.sizeToMB" -}}
{{- $size := . -}}
{{- if hasSuffix "Gi" $size -}}
  {{- $val := trimSuffix "Gi" $size | float64 -}}
  {{- $val | mul 1024 | int -}}
{{- else if hasSuffix "Mi" $size -}}
  {{- trimSuffix "Mi" $size | int -}}
{{- else if hasSuffix "G" $size -}}
  {{- $val := trimSuffix "G" $size | float64 -}}
  {{- $val | mul 1000 | int -}}
{{- else if hasSuffix "M" $size -}}
  {{- trimSuffix "M" $size | int -}}
{{- else -}}
  {{- fail (printf "Unsupported size format: %s. Use Gi, Mi, G, or M" $size) -}}
{{- end -}}
{{- end -}}

{{/*
Generate HTTP proxy environment variables
*/}}
{{- define "agent-job.proxyEnv" -}}
{{- if .Values.global.proxy.enabled }}
- name: HTTP_PROXY
  value: {{ .Values.global.proxy.httpProxy | quote }}
- name: HTTPS_PROXY
  value: {{ .Values.global.proxy.httpsProxy | quote }}
- name: NO_PROXY
  value: {{ .Values.global.proxy.noProxy | quote }}
{{- end }}
{{- end -}}

{{/*
Determine the CA bundle secret name
Returns the user-provided secret name or the chart-managed secret name
*/}}
{{- define "agent-job.caBundleSecretName" -}}
{{- if .Values.global.tls.caBundleSecret.name -}}
{{- .Values.global.tls.caBundleSecret.name -}}
{{- else if .Values.global.tls.caBundle -}}
{{- printf "%s-ca-bundle" (include "agent-job.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Generate CA certificate environment variable and path
*/}}
{{- define "agent-job.caCertEnv" -}}
{{- $secretName := include "agent-job.caBundleSecretName" . -}}
{{- if $secretName }}
- name: SCALR_AGENT_CA_CERT
  value: "/etc/ssl/certs/scalr-ca-bundle.crt"
- name: SSL_CERT_FILE
  value: "/etc/ssl/certs/scalr-ca-bundle.crt"
{{- end }}
{{- end -}}

{{/*
Generate CA certificate volume mount
*/}}
{{- define "agent-job.caCertVolumeMount" -}}
{{- $secretName := include "agent-job.caBundleSecretName" . -}}
{{- if $secretName }}
- name: ca-bundle
  mountPath: /etc/ssl/certs/scalr-ca-bundle.crt
  subPath: {{ .Values.global.tls.caBundleSecret.key }}
  readOnly: true
{{- end }}
{{- end -}}

{{/*
Generate CA certificate volume
*/}}
{{- define "agent-job.caCertVolume" -}}
{{- $secretName := include "agent-job.caBundleSecretName" . -}}
{{- if $secretName }}
- name: ca-bundle
  secret:
    secretName: {{ $secretName }}
    items:
      - key: {{ .Values.global.tls.caBundleSecret.key }}
        path: {{ .Values.global.tls.caBundleSecret.key }}
{{- end }}
{{- end -}}

{{/*
Build image string with registry and namespace handling.

Automatically uses .Values.global.imageRegistry and .Values.global.imageNamespace from context.

Usage:
{{ include "agent-job.image" (dict "context" . "repository" .Values.task.runner.image.repository "tag" .Values.task.runner.image.tag "defaultTag" .Chart.AppVersion) }}
*/}}
{{- define "agent-job.image" -}}
{{- $registry := .context.Values.global.imageRegistry -}}
{{- $namespace := .context.Values.global.imageNamespace -}}
{{- $repository := .repository -}}
{{- $tag := .tag -}}
{{- if and (not $tag) .defaultTag -}}
  {{- $tag = .defaultTag -}}
{{- end -}}

{{- /* Extract image name from repository */ -}}
{{- $imageName := last (splitList "/" $repository) -}}

{{- /* Build repository path with namespace override if provided */ -}}
{{- if $namespace -}}
  {{- $repository = printf "%s/%s" $namespace $imageName -}}
{{- end -}}

{{- /* Build final image reference */ -}}
{{- if $registry -}}
  {{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- else -}}
  {{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}
