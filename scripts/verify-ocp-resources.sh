#!/usr/bin/env bash

# Copyright (C) 2021-2024 Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Verify OpenShift resources and provide assertions for cluster validation
#
# This script checks for the presence of essential OpenShift resources
# and provides detailed verification of cluster configuration.
#
# Usage:
#   ./verify-ocp-resources.sh [--strict] [--verbose]
#
# Examples:
#   ./verify-ocp-resources.sh                    # Basic verification
#   ./verify-ocp-resources.sh --strict          # Strict mode with exit codes
#   ./verify-ocp-resources.sh --verbose         # Verbose output
#   ./verify-ocp-resources.sh --strict --verbose # Both strict and verbose

set -euo pipefail

# Default values
STRICT_MODE=false
VERBOSE_MODE=false
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_test() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

print_assertion() {
    echo -e "${PURPLE}[ASSERTION]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Verify OpenShift resources and provide assertions for cluster validation

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --strict     Exit with error code if any test fails
    --verbose    Provide detailed output for each test
    --help       Show this help message

EXAMPLES:
    $0                    # Basic verification
    $0 --strict          # Strict mode with exit codes
    $0 --verbose         # Verbose output
    $0 --strict --verbose # Both strict and verbose

DESCRIPTION:
    This script performs comprehensive verification of OpenShift cluster
    resources and configuration. It checks for:

    - API Groups and Resources
    - ClusterOperator resources
    - ClusterVersion resources
    - OLM (Operator Lifecycle Manager) resources
    - Node status and readiness
    - Authentication and authorization
    - Storage and networking components

    The script provides detailed feedback and can be used in CI/CD
    pipelines for cluster validation.
EOF
}

# Function to check if oc command is available
check_oc_command() {
    if ! command -v oc &> /dev/null; then
        print_error "oc command not found. Please install the OpenShift CLI."
        exit 1
    fi
}

# Function to check if connected to a cluster
check_cluster_connection() {
    if ! oc cluster-info &> /dev/null; then
        print_error "Not connected to a Kubernetes/OpenShift cluster."
        print_info "Please ensure you're connected to your cluster."
        exit 1
    fi
}

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-0}"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$VERBOSE_MODE" = true ]; then
        print_test "Running: $test_name"
        echo "Command: $test_command"
    fi
    
    if eval "$test_command" >/dev/null 2>&1; then
        if [ "$VERBOSE_MODE" = true ]; then
            print_success "PASS: $test_name"
        else
            print_success "✅ $test_name"
        fi
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        if [ "$VERBOSE_MODE" = true ]; then
            print_error "FAIL: $test_name"
        else
            print_error "❌ $test_name"
        fi
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Function to check API groups
check_api_groups() {
    print_info "Checking OpenShift API groups..."
    
    local api_groups=(
        "config.openshift.io"
        "console.openshift.io"
        "image.openshift.io"
        "project.openshift.io"
        "route.openshift.io"
        "security.openshift.io"
        "template.openshift.io"
        "user.openshift.io"
    )
    
    for group in "${api_groups[@]}"; do
        run_test "API Group: $group" "oc api-resources --api-group=$group --no-headers | head -1"
    done
    
    # Check OLM API group separately (may not be available in microshift)
    if oc api-resources --api-group=operators.coreos.com --no-headers &>/dev/null; then
        print_success "✅ API Group: operators.coreos.com"
    else
        print_warning "API Group: operators.coreos.com not available (expected in microshift)"
    fi
}

# Function to check ClusterOperator resources
check_cluster_operators() {
    print_info "Checking ClusterOperator resources..."
    
    # Check if ClusterOperator CRD exists (with retry for timing issues)
    local max_retries=3
    local retry_count=0
    local crd_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$crd_success" = false ]; do
        if oc get crd clusteroperators.config.openshift.io &>/dev/null; then
            crd_success=true
            break
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            print_warning "ClusterOperator CRD not ready, retrying in 5 seconds... (attempt $retry_count/$max_retries)"
            sleep 5
        fi
    done
    
    if [ "$crd_success" = true ]; then
        print_success "✅ ClusterOperator CRD exists"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "❌ ClusterOperator CRD exists"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check if we can list ClusterOperators (with retry for timing issues)
    local max_retries=3
    local retry_count=0
    local list_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$list_success" = false ]; do
        if oc get clusteroperators --no-headers &>/dev/null; then
            list_success=true
            break
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            print_warning "ClusterOperators not ready, retrying in 5 seconds... (attempt $retry_count/$max_retries)"
            sleep 5
        fi
    done
    
    if [ "$list_success" = true ]; then
        print_success "✅ Can list ClusterOperators"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "❌ Can list ClusterOperators"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check for specific ClusterOperators
    local expected_operators=(
        "openshift-apiserver"
        "openshift-controller-manager"
        "openshift-etcd"
        "openshift-kube-apiserver"
        "openshift-kube-controller-manager"
        "openshift-kube-scheduler"
    )
    
    for operator in "${expected_operators[@]}"; do
        run_test "ClusterOperator: $operator" "oc get clusteroperator $operator"
    done
    
    # Check ClusterOperator status
    if oc get clusteroperator openshift-apiserver &>/dev/null; then
        run_test "openshift-apiserver is Available" "oc get clusteroperator openshift-apiserver -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -q True"
        run_test "openshift-apiserver is not Degraded" "oc get clusteroperator openshift-apiserver -o jsonpath='{.status.conditions[?(@.type==\"Degraded\")].status}' | grep -q False"
    fi
}

# Function to check ClusterVersion resources
check_cluster_version() {
    print_info "Checking ClusterVersion resources..."
    
    # Check if ClusterVersion CRD exists
    run_test "ClusterVersion CRD exists" "oc get crd clusterversions.config.openshift.io"
    
    # Check if ClusterVersion resource exists
    run_test "ClusterVersion resource exists" "oc get clusterversion version"
    
    # Check ClusterVersion status
    if oc get clusterversion version &>/dev/null; then
        run_test "ClusterVersion is Available" "oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -q True"
        run_test "ClusterVersion is not Progressing" "oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type==\"Progressing\")].status}' | grep -q False"
        
        # Get and display version information
        local version
        version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
        print_info "Detected OpenShift version: $version"
    fi
}

# Function to check OLM resources
check_olm_resources() {
    print_info "Checking OLM (Operator Lifecycle Manager) resources..."
    
    # Detect if we're running in microshift mode
    local is_microshift=false
    if oc get clusteroperator openshift-apiserver &>/dev/null; then
        local created_by
        created_by=$(oc get clusteroperator openshift-apiserver -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
        if [[ "$created_by" == "certsuite-microshift-setup-script" ]]; then
            is_microshift=true
        fi
    fi
    
    # Check if OLM API group has any resources
    local olm_resources_count
    olm_resources_count=$(oc api-resources --api-group=operators.coreos.com --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$olm_resources_count" -eq 0 ]; then
        if [ "$is_microshift" = true ]; then
            print_info "OLM API group has no resources (expected in microshift)"
            print_info "Skipping OLM resource checks for microshift compatibility"
        else
            print_warning "OLM API group has no resources"
            print_info "Skipping OLM resource checks"
        fi
        return 0
    fi
    
    local olm_crds=(
        "catalogsources.operators.coreos.com"
        "clusterserviceversions.operators.coreos.com"
        "subscriptions.operators.coreos.com"
        "installplans.operators.coreos.com"
    )
    
    for crd in "${olm_crds[@]}"; do
        run_test "OLM CRD: $crd" "oc get crd $crd"
    done
    
    # Check if we can list OLM resources
    run_test "Can list CatalogSources" "oc get catalogsources --all-namespaces --no-headers | head -1"
    run_test "Can list ClusterServiceVersions" "oc get clusterserviceversions --all-namespaces --no-headers | head -1"
    run_test "Can list Subscriptions" "oc get subscriptions --all-namespaces --no-headers | head -1"
}

# Function to check node status
check_node_status() {
    print_info "Checking node status..."
    
    # Check if we can list nodes
    run_test "Can list nodes" "oc get nodes --no-headers | head -1"
    
    # Check node readiness
    run_test "All nodes are Ready" "oc get nodes -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' | grep -v False"
    
    # Check node count
    local node_count
    node_count=$(oc get nodes --no-headers | wc -l)
    print_info "Node count: $node_count"
    
    if [ "$node_count" -gt 0 ]; then
        print_success "✅ Nodes are available"
    else
        print_error "❌ No nodes found"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Function to check authentication and authorization
check_auth_resources() {
    print_info "Checking authentication and authorization..."
    
    # Check for authentication operator
    run_test "Authentication operator exists" "oc get clusteroperator authentication"
    
    # Check for OAuth server
    run_test "OAuth server exists" "oc get oauth cluster"
    
    # Check for default service accounts
    run_test "Default service accounts exist" "oc get serviceaccount default -n default"
    
    # Check for admin user
    run_test "Can get current user" "oc whoami"
}

# Function to check storage and networking
check_storage_networking() {
    print_info "Checking storage and networking components..."
    
    # Check for storage classes
    run_test "Storage classes exist" "oc get storageclass --no-headers | head -1"
    
    # Check for persistent volumes
    run_test "Can list persistent volumes" "oc get pv --no-headers | head -1"
    
    # Check for routes
    run_test "Route CRD exists" "oc get crd routes.route.openshift.io"
    
    # Check for ingress controllers
    run_test "Ingress controller exists" "oc get clusteroperator ingress"
}

# Function to check console and web UI
check_console_resources() {
    print_info "Checking console and web UI resources..."
    
    # Check for console operator
    run_test "Console operator exists" "oc get clusteroperator console"
    
    # Check for console deployment (if not scaled down)
    if oc get deployment console -n openshift-console &>/dev/null; then
        run_test "Console deployment exists" "oc get deployment console -n openshift-console"
    else
        print_warning "Console deployment not found (may be scaled down)"
    fi
}

# Function to check project and namespace resources
check_project_resources() {
    print_info "Checking project and namespace resources..."
    
    # Check for project CRD
    run_test "Project CRD exists" "oc get crd projects.project.openshift.io"
    
    # Check for default namespace
    run_test "Default namespace exists" "oc get namespace default"
    
    # Detect if we're running in microshift mode
    local is_microshift=false
    if oc get clusteroperator openshift-apiserver &>/dev/null; then
        local created_by
        created_by=$(oc get clusteroperator openshift-apiserver -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
        if [[ "$created_by" == "certsuite-microshift-setup-script" ]]; then
            is_microshift=true
            print_info "Detected microshift mode - adjusting namespace checks"
        fi
    fi
    
    if [ "$is_microshift" = true ]; then
        # In microshift mode, only check for namespaces that actually exist
        local microshift_namespaces=(
            "openshift-controller-manager"
            "openshift-dns"
            "openshift-infra"
            "openshift-ingress"
            "openshift-kube-controller-manager"
        )
        
        for ns in "${microshift_namespaces[@]}"; do
            run_test "Namespace: $ns" "oc get namespace $ns"
        done
        
        # Skip namespaces that don't exist in microshift
        print_info "Skipping microshift-incompatible namespaces: openshift-marketplace, openshift-ovn-kubernetes, openshift-route-controller-manager, openshift-service-ca, openshift-storage"
    else
        # Check for openshift namespaces (full OpenShift distribution)
        local openshift_namespaces=(
            "openshift-controller-manager"
            "openshift-dns"
            "openshift-infra"
            "openshift-ingress"
            "openshift-kube-controller-manager"
            "openshift-marketplace"
            "openshift-ovn-kubernetes"
            "openshift-route-controller-manager"
            "openshift-service-ca"
            "openshift-storage"
        )
        
        for ns in "${openshift_namespaces[@]}"; do
            run_test "Namespace: $ns" "oc get namespace $ns"
        done
    fi
}

# Function to check image registry
check_image_registry() {
    print_info "Checking image registry..."
    
    # Check for image registry operator
    run_test "Image registry operator exists" "oc get clusteroperator image-registry"
    
    # Check for image registry deployment
    if oc get deployment image-registry -n openshift-image-registry &>/dev/null; then
        run_test "Image registry deployment exists" "oc get deployment image-registry -n openshift-image-registry"
    else
        print_warning "Image registry deployment not found"
    fi
}

# Function to check monitoring and logging
check_monitoring_logging() {
    print_info "Checking monitoring and logging..."
    
    # Check for monitoring operator
    run_test "Monitoring operator exists" "oc get clusteroperator monitoring"
    
    # Check for logging operator
    run_test "Logging operator exists" "oc get clusteroperator logging"
    
    # Check for prometheus
    if oc get prometheus k8s -n openshift-monitoring &>/dev/null; then
        run_test "Prometheus exists" "oc get prometheus k8s -n openshift-monitoring"
    else
        print_warning "Prometheus not found"
    fi
}

# Function to check security and compliance
check_security_compliance() {
    print_info "Checking security and compliance..."
    
    # Check for security context constraints (with retry for timing issues)
    local max_retries=3
    local retry_count=0
    local scc_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$scc_success" = false ]; do
        if oc get scc --no-headers &>/dev/null; then
            scc_success=true
            break
        fi
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            print_warning "Security context constraints not ready, retrying in 5 seconds... (attempt $retry_count/$max_retries)"
            sleep 5
        fi
    done
    
    if [ "$scc_success" = true ]; then
        print_success "✅ Security context constraints exist"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_error "❌ Security context constraints exist"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Check for security operator
    run_test "Security operator exists" "oc get clusteroperator security"
    
    # Check for compliance operator
    run_test "Compliance operator exists" "oc get clusteroperator compliance"
}

# Function to print summary
print_summary() {
    echo
    print_info "=== Verification Summary ==="
    echo "Total tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        print_success "✅ All tests passed!"
        if [ "$STRICT_MODE" = true ]; then
            exit 0
        fi
    else
        print_error "❌ $FAILED_TESTS test(s) failed"
        if [ "$STRICT_MODE" = true ]; then
            exit 1
        fi
    fi
    
    echo
    print_info "=== Cluster Status ==="
    
    # Display cluster info
    echo "Cluster URL: $(oc cluster-info | grep 'Kubernetes control plane' | awk '{print $NF}' || echo 'unknown')"
    
    # Display version info
    local version
    version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
    echo "OpenShift version: $version"
    
    # Display node info
    local node_count
    node_count=$(oc get nodes --no-headers | wc -l)
    echo "Node count: $node_count"
    
    # Display operator status
    local available_operators
    available_operators=$(oc get clusteroperators --no-headers | grep -c "True.*False.*False" || echo "0")
    echo "Available operators: $available_operators"
    
    echo
    print_info "=== Recommendations ==="
    
    if [ "$FAILED_TESTS" -gt 0 ]; then
        print_warning "Some tests failed. Consider:"
        echo "  - Checking cluster logs: oc logs -n openshift-apiserver"
        echo "  - Verifying operator status: oc get clusteroperators"
        echo "  - Checking node status: oc get nodes"
    else
        print_success "Cluster appears to be healthy and properly configured!"
    fi
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --strict)
                STRICT_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    parse_arguments "$@"
    
    print_info "Starting OpenShift cluster verification..."
    echo
    
    # Basic checks
    check_oc_command
    check_cluster_connection
    
    # Run all verification checks
    check_api_groups
    check_cluster_operators
    check_cluster_version
    check_olm_resources
    check_node_status
    check_auth_resources
    check_storage_networking
    check_console_resources
    check_project_resources
    check_image_registry
    check_monitoring_logging
    check_security_compliance
    
    # Print summary
    print_summary
}

# Run main function with all arguments
main "$@" 