{{/*
Expand the name of the chart.
*/}}
{{- define "predefined-namespaces.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "predefined-namespaces.fullname" -}}
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
{{- define "predefined-namespaces.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "predefined-namespaces.labels" -}}
helm.sh/chart: {{ include "predefined-namespaces.chart" . }}
{{ include "predefined-namespaces.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "predefined-namespaces.selectorLabels" -}}
app.kubernetes.io/name: {{ include "predefined-namespaces.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Merge annotations function
*/}}
{{- define "predefined-namespaces.mergeAnnotations" -}}
{{- $global := .global -}}
{{- $local := .local -}}
{{- $merged := dict -}}
{{- range $key, $value := $global -}}
  {{- $_ := set $merged $key $value -}}
{{- end -}}
{{- range $key, $value := $local -}}
  {{- $_ := set $merged $key $value -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end }}

{{/*
Merge labels function
*/}}
{{- define "predefined-namespaces.mergeLabels" -}}
{{- $global := .global -}}
{{- $local := .local -}}
{{- $merged := dict -}}
{{- range $key, $value := $global -}}
  {{- $_ := set $merged $key $value -}}
{{- end -}}
{{- range $key, $value := $local -}}
  {{- $_ := set $merged $key $value -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end }} 