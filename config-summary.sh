#!/bin/bash
# Envoy Proxy POC - Configuration Summary Script
# Location: /home/mark/workareas/github/envoy-proxy-poc2/config-summary.sh
# Purpose: Display current configuration from all locals.tf files across sections

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${BLUE}            ENVOY PROXY POC - CONFIGURATION SUMMARY${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${CYAN}Timestamp: $(date)${NC}"
    echo ""
}

print_section() {
    echo -e "${PURPLE}$1${NC}"
    echo "---------------------------------------------------------------------"
}

get_envoy_config() {
    print_section "🔧 ENVOY PROXY CONFIGURATION (Section 06)"
    
    if [ -f "terraform/06-envoy-proxy/locals.tf" ]; then
        echo -e "${CYAN}Circuit Breaker Settings:${NC}"
        grep -A 4 "Circuit Breaker" terraform/06-envoy-proxy/locals.tf | grep -v "Circuit Breaker" | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
        
        echo ""
        echo -e "${CYAN}Rate Limiting Settings:${NC}"
        grep -A 4 "Rate Limiting" terraform/06-envoy-proxy/locals.tf | grep -v "Rate Limiting" | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
    else
        echo -e "${RED}  ❌ Envoy locals.tf not found${NC}"
    fi
    echo ""
}

get_server_config() {
    print_section "🖥️  SERVER APPLICATION CONFIGURATION (Section 05)"
    
    if [ -f "terraform/05-server-application/locals.tf" ]; then
        echo -e "${CYAN}Application Settings:${NC}"
        grep -E "(replicas|container_port)" terraform/05-server-application/locals.tf | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
        
        echo ""
        echo -e "${CYAN}Resource Limits:${NC}"
        grep -A 4 "Resource Limits" terraform/05-server-application/locals.tf | grep -v "Resource Limits" | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
    else
        echo -e "${RED}  ❌ Server locals.tf not found${NC}"
    fi
    echo ""
}

get_client_config() {
    print_section "📱 CLIENT APPLICATION CONFIGURATION (Section 07)"
    
    if [ -f "terraform/07-client-application/locals.tf" ]; then
        echo -e "${CYAN}Application Settings:${NC}"
        grep -E "(replicas|container_port)" terraform/07-client-application/locals.tf | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
        
        echo ""
        echo -e "${CYAN}Client Behavior Settings:${NC}"
        grep -A 6 "Client Behavior Configuration" terraform/07-client-application/locals.tf | grep -v "Client Behavior Configuration" | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
        
        echo ""
        echo -e "${CYAN}Resource Limits:${NC}"
        grep -A 4 "Resource Limits" terraform/07-client-application/locals.tf | grep -v "Resource Limits" | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
    else
        echo -e "${RED}  ❌ Client locals.tf not found${NC}"
    fi
    echo ""
}

get_networking_config() {
    print_section "🌐 NETWORKING CONFIGURATION (Section 02)"
    
    if [ -f "terraform/02-networking/locals.tf" ]; then
        echo -e "${CYAN}VPC Settings:${NC}"
        grep -E "(vpc_cidr|availability_zones)" terraform/02-networking/locals.tf | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
        
        echo ""
        echo -e "${CYAN}Subnet Configuration:${NC}"
        grep -E "(public_subnet_cidrs|private_subnet_cidrs)" terraform/02-networking/locals.tf | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
    else
        echo -e "${RED}  ❌ Networking locals.tf not found${NC}"
    fi
    echo ""
}

get_eks_config() {
    print_section "☸️  EKS CLUSTER CONFIGURATION (Section 03)"
    
    if [ -f "terraform/03-eks-cluster/locals.tf" ]; then
        echo -e "${CYAN}Cluster Settings:${NC}"
        grep -E "(cluster_name|cluster_version)" terraform/03-eks-cluster/locals.tf | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
        
        echo ""
        echo -e "${CYAN}Node Group Settings:${NC}"
        grep -E "(node_instance_type|node_.*_capacity)" terraform/03-eks-cluster/locals.tf | \
        sed 's/^[ \t]*/  /' | sed 's/#.*//'
    else
        echo -e "${RED}  ❌ EKS locals.tf not found${NC}"
    fi
    echo ""
}

show_deployment_status() {
    print_section "🚀 DEPLOYMENT STATUS"
    
    echo -e "${CYAN}Terraform State Status:${NC}"
    
    # Check each section's terraform state
    sections=("02-networking" "03-eks-cluster" "04-ecr-repositories" "05-server-application" "06-envoy-proxy" "07-client-application")
    
    for section in "${sections[@]}"; do
        if [ -d "terraform/$section" ]; then
            cd "terraform/$section"
            if [ -f ".terraform/terraform.tfstate" ] || [ -f "terraform.tfstate" ]; then
                echo -e "  ${GREEN}✅ $section: Deployed${NC}"
            else
                echo -e "  ${YELLOW}⚠️  $section: Not deployed${NC}"
            fi
            cd - > /dev/null
        else
            echo -e "  ${RED}❌ $section: Directory not found${NC}"
        fi
    done
    
    echo ""
    echo -e "${CYAN}Kubernetes Resources:${NC}"
    
    # Check if kubectl is available and configured
    if command -v kubectl >/dev/null 2>&1; then
        kubectl get deployments -o wide 2>/dev/null | grep -E "(envoy-poc|NAME)" | \
        awk 'NR==1 {print "  " $0} NR>1 {print "  ✅ " $0}' || echo "  ⚠️  No deployments found or kubectl not configured"
    else
        echo -e "  ${YELLOW}⚠️  kubectl not available${NC}"
    fi
    echo ""
}

show_configuration_commands() {
    print_section "🔧 CONFIGURATION COMMANDS"
    
    echo -e "${CYAN}Quick Configuration Changes:${NC}"
    echo ""
    echo "  # Modify Envoy circuit breaker and rate limits:"
    echo "  vim terraform/06-envoy-proxy/locals.tf"
    echo "  cd terraform/06-envoy-proxy && terraform apply"
    echo ""
    echo "  # Modify client behavior (connections, intervals):"
    echo "  vim terraform/07-client-application/locals.tf" 
    echo "  cd terraform/07-client-application && terraform apply"
    echo ""
    echo "  # Modify server replicas and resources:"
    echo "  vim terraform/05-server-application/locals.tf"
    echo "  cd terraform/05-server-application && terraform apply"
    echo ""
    echo "  # Scale client pods for load testing:"
    echo "  # Edit replicas in terraform/07-client-application/locals.tf"
    echo ""
    echo "  # Test different scenarios:"
    echo "  # 1. High connection limit + Low rate limit = Test rate limiting"
    echo "  # 2. Low connection limit + High rate limit = Test circuit breaker"
    echo "  # 3. Many client pods + Normal limits = Test load distribution"
    echo ""
    
    echo -e "${CYAN}Monitoring Commands:${NC}"
    echo "  # Run comprehensive monitoring:"
    echo "  ./envoy-monitor.sh"
    echo ""
    echo "  # Continuous monitoring:"
    echo "  ./envoy-monitor.sh -w"
    echo ""
    echo "  # View this configuration summary:"
    echo "  ./config-summary.sh"
    echo ""
}

# Main execution
main() {
    print_header
    get_envoy_config
    get_server_config
    get_client_config
    get_networking_config
    get_eks_config
    show_deployment_status
    show_configuration_commands
    
    echo -e "${BLUE}=====================================================================${NC}"
    echo -e "${GREEN}✅ Configuration summary complete.${NC}"
    echo -e "${YELLOW}💡 Use ./envoy-monitor.sh to see live metrics and status.${NC}"
    echo -e "${BLUE}=====================================================================${NC}"
}

# Execute main function
main
