#!/bin/bash
set -e

# Configuration - adjust these if needed
CLUSTER_NAME="gas-fakes-test-cluster"
REGION="europe-west1" # Matches deploy-k8s.sh

usage() {
    echo "Usage: $0 [up|down|get-credentials]"
    echo "  up               - Create a temporary GKE Autopilot cluster"
    echo "  down             - Delete the GKE Autopilot cluster"
    echo "  get-credentials  - Configure kubectl to point to the cluster"
    exit 1
}

case "$1" in
    up)
        echo "--- Creating GKE Autopilot Cluster: $CLUSTER_NAME ---"
        gcloud container clusters create-auto "$CLUSTER_NAME" \
            --region "$REGION" \
            --quiet
        
        echo "--- Getting Cluster Credentials ---"
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION"
        ;;
    down)
        echo "--- Deleting GKE Autopilot Cluster: $CLUSTER_NAME ---"
        gcloud container clusters delete "$CLUSTER_NAME" \
            --region "$REGION" \
            --quiet
        ;;
    get-credentials)
        echo "--- Getting Cluster Credentials ---"
        gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION"
        ;;
    *)
        usage
        ;;
esac
