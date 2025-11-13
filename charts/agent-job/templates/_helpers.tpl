{{/*
Expand the name of the chart.
*/}}
{{- define "agent-job.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
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
{{- $name := default .Chart.Name .Values.nameOverride }}
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
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
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
Generate a stable, release-scoped name for chart sub-components.
*/}}
{{- define "agent-job.componentName" -}}
{{- printf "%s-%s" (include "agent-job.fullname" .context) .component | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve the data PVC name, falling back to the chart-managed default.
*/}}
{{- define "agent-job.dataPVCName" -}}
{{- if .Values.persistence.data.persistentVolumeClaim.claimName }}
{{- .Values.persistence.data.persistentVolumeClaim.claimName -}}
{{- else }}
{{- printf "%s-data" (include "agent-job.fullname" .) -}}
{{- end }}
{{- end }}

{{/*
Resolve the cache PVC name, falling back to the chart-managed default.
*/}}
{{- define "agent-job.cachePVCName" -}}
{{- if .Values.persistence.cache.persistentVolumeClaim.claimName }}
{{- .Values.persistence.cache.persistentVolumeClaim.claimName -}}
{{- else }}
{{- printf "%s-cache" (include "agent-job.fullname" .) -}}
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
