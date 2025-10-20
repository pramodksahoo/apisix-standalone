{{/*
Expand the name of the chart.
*/}}
{{- define "apisix-standalone.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "apisix-standalone.fullname" -}}
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
{{- define "apisix-standalone.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "apisix-standalone.labels" -}}
helm.sh/chart: {{ include "apisix-standalone.chart" . }}
{{ include "apisix-standalone.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: gateway
app.kubernetes.io/part-of: apisix
environment: {{ .Values.environment }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "apisix-standalone.selectorLabels" -}}
app.kubernetes.io/name: {{ include "apisix-standalone.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "apisix-standalone.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "apisix-standalone.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate APISIX configuration
*/}}
{{- define "apisix-standalone.config" -}}
deployment:
  role: traditional
  role_traditional:
    config_provider: yaml

apisix:
  ssl:
    ssl_trusted_certificate: /usr/local/apisix/conf/ca-certificates.crt
  node_listen:
    - {{ .Values.deployment.ports.http }}
    - port: {{ .Values.deployment.ports.https }}
      ssl: true

deployment:
  admin:
    admin_key:
      - name: admin
        key: {{ .Values.configMap.adminKey }}
        role: admin

plugins:
{{- range .Values.configMap.plugins }}
  - {{ . }}
{{- end }}

#END
{{- end }}

{{/*
Generate routes configuration for APISIX
*/}}
{{- define "apisix-standalone.routes" -}}
routes:
{{- range .Values.routes }}
  - name: {{ .name | quote }}
    {{- if .uris }}
    uris:
    {{- range .uris }}
      - {{ . | quote }}
    {{- end }}
    {{- else if .uri }}
    uri: {{ .uri | quote }}
    {{- end }}
    {{- if .plugins }}
    plugins:
    {{- toYaml .plugins | nindent 6 }}
    {{- end }}
    {{- if .upstream }}
    upstream:
    {{- toYaml .upstream | nindent 6 }}
    {{- end }}
{{- end }}

#END
{{- end }}

{{/*
Generate SSL configuration
*/}}
{{- define "apisix-standalone.ssl" -}}
{{- if .Values.ssl }}
ssls:
{{- range .Values.ssl }}
  cert: |
    {{- .cert | nindent 4 }}
  key: |
    {{- .key | nindent 4 }}
{{- end }}

snis:
{{- range .Values.ssl }}
{{- range .snis }}
  - {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}

#END
{{- end }}