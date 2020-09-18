#!/bin/bash

# Prerequisites: Helm3, kubectl, base64, curl

helm upgrade keptn keptn --install -n keptn --create-namespace --wait --version=0.7.2 --set=control-plane.apiGatewayNginx.type=NodePort,control-plane.bridge.secret.enabled=false,control-plane.apiGatewayNginx.nodePort=31090,control-plane.prefixPath=/keptn
kubectl create configmap lighthouse-config -n keptn --from-literal=sli-provider=dynatrace

# Create master API token and use it in order to get DT-AP-Token
DT_API_TOKEN=
DT_TENANT=
# TODO: Insert here the Keptn API URL
KEPTN_API_URL=http://$(kubectl get nodes --selector=kubernetes.io/role!=master -o jsonpath={.items[0].status.addresses[?\(@.type==\"ExternalIP\"\)].address}):31090/keptn/api
KEPTN_API_TOKEN=$(kubectl get secret keptn-api-token -n keptn -ojsonpath={.data.keptn-api-token} | base64 --decode)
KEPTN_BRIDGE_URL=http://$(kubectl get nodes --selector=kubernetes.io/role!=master -o jsonpath={.items[0].status.addresses[?\(@.type==\"ExternalIP\"\)].address}):31090/keptn/bridge

kubectl -n keptn create secret generic dynatrace --from-literal="DT_API_TOKEN=$DT_API_TOKEN" --from-literal="DT_TENANT=$DT_TENANT" --from-literal="KEPTN_API_URL=$KEPTN_API_URL" --from-literal="KEPTN_API_TOKEN=$KEPTN_API_TOKEN" --from-literal="KEPTN_BRIDGE_URL=$KEPTN_BRIDGE_URL" -oyaml --dry-run | kubectl replace -f -

# Install dynatrace-service
cat <<EOF | kubectl apply -n keptn -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keptn-dynatrace-service
  labels:
    "app": "keptn"

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: keptn-dynatrace-service-secrets
  labels:
    "app": "keptn"
rules:
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - get
      - list
      - watch

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: keptn-dynatrace-service-secrets
  labels:
    "app": "keptn"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: keptn-dynatrace-service-secrets
subjects:
  - kind: ServiceAccount
    name: keptn-dynatrace-service

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynatrace-service
spec:
  selector:
    matchLabels:
      run: dynatrace-service
  replicas: 1
  template:
    metadata:
      labels:
        run: dynatrace-service
    spec:
      serviceAccountName: keptn-dynatrace-service
      containers:
        - name: dynatrace-service
          image: keptncontrib/dynatrace-service:bc8c823    # TODO: Set here the latest version
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "32Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "200m"
          env:
            - name: API_WEBSOCKET_URL
              value: 'ws://api-service:8080/websocket'
            - name: EVENTBROKER
              value: 'http://event-broker/keptn'
            - name: DATASTORE
              value: 'http://mongodb-datastore:8080'
            - name: PLATFORM
              value: kubernetes
            - name: DT_API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: dynatrace
                  key: DT_API_TOKEN
            - name: DT_TENANT
              valueFrom:
                secretKeyRef:
                  name: dynatrace
                  key: DT_TENANT
            - name: KEPTN_API_URL
              valueFrom:
                secretKeyRef:
                  name: dynatrace
                  key: KEPTN_API_URL
            - name: KEPTN_API_TOKEN
              valueFrom:
                secretKeyRef:
                  name: dynatrace
                  key: KEPTN_API_TOKEN
            - name: KEPTN_BRIDGE_URL
              valueFrom:
                secretKeyRef:
                  name: dynatrace
                  key: KEPTN_BRIDGE_URL
                  optional: true
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: GENERATE_TAGGING_RULES
              value: 'false'
            - name: GENERATE_PROBLEM_NOTIFICATIONS
              value: 'false'
            - name: GENERATE_MANAGEMENT_ZONES
              value: 'false'
            - name: GENERATE_DASHBOARDS
              value: 'false'
            - name: GENERATE_METRIC_EVENTS
              value: 'false'
        - name: distributor
          image: keptn/distributor:0.7.2
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "32Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "500m"
          env:
            - name: PUBSUB_URL
              value: 'nats://keptn-nats-cluster'
            - name: PUBSUB_TOPIC
              value: 'sh.keptn.>'
            - name: PUBSUB_RECIPIENT
              value: '127.0.0.1'
---
apiVersion: v1
kind: Service
metadata:
  name: dynatrace-service
  labels:
    run: dynatrace-service
spec:
  ports:
    - port: 8080
      protocol: TCP
  selector:
    run: dynatrace-service
EOF

# Install dynatrace-sli-service
cat <<EOF | kubectl apply -n keptn -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: keptn-dynatrace-sli-service
  labels:
    "app": "keptn"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: keptn-dynatrace-sli-service-secrets
  labels:
    "app": "keptn"
rules:
  - apiGroups:
      - ""
    resources:
      - secrets
    verbs:
      - get
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: keptn-dynatrace-sli-service-secrets
  labels:
    "app": "keptn"
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: keptn-dynatrace-sli-service-secrets
subjects:
  - kind: ServiceAccount
    name: keptn-dynatrace-sli-service
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dynatrace-sli-service
spec:
  selector:
    matchLabels:
      run: dynatrace-sli-service
  replicas: 1
  template:
    metadata:
      labels:
        run: dynatrace-sli-service
    spec:
      serviceAccountName: keptn-dynatrace-sli-service
      containers:
        - name: dynatrace-sli-service
          image: keptncontrib/dynatrace-sli-service:0902645      # TODO: set here the latest version
          imagePullPolicy: Always
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "32Mi"
              cpu: "50m"
            limits:
              memory: "256Mi"
              cpu: "500m"
          env:
            - name: CONFIGURATION_SERVICE
              value: 'http://configuration-service:8080'
            - name: EVENTBROKER
              value: 'http://event-broker/keptn'
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
        - name: distributor
          image: keptn/distributor:0.7.2
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "32Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "500m"
          env:
            - name: PUBSUB_URL
              value: 'nats://keptn-nats-cluster'
            - name: PUBSUB_TOPIC
              value: 'sh.keptn.internal.event.get-sli'
            - name: PUBSUB_RECIPIENT
              value: '127.0.0.1'
---
apiVersion: v1
kind: Service
metadata:
  name: dynatrace-sli-service
  labels:
    run: dynatrace-sli-service
spec:
  ports:
    - port: 8080
      protocol: TCP
  selector:
    run: dynatrace-sli-service
EOF

KEPTN_PROJECT=sampleproject
KEPTN_SERVICE=sampleservice
KEPTN_STAGE=qualitygates

KEPTN_BRIDGE_PROJECT=$KEPTN_BRIDGE_URL/project/$KEPTN_PROJECT

# Creates a sampleproject with a single stage called qualitygates
curl -X POST "${KEPTN_API_URL}/v1/project" -H "accept: application/json" -H "Content-Type: application/json" -H "x-token: ${KEPTN_API_TOKEN}" -d "{ \"name\": \"${KEPTN_PROJECT}\", \"shipyard\": \"c3RhZ2VzOg0KICAtIG5hbWU6ICJxdWFsaXR5Z2F0ZXMiDQo=\" }"
# Creates a sampleservice
curl -X POST "${KEPTN_API_URL}/v1/project/${KEPTN_PROJECT}/service" -H "accept: application/json" -H "Content-Type: application/json" -H "x-token: ${KEPTN_API_TOKEN}"  -d "{ \"serviceName\": \"${KEPTN_SERVICE}\", \"helmChart\": \"\"}"
# Create a dashboard
curl -X POST  "https://${DT_TENANT}/api/config/v1/dashboards/" -H "accept: application/json; charset=utf-8" -H "Authorization: Api-Token ${DT_API_TOKEN}" -H "Content-Type: application/json; charset=utf-8" -d "{\"dashboardMetadata\":{\"name\":\"KQG;project=${KEPTN_PROJECT};service=${KEPTN_SERVICE};stage=${KEPTN_STAGE}\",\"shared\":false,\"owner\":\"\",\"sharingDetails\":{\"linkShared\":true,\"published\":false},\"dashboardFilter\":{\"timeframe\":\"\"}},\"tiles\":[{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":646,\"left\":760,\"width\":418,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Worker Process Count (Avg);sli=proc_count;\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:tech.generic.processCount\",\"aggregation\":\"AVG\",\"type\":\"LINE\",\"entityType\":\"PROCESS_GROUP_INSTANCE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":114,\"left\":0,\"width\":2052,\"height\":38},\"tileFilter\":{},\"markdown\":\"KQG.Total.Pass=90%;KQG.Total.Warning=70%;KQG.Compare.WithScore=pass;KQG.Compare.Results=1;KQG.Compare.Function=avg\"},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":190,\"left\":0,\"width\":380,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Response time (P95);sli=svc_rt_p95;pass=<+10%,<600\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:service.response.time\",\"aggregation\":\"PERCENTILE\",\"percentile\":95,\"type\":\"LINE\",\"entityType\":\"SERVICE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":418,\"left\":0,\"width\":380,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Response time (P90);sli=svc_rt_p90;pass=<+10%,<550\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:service.response.time\",\"aggregation\":\"PERCENTILE\",\"percentile\":90,\"type\":\"LINE\",\"entityType\":\"SERVICE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":646,\"left\":0,\"width\":380,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Response time (P50);sli=svc_rt_p50;pass=<+10%,<500\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:service.response.time\",\"aggregation\":\"PERCENTILE\",\"percentile\":50,\"type\":\"LINE\",\"entityType\":\"SERVICE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":152,\"left\":0,\"width\":380,\"height\":38},\"tileFilter\":{},\"markdown\":\"## Service Performance (SLI/SLO)\"},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":152,\"left\":1178,\"width\":418,\"height\":38},\"tileFilter\":{},\"markdown\":\"## Host-based (SLI/SLO)\"},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":152,\"left\":760,\"width\":418,\"height\":38},\"tileFilter\":{},\"markdown\":\"## Process Metrics (SLI/SLO)\"},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":418,\"left\":760,\"width\":418,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Process Memory;sli=process_memory\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:tech.generic.mem.workingSetSize\",\"aggregation\":\"AVG\",\"type\":\"LINE\",\"entityType\":\"PROCESS_GROUP_INSTANCE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":190,\"left\":760,\"width\":418,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Process CPU;sli=process_cpu;pass=<20;warning=<50;key=false\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:tech.generic.cpu.usage\",\"aggregation\":\"AVG\",\"type\":\"LINE\",\"entityType\":\"PROCESS_GROUP_INSTANCE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":152,\"left\":380,\"width\":380,\"height\":38},\"tileFilter\":{},\"markdown\":\"## Service Errors & Throughput (SLI/SLO)\"},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":190,\"left\":380,\"width\":380,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Failure Rate (Avg);sli=svc_fr;pass=<+10%,<2\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:service.errors.server.rate\",\"aggregation\":\"AVG\",\"type\":\"LINE\",\"entityType\":\"SERVICE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":418,\"left\":380,\"width\":380,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Throughput (per min);sli=svc_tp_min;pass=<+10%,<200\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:service.requestCount.total\",\"aggregation\":\"NONE\",\"type\":\"LINE\",\"entityType\":\"SERVICE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"MINUTE\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":152,\"left\":1596,\"width\":456,\"height\":38},\"tileFilter\":{},\"markdown\":\"## Test Transaction (SLI/SLO)\"},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":190,\"left\":1178,\"width\":418,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Host CPU %;sli=host_cpu;pass=<20;warning=<50;key=false\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:host.cpu.usage\",\"aggregation\":\"AVG\",\"type\":\"LINE\",\"entityType\":\"HOST\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":418,\"left\":1178,\"width\":418,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Host Memory used %;sli=host_mem;pass=<20;warning=<50;key=false\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:host.mem.usage\",\"aggregation\":\"AVG\",\"type\":\"LINE\",\"entityType\":\"HOST\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":646,\"left\":1178,\"width\":418,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Host Disk Queue Length (max);sli=host_disk_queue;pass=<=0;warning=<1;key=false\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:host.disk.queueLength\",\"aggregation\":\"MAX\",\"type\":\"LINE\",\"entityType\":\"HOST\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"TOTAL\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Custom chart\",\"tileType\":\"CUSTOM_CHARTING\",\"configured\":true,\"bounds\":{\"top\":646,\"left\":380,\"width\":380,\"height\":228},\"tileFilter\":{},\"filterConfig\":{\"type\":\"MIXED\",\"customName\":\"Calls to backend services (per min);sli=svc2svc_calls;\",\"defaultName\":\"Custom chart\",\"chartConfig\":{\"legendShown\":true,\"type\":\"SINGLE_VALUE\",\"series\":[{\"metric\":\"builtin:service.nonDbChildCallCount\",\"aggregation\":\"NONE\",\"type\":\"LINE\",\"entityType\":\"SERVICE\",\"dimensions\":[],\"sortAscending\":false,\"sortColumn\":true,\"aggregationRate\":\"MINUTE\"}],\"resultMetadata\":{}},\"filtersPerEntityType\":{}}},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":190,\"left\":1596,\"width\":456,\"height\":152},\"tileFilter\":{},\"markdown\":\"## Extend with Test Transactions\\n\\n\\nFollow the best practices around SRE-driven Performance Engineering as described in this [blog](https://www.dynatrace.com/news/blog/guide-to-automated-sre-driven-performance-engineering-analysis/)\\n\\nThis will allow you to add metrics per test or business transaction.\"},{\"name\":\"Markdown\",\"tileType\":\"MARKDOWN\",\"configured\":true,\"bounds\":{\"top\":0,\"left\":0,\"width\":2052,\"height\":114},\"tileFilter\":{},\"markdown\":\"## Welcome to your first SLI/SLO-based Quality Gate Dashboard - view results in your [Keptn Bridge](${KEPTN_BRIDGE_PROJECT})\\n \\nThis default dashboard includes a set of base metrics (SLIs) that produce values in any Dynatrace deployment. \\nUse this to make yourself familiar with defining your own SLIs (by adding more custom charts) and how to define SLOs (as part of the chart title) for every metric.\\nThis default chart does not split by metric dimensions such as service, process, or host; however, splitting is supported by Keptn and is encouraged.\\nFor more best practices on how to create these SLI/SLO dashboards please have a look at the [Dynatrace-SLI-Service readme](https://github.com/keptn-contrib/dynatrace-sli-service).\"}]}"