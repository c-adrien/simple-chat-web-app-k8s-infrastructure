#! /bin/bash


# Check if the "trivy" flag is passed as an argument
TRIVY_FLAG=false

for arg in "$@"; do
  if [[ "$arg" == "--trivy" ]]; then
    TRIVY_FLAG=true
    break
  fi
done


# -------------------------------------------
# Create namespaces
# -------------------------------------------

kubectl create namespace web
kubectl create namespace monitoring
kubectl label namespace web name=web
kubectl label namespace monitoring name=monitoring


# -------------------------------------------
# Ingress controller
# -------------------------------------------


# Create the TLS certificate and key
KEY_FILE="tls-web.key"
CERT_FILE="tls-web.crt"
HOST="ma-messagerie.local"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -subj "/CN=${HOST}/O=${HOST}" -addext "subjectAltName = DNS:${HOST}"
kubectl create secret tls web-tls \
    --key $KEY_FILE \
    --cert $CERT_FILE \
    --namespace=web

# Upgrade or install the ingress-nginx controller
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Wait for the ingress-nginx-controller service to have EXTERNAL-IP set to localhost
while true; do
    EXTERNAL_IP=$(kubectl get service --namespace ingress-nginx ingress-nginx-controller)

    if [[ "$EXTERNAL_IP" == *"localhost"* ]]; then
        echo "EXTERNAL_IP is set to 'localhost'."
        break  # Exit the loop if 'localhost' is found
    else
        echo "Waiting for EXTERNAL_IP to be 'localhost'..."
        sleep 5  # Wait for 5 seconds before checking again
    fi
done

sleep 20

# Deploy ingress rule
# 1 - ma-messagerie.local -> backend web:80
# 2 - ssl termination
kubectl apply -f web-ingress.yml

# -------------------------------------------
# Web app & OpenSearch
# -------------------------------------------


# Deploy web app and nginx-exporter
kubectl apply -f web-deployment.yaml
kubectl apply -f nginx-exporter.yaml

# Create the opensearch secret from the env.sh file
kubectl create secret generic opensearch-secret \
    --from-literal=OPENSEARCH_INITIAL_ADMIN_PASSWORD=$OPENSEARCH_PASSWORD \
    --namespace=web

# Create the opensearch deployment
kubectl apply -f opensearch-deployment.yaml

# Create the job to create the opensearch index
# kubectl apply -f jobs/create-opensearch-index-job.yaml


# -------------------------------------------
# Prometheus & Grafana
# -------------------------------------------


# Create the prometheus configmap
kubectl create configmap prometheus-config --from-file=prometheus.yml=./configs/prometheus.yml --namespace=monitoring

# Create the prometheus deployment
kubectl apply -f prometheus-deployment.yaml
# Create the prometheus service
kubectl apply -f prometheus-service.yaml



# Create the grafana secret
kubectl create secret generic grafana-secret \
    --from-literal=GF_SECURITY_ADMIN_PASSWORD=$GF_SECURITY_ADMIN_PASSWORD \
    --namespace=monitoring

# Create the grafana provisioning configmap
kubectl create configmap grafana-provisioning \
     --from-file=./configs/grafana/provisioning/datasources/ \
     --from-file=./configs/grafana/provisioning/dashboards/ \
     --namespace=monitoring

# Create the grafana dashboards configmap
kubectl create configmap grafana-dashboards --from-file=./configs/grafana/dashboards/ --namespace=monitoring


# Create the grafana deployment
kubectl apply -f grafana-deployment.yaml
# Create the grafana service
kubectl apply -f grafana-service.yaml



# Create the TLS certificate and key
KEY_FILE="tls-grafana.key"
CERT_FILE="tls-grafana.crt"
HOST="grafana.local"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $KEY_FILE -out $CERT_FILE -subj "/CN=${HOST}/O=${HOST}" -addext "subjectAltName = DNS:${HOST}"
kubectl create secret tls grafana-tls \
    --key $KEY_FILE \
    --cert $CERT_FILE \
    --namespace=monitoring

# Deploy the grafana ingress
# 1 - grafana.local -> grafana:3000
# 2 - ssl termination
kubectl apply -f grafana-ingress.yaml



# -------------------------------------------
# Trivy
# -------------------------------------------

if [ "$TRIVY_FLAG" = true ]; then
    # Deploy the trivy operator
    kubectl apply -f https://raw.githubusercontent.com/aquasecurity/trivy-operator/v0.23.0/deploy/static/trivy-operator.yaml
fi


# # Get the vulnerability reports
# # Overview of all the vulnerabilities
# OUTPUT_FILE="vulnerability-reports.txt"

# kubectl get vulnerabilityreports --all-namespaces -o json | jq -r '
#   .items[] |
#   {
#     namespace: .metadata.namespace,
#     resource: .metadata.ownerReferences[0].name,
#     kind: .metadata.ownerReferences[0].kind,
#     vulnerabilities: .report.vulnerabilities[] | {cve: .vulnerabilityID, severity: .severity, package: .pkgName, installedVersion: .installedVersion, fixedVersion: .fixedVersion}
#   } |
#   "Namespace: \(.namespace)\nResource: \(.resource) (\(.kind))\nCVE: \(.vulnerabilities.cve)\nSeverity: \(.vulnerabilities.severity)\nPackage: \(.vulnerabilities.package)\nInstalled: \(.vulnerabilities.installedVersion)\nFixed: 
# \(.vulnerabilities.fixedVersion)\n---"' > $OUTPUT_FILE


# -------------------------------------------
# Network policies
# -------------------------------------------

# Deny all ingress
kubectl apply -f network-policies/deny-all-ingress-web-monitoring.yaml

# Allow web to prometheus
kubectl apply -f network-policies/web-to-prometheus.yaml
# Allow prometheus to all web
kubectl apply -f network-policies/prometheus-to-all-web.yaml
# Allow ingress-nginx to web and monitoring
kubectl apply -f network-policies/nginx-controller-to-services.yaml

if [ "$TRIVY_FLAG" = true ]; then
    # Allow trivy-operator to web and monitoring
    kubectl apply -f network-policies/allow-trivy-operator.yaml
fi


echo "Setup completed successfully."