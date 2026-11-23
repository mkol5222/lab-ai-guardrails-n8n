{{- define "n8n.name" -}}{{ .Release.Name }}{{- end -}}
{{- define "n8n.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- define "n8n.selector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "n8n.url" -}}https://{{ .Values.host }}{{ if ne (int .Values.localPort) 443 }}:{{ .Values.localPort }}{{ end }}/{{- end -}}
