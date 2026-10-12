{{/* Environment variables emitted by the chart. */}}
{{- define "agent-local.env" -}}
{{- with .root -}}
SCALR_AGENT_NAME:
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
SCALR_URL:
  value: {{ .Values.agent.url | quote }}
SCALR_AGENT_DRIVER:
  value: local
SCALR_AGENT_CONCURRENCY:
  value: "1"
SCALR_AGENT_DISCONNECT_ON_STOP:
  value: "1"
{{- if eq .Values.agent.shutdownMode "graceful" }}
{{- if lt (.Values.terminationGracePeriodSeconds | int) 30 }}
{{- fail "terminationGracePeriodSeconds must be at least 30 seconds when agent.shutdownMode=graceful" }}
{{- end }}
SCALR_AGENT_WORKER_ON_STOP_ACTION:
  value: grace-shutdown
SCALR_AGENT_WORKER_GRACE_SHUTDOWN_TIMEOUT:
  value: {{ sub .Values.terminationGracePeriodSeconds 10 | quote }}
{{- else if eq .Values.agent.shutdownMode "drain" }}
{{- if lt (.Values.terminationGracePeriodSeconds | int) 120 }}
{{- fail "terminationGracePeriodSeconds must be at least 120 seconds when agent.shutdownMode=drain" }}
{{- end }}
SCALR_AGENT_WORKER_ON_STOP_ACTION:
  value: drain
SCALR_AGENT_WORKER_DRAIN_TIMEOUT:
  value: {{ sub .Values.terminationGracePeriodSeconds 70 | quote }}
SCALR_AGENT_WORKER_GRACE_SHUTDOWN_TIMEOUT:
  value: "60"
{{- else }}
SCALR_AGENT_WORKER_ON_STOP_ACTION:
  value: force-shutdown
{{- end }}
SCALR_AGENT_DATA_DIR:
  value: {{ .Values.agent.dataDir | quote }}
SCALR_AGENT_CACHE_DIR:
  value: {{ .Values.agent.cacheDir | quote }}
{{- with .Values.agent.providerNetworkMirrors }}
SCALR_AGENT_PROVIDER_NETWORK_MIRRORS:
  value: {{ toJson . | quote }}
{{- end }}
SCALR_AGENT_TOKEN:
  valueFrom:
    secretKeyRef:
      {{- if .Values.agent.tokenExistingSecret.name }}
      name: {{ .Values.agent.tokenExistingSecret.name | quote }}
      key: {{ .Values.agent.tokenExistingSecret.key | quote }}
      {{- else }}
      name: {{ include "agent-local.fullname" . }}-token
      key: token
      {{- end }}
      optional: false
{{- if $.clientCert }}
SCALR_AGENT_TLS_CERT_FILE:
  value: /etc/scalr-agent/ssl/tls.crt
SCALR_AGENT_TLS_KEY_FILE:
  value: /etc/scalr-agent/ssl/tls.key
{{- end }}
{{- if $.caBundle }}
SCALR_AGENT_CA_CERT:
  value: /etc/ssl/certs/scalr-ca-bundle.crt
SSL_CERT_FILE:
  value: /etc/ssl/certs/scalr-ca-bundle.crt
{{- end }}
{{- end }}
{{- end }}
