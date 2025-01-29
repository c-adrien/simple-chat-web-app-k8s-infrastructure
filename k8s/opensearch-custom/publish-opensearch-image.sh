#!/bin/bash

repo="$DOCKERHUB_USERNAME/opensearch-custom-prometheus-exporter"
tag="2.17.1"
directory="opensearch-custom"

# Log in to Docker
docker login

# Check if the login was successful
if [ $? -eq 0 ]; then
    echo "Docker login succeeded."

    docker build -t $repo:$tag ./$directory/
    docker push $repo:$tag

    echo "Docker image built and pushed successfully."
else
    echo "Docker login failed. Exiting."
    exit 1
fi
