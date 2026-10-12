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
{{- include "agent-local.fullnameRaw" . | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/* Preserve the full input for name hashing before applying resource limits. */}}
{{- define "agent-local.fullnameRaw" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name }}
{{- end }}
{{- end }}
{{- end }}


{{/* Older releases using --reuse-values do not have workload settings. */}}
{{- define "agent-local.workloadKind" -}}
{{- (default dict .Values.workload).kind | default "Deployment" -}}
{{- end }}

{{/* Leave room for the revision hash label and use a valid governing Service name. */}}
{{- define "agent-local.statefulSetName" -}}
{{- $fullName := include "agent-local.fullnameRaw" . -}}
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
  {{- if eq (include "agent-local.persistence.usingDeprecated" .root) "true" -}}
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

{{/* Shared spec for standalone PVCs and both kinds of claim templates. */}}
{{- define "agent-local.persistence.claimSpec" -}}
accessModes:
  - {{ .accessMode }}
resources:
  requests:
    storage: {{ .storage }}
{{- with .storageClassName }}
storageClassName: {{ ternary "" . (eq . "-") | quote }}
{{- end }}
{{- end }}

{{/* Pod volume source. StatefulSet claim templates supply their own volumes. */}}
{{- define "agent-local.persistence.podVolume" -}}
- name: {{ .name }}-dir
  {{- if eq .mode "emptyDir" }}
  {{- if .emptyDirSizeLimit }}
  emptyDir:
    sizeLimit: {{ .emptyDirSizeLimit }}
  {{- else }}
  emptyDir: {}
  {{- end }}
  {{- else if eq .mode "persistentVolumeClaim" }}
  persistentVolumeClaim:
    claimName: {{ .claimName | default .defaultClaimName }}
  {{- else if eq .mode "ephemeral" }}
  ephemeral:
    volumeClaimTemplate:
      {{- with omit .annotations "helm.sh/resource-policy" }}
      metadata:
        annotations:
          {{- toYaml . | nindent 10 }}
      {{- end }}
      spec:
        {{- include "agent-local.persistence.claimSpec" . | nindent 8 }}
  {{- end }}
{{- end }}
