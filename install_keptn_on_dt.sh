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
KEPTN_BRIDGE_URL=$(kubectl get nodes --selector=kubernetes.io/role!=master -o jsonpath={.items[0].status.addresses[?\(@.type==\"ExternalIP\"\)].address}):31090/keptn/bridge

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

# Creates a sampleproject with a single stage called qualitygates
curl -X POST "${KEPTN_API_URL}/v1/project" -H "accept: application/json" -H "Content-Type: application/json" -H "x-token: ${KEPTN_API_TOKEN}" -d "{ \"name\": \"sampleproject\", \"shipyard\": \"c3RhZ2VzOg0KICAtIG5hbWU6ICJxdWFsaXR5Z2F0ZXMiDQo=\" }"
# Creates a sampleservice
curl -X POST "${KEPTN_API_URL}/v1/project/sampleproject/service" -H "accept: application/json" -H "Content-Type: application/json" -H "x-token: ${KEPTN_API_TOKEN}"  -d "{ \"serviceName\": \"sampleservice\", \"helmChart\": \"\"}"
# Create a dashboard
curl -X POST  "https://${DT_TENANT}/api/config/v1/dashboards/" -H "accept: application/json; charset=utf-8" -H "Authorization: Api-Token ${DT_API_TOKEN}" -H "Content-Type: application/json; charset=utf-8" -d "{\"metadata\":{\"configurationVersions\":[4,2],\"clusterVersion\":\"Mock version\"},\"dashboardMetadata\":{\"name\":\"Example Dashboard\",\"shared\":true,\"sharingDetails\":{\"linkShared\":true,\"published\":false},\"dashboardFilter\":{\"timeframe\":\"l_72_HOURS\",\"managementZone\":{\"id\":\"3438779970106539862\",\"name\":\"Example Management Zone\"}}},\"tiles\":[{\"name\":\"Hosts\",\"tileType\":\"HEADER\",\"configured\":true,\"bounds\":{\"top\":0,\"left\":0,\"width\":304,\"height\":38},\"tileFilter\":{}},{\"name\":\"Applications\",\"tileType\":\"HEADER\",\"configured\":true,\"bounds\":{\"top\":0,\"left\":304,\"width\":304,\"height\":38},\"tileFilter\":{}},{\"name\":\"Host health\",\"tileType\":\"HOSTS\",\"configured\":true,\"bounds\":{\"top\":38,\"left\":0,\"width\":304,\"height\":304},\"tileFilter\":{\"managementZone\":{\"id\":\"3438779970106539862\",\"name\":\"Example Management Zone\"}},\"chartVisible\":true},{\"name\":\"Application health\",\"tileType\":\"APPLICATIONS\",\"configured\":true,\"bounds\":{\"top\":38,\"left\":304,\"width\":304,\"height\":304},\"tileFilter\":{\"managementZone\":{\"id\":\"3438779970106539862\",\"name\":\"Example Management Zone\"}},\"chartVisible\":true}]}"
