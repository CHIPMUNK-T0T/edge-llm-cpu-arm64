{{- define "edge-llm-monitoring.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: edge-llm
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
monitoring.edge-llm.io/stack: edge-llm
{{- end }}
