apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app_name}
  namespace: ${namespace}
  labels:
    app: ${app_name}
    component: websocket-server
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
        component: websocket-server
        version: ${app_version}
    spec:
      containers:
      - name: websocket-server
        image: ${ecr_repository_url}:${image_tag}
        ports:
        - containerPort: ${container_port}
          name: websocket
          protocol: TCP
        - containerPort: ${health_port}
          name: health
          protocol: TCP
        env:
        - name: SERVER_HOST
          value: "0.0.0.0"
        - name: SERVER_PORT
          value: "${container_port}"
        - name: POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
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
            port: ${health_port}
            scheme: HTTP
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: ${health_port}
            scheme: HTTP
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        securityContext:
          runAsNonRoot: true
          runAsUser: 1001
          runAsGroup: 1001
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: false
          capabilities:
            drop:
            - ALL
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
    component: websocket-server
spec:
  type: ClusterIP
  ports:
  - port: ${service_port}
    targetPort: ${container_port}
    protocol: TCP
    name: websocket
  selector:
    app: ${app_name}
