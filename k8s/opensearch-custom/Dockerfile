# Use the official OpenSearch image as the base image
FROM opensearchproject/opensearch:2.17.1

# Install the Prometheus exporter plugin
RUN ./bin/opensearch-plugin install https://github.com/aiven/prometheus-exporter-plugin-for-opensearch/releases/download/2.17.1.0/prometheus-exporter-2.17.1.0.zip
