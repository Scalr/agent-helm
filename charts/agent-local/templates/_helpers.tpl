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
{{- $name := $fullName | replace "." "-" -}}
{{- if regexMatch "^[0-9]" $name -}}
{{- $name = printf "agent-%s" $name -}}
{{- end -}}
{{- if or (ne $name $fullName) (gt (len $name) 52) -}}
{{- printf "%s-%s" ($name | trunc 43 | trimSuffix "-") ($fullName | sha256sum | trunc 8) -}}
{{- else -}}
{{- $name | trimSuffix "-" -}}
{{- end -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "agent-local.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
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
app.kubernetes.io/name: {{ default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
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
Resolve one volume's storage mode and claim settings. An empty mode preserves the
enabled flag's behavior, including the legacy cache PVC name and precedence.
Parameters: root (chart context), name (data or cache).
*/}}
{{- define "agent-local.persistence.volume" -}}
{{- $volume := index .root.Values.persistence .name -}}
{{- $enabled := $volume.enabled | default false -}}
{{- $pvc := $volume.persistentVolumeClaim -}}
{{- $defaultClaimName := printf "%s-%s" (include "agent-local.fullname" .root) .name -}}
{{- if eq .name "cache" -}}
  {{- $enabled = or $enabled (.root.Values.persistence.enabled | default false) -}}
  {{- if or .root.Values.persistence.enabled (ne (default "" .root.Values.persistence.persistentVolumeClaim.claimName) "") -}}
    {{- $pvc = .root.Values.persistence.persistentVolumeClaim -}}
    {{- $defaultClaimName = include "agent-local.fullname" .root -}}
  {{- end -}}
{{- end -}}
{{- $mode := $volume.mode | default "emptyDir" -}}
{{- if and (not $volume.mode) $enabled -}}
  {{- $mode = "persistentVolumeClaim" -}}
{{- end -}}
{{- $out := dict
    "name" .name
    "mode" $mode
    "claimName" (default "" $pvc.claimName)
    "storageClassName" (default "" $pvc.storageClassName)
    "storage" $pvc.storage
    "accessMode" $pvc.accessMode
    "subPath" (default "" $pvc.subPath)
    "annotations" (default (dict) $pvc.annotations)
    "defaultClaimName" $defaultClaimName
-}}
{{- if eq $mode "emptyDir" -}}
  {{- $_ := set $out "emptyDirSizeLimit" ($volume.emptyDir | default dict).sizeLimit -}}
{{- end -}}
{{- toYaml $out -}}
{{- end }}
