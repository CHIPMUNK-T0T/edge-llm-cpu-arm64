{{- define "inference-gateway.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "inference-gateway.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "inference-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "inference-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "inference-gateway.commonLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "inference-gateway.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "inference-gateway.image" -}}
{{ printf "%s:%s@%s" .Values.image.repository .Values.image.tag .Values.image.digest }}
{{- end }}
