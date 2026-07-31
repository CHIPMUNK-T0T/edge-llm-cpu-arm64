{{- define "north-mini-code.fullname" -}}
{{- .Release.Name -}}
{{- end }}

{{- define "north-mini-code.modelPvcName" -}}
{{- printf "%s-model" (include "north-mini-code.fullname" .) -}}
{{- end }}

{{- define "north-mini-code.commonLabels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: north-mini-code
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: edge-llm-platform
{{- end }}

{{- define "north-mini-code.selectorLabels" -}}
app.kubernetes.io/name: north-mini-code
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: inference
{{- end }}
