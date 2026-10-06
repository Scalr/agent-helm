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
app.kubernetes.io/instance: {{ .Release.Name }}
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

{{/*
Effective cache persistence config as a dict with keys:
  enabled, claimName, storageClassName, storage, accessMode, subPath, emptyDirSizeLimit, defaultClaimName
When the deprecated top-level schema is in use, falls back to legacy `persistence.persistentVolumeClaim.*` and `persistence.enabled`,
and preserves the legacy default PVC name (`<fullname>`) to avoid orphaning existing PVCs on upgrade.
*/}}
{{- define "agent-local.persistence.cache" -}}
{{- $deprecated := eq (include "agent-local.persistence.usingDeprecated" .) "true" -}}
{{- $enabled := or .Values.persistence.cache.enabled .Values.persistence.enabled -}}
{{- $pvc := .Values.persistence.cache.persistentVolumeClaim -}}
{{- $defaultClaimName := printf "%s-cache" (include "agent-local.fullname" .) -}}
{{- if $deprecated -}}
  {{- $pvc = .Values.persistence.persistentVolumeClaim -}}
  {{- $defaultClaimName = include "agent-local.fullname" . -}}
{{- end -}}
{{- $out := dict
    "enabled" $enabled
    "claimName" (default "" $pvc.claimName)
    "storageClassName" (default "" $pvc.storageClassName)
    "storage" $pvc.storage
    "accessMode" $pvc.accessMode
    "subPath" (default "" $pvc.subPath)
    "emptyDirSizeLimit" .Values.persistence.cache.emptyDir.sizeLimit
    "defaultClaimName" $defaultClaimName
-}}
{{- toYaml $out -}}
{{- end }}
