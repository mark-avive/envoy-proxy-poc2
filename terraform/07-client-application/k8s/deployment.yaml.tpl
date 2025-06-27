apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app_name}
  namespace: ${namespace}
  labels:
    app: ${app_name}
    component: websocket-client
    version: ${app_version}
spec:
  replicas: ${replicas}
  selector:
    matchLabels:
      app: ${app_name}
  template:
    metadata:
      labels:
        app: ${app_name}
        component: websocket-client
        version: ${app_version}
    spec:
      containers:
      - name: websocket-client
        image: IMAGE_REGISTRY_PLACEHOLDER
        ports:
        - containerPort: ${container_port}
          name: health
          protocol: TCP
        env:
        - name: ENVOY_ENDPOINT
          value: "ws://envoy-proxy-service.${namespace}.svc.cluster.local:80"
        - name: CLIENT_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: HEALTH_PORT
          value: "${container_port}"
        - name: MAX_CONNECTIONS
          value: "${max_connections}"
        - name: CONNECTION_INTERVAL
          value: "${connection_interval}"
        - name: MESSAGE_INTERVAL_MIN
          value: "${message_interval_min}"
        - name: MESSAGE_INTERVAL_MAX
          value: "${message_interval_max}"
        resources:
          requests:
            cpu: ${cpu_request}
            memory: ${memory_request}
          limits:
            cpu: ${cpu_limit}
            memory: ${memory_limit}
        livenessProbe:
          httpGet:
            path: /health
            port: ${container_port}
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: ${container_port}
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 3
          failureThreshold: 3
      restartPolicy: Always
      terminationGracePeriodSeconds: 30

---
apiVersion: v1
kind: Service
metadata:
  name: ${service_name}
  namespace: ${namespace}
  labels:
    app: ${app_name}
    component: websocket-client
spec:
  type: ClusterIP
  ports:
  - port: ${service_port}
    targetPort: ${container_port}
    protocol: TCP
    name: health
  selector:
    app: ${app_name}
