{{/*
Expand the name of the chart.
*/}}
{{- define "agent-local.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "agent-local.fullname" -}}
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

{{/* Leave room for the revision hash label and use a valid governing Service name. */}}
{{- define "agent-local.statefulSetName" -}}
{{- $fullName := .Values.fullnameOverride -}}
{{- if not $fullName -}}
{{- $chartName := .Values.nameOverride | default .Chart.Name -}}
{{- $fullName = .Release.Name -}}
{{- if not (contains $chartName .Release.Name) -}}
{{- $fullName = printf "%s-%s" .Release.Name $chartName -}}
{{- end -}}
{{- end -}}
{{- $name := $fullName | replace "." "-" | trimSuffix "-" -}}
{{- if regexMatch "^[0-9]" $name -}}
{{- $name = printf "agent-%s" $name -}}
{{- end -}}
{{- if or (ne $name $fullName) (gt (len $name) 52) -}}
{{- printf "%s-%s" ($name | trunc 43 | trimSuffix "-") ($fullName | sha256sum | trunc 8) -}}
{{- else -}}
{{- $name -}}
{{- end -}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "agent-local.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agent-local.labels" -}}
helm.sh/chart: {{ include "agent-local.chart" . }}
{{ include "agent-local.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "agent-local.selectorLabels" -}}
app.kubernetes.io/name: {{ include "agent-local.name" . }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "agent-local.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "agent-local.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Returns "true" if the deprecated top-level persistence keys are in use.
Triggered when `persistence.enabled` is true or the legacy `persistence.persistentVolumeClaim.claimName` is non-empty.
*/}}
{{- define "agent-local.persistence.usingDeprecated" -}}
{{- if or .Values.persistence.enabled (ne (default "" .Values.persistence.persistentVolumeClaim.claimName) "") -}}
true
{{- end -}}
{{- end }}
