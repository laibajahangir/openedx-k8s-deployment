#!/bin/bash

# OpenEdX Kubernetes Deployment Script
# Automation script for assessment requirement

set -e

echo "========================================="
echo "OpenEdX Kubernetes Deployment Automation"
echo "========================================="

# Configuration
NAMESPACE="openedx"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="deployment_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a $LOG_FILE
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a $LOG_FILE
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a $LOG_FILE
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    command -v kubectl >/dev/null 2>&1 || error "kubectl is required but not installed."
    command -v helm >/dev/null 2>&1 || warn "helm not installed (optional)."
    command -v aws >/dev/null 2>&1 || warn "aws CLI not installed (optional for AWS)."
    
    kubectl cluster-info >/dev/null 2>&1 || error "Kubernetes cluster is not accessible."
    log "Prerequisites check passed."
}

# Create namespace
create_namespace() {
    log "Creating namespace: $NAMESPACE"
    kubectl apply -f kubernetes/namespaces/openedx-namespace.yaml || error "Failed to create namespace"
}

# Apply storage
apply_storage() {
    log "Applying persistent storage configurations..."
    kubectl apply -f kubernetes/storage/ || error "Failed to apply storage"
}

# Apply configurations
apply_configs() {
    log "Applying ConfigMaps..."
    kubectl apply -f kubernetes/configmaps/ || error "Failed to apply ConfigMaps"
}

# Deploy applications
deploy_apps() {
    log "Deploying OpenEdX applications..."
    
    # Deploy LMS
    log "Deploying LMS..."
    kubectl apply -f kubernetes/deployments/lms-deployment.yaml || error "LMS deployment failed"
    kubectl apply -f kubernetes/services/lms-service.yaml || error "LMS service failed"
    
    # Deploy CMS
    log "Deploying CMS..."
    kubectl apply -f kubernetes/deployments/cms-deployment.yaml || error "CMS deployment failed"
    kubectl apply -f kubernetes/services/cms-service.yaml || error "CMS service failed"
}

# Apply autoscaling
apply_autoscaling() {
    log "Applying Horizontal Pod Autoscaling..."
    kubectl apply -f kubernetes/hpa/ || error "HPA configuration failed"
}

# Apply ingress
apply_ingress() {
    log "Applying Ingress configuration..."
    kubectl apply -f kubernetes/ingress/ || error "Ingress configuration failed"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check pods
    log "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    
    # Check services
    log "Checking service status..."
    kubectl get svc -n $NAMESPACE
    
    # Check ingress
    log "Checking ingress..."
    kubectl get ingress -n $NAMESPACE
    
    # Check HPA
    log "Checking HPA..."
    kubectl get hpa -n $NAMESPACE
    
    log "Deployment verification completed."
}

# Health check
health_check() {
    log "Running health checks..."
    
    # Simple curl check if external IP is available
    if kubectl get svc -n $NAMESPACE | grep -q "LoadBalancer"; then
        EXTERNAL_IP=$(kubectl get svc -n $NAMESPACE | grep LoadBalancer | awk '{print $4}')
        if [[ $EXTERNAL_IP != "<pending>" ]]; then
            log "Testing external endpoint: http://$EXTERNAL_IP"
            curl -I --max-time 10 http://$EXTERNAL_IP 2>/dev/null | head -1 || warn "Endpoint not responding"
        fi
    fi
    
    log "Health checks completed."
}

# Main deployment function
main() {
    log "Starting OpenEdX deployment on Kubernetes"
    
    check_prerequisites
    create_namespace
    apply_storage
    apply_configs
    deploy_apps
    apply_autoscaling
    apply_ingress
    sleep 30  # Wait for resources to initialize
    verify_deployment
    health_check
    
    log "========================================="
    log "Deployment completed successfully!"
    log "Log file: $LOG_FILE"
    log "To check status: kubectl get all -n $NAMESPACE"
    log "========================================="
}

# Help function
show_help() {
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  deploy     - Deploy OpenEdX on Kubernetes (default)"
    echo "  verify     - Verify current deployment"
    echo "  clean      - Clean up deployment"
    echo "  help       - Show this help message"
}

# Clean up function
cleanup() {
    log "Cleaning up deployment..."
    kubectl delete -f kubernetes/ingress/
    kubectl delete -f kubernetes/hpa/
    kubectl delete -f kubernetes/services/
    kubectl delete -f kubernetes/deployments/
    kubectl delete -f kubernetes/configmaps/
    kubectl delete -f kubernetes/storage/
    kubectl delete namespace $NAMESPACE
    log "Cleanup completed."
}

# Parse arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    verify)
        verify_deployment
        ;;
    clean|cleanup)
        cleanup
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
