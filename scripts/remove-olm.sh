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
# GNU General Public License along with this program; if not, write to the
# Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# Uninstall OLM (Operator Lifecycle Manager)
#
# This script uninstalls OLM components following the official OLM documentation.
# It removes all OLM resources in the correct order to prevent dangling resources.
#
# Usage:
#   ./remove-olm.sh [--force] [--version VERSION]
#
# Examples:
#   ./remove-olm.sh                    # Uninstall OLM if present
#   ./remove-olm.sh --force            # Force uninstall OLM
#   ./remove-olm.sh --version v0.31.0  # Uninstall specific OLM version

set -euo pipefail

# Default values
FORCE_UNINSTALL=false
OLM_VERSION="v0.32.0"
OLM_NAMESPACE="olm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Function to show usage
show_usage() {
    cat << EOF
Uninstall OLM (Operator Lifecycle Manager)

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --force              Force uninstall OLM even if not detected
    --version VERSION    Specify OLM version to uninstall (default: v0.31.0)
    --help               Show this help message

EXAMPLES:
    $0                           # Uninstall OLM if present
    $0 --force                  # Force uninstall OLM
    $0 --version v0.30.0        # Uninstall specific OLM version

DESCRIPTION:
    This script uninstalls OLM components following the official OLM documentation.
    It removes all OLM resources in the correct order to prevent dangling resources.
    
    The uninstall process:
    1. Removes API services first to prevent dangling resources
    2. Deletes OLM CRDs
    3. Deletes OLM deployment resources
    4. Verifies complete removal

    Note: Uninstalling OLM does not clean up operators it maintained.
    Please clean up installed operator resources before uninstalling OLM.
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

# Function to check if OLM is installed
check_olm_installed() {
    if oc get namespace "${OLM_NAMESPACE}" &> /dev/null; then
        print_info "OLM namespace '${OLM_NAMESPACE}' found"
        return 0
    else
        print_info "OLM namespace '${OLM_NAMESPACE}' not found"
        return 1
    fi
}

# Function to detect OLM version from packageserver CSV
detect_olm_version() {
    print_info "Detecting OLM version from packageserver CSV..."
    
    if oc get csv -n "${OLM_NAMESPACE}" packageserver &> /dev/null; then
        local detected_version
        detected_version=$(oc get csv -n "${OLM_NAMESPACE}" packageserver -o jsonpath='{.spec.version}' 2>/dev/null || echo "")
        
        if [ -n "${detected_version}" ]; then
            # Extract major.minor version from full version
            local major_minor_version
            major_minor_version=$(echo "${detected_version}" | cut -d. -f1-2)
            OLM_VERSION="v${major_minor_version}"
            print_info "Detected OLM version: ${OLM_VERSION}"
        else
            print_warning "Could not detect OLM version, using default: ${OLM_VERSION}"
        fi
    else
        print_warning "Could not find packageserver CSV, using default version: ${OLM_VERSION}"
    fi
}

# Function to remove API services first
remove_api_services() {
    print_info "Removing OLM API services..."
    
    # Remove the packages API service first to prevent dangling resources
    if oc delete apiservices.apiregistration.k8s.io v1.packages.operators.coreos.com &> /dev/null; then
        print_success "Removed API service: v1.packages.operators.coreos.com"
    else
        print_warning "API service v1.packages.operators.coreos.com not found or already removed"
    fi
}

# Function to remove OLM CRDs
remove_olm_crds() {
    print_info "Removing OLM CRDs..."
    
    local crds_url="https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/crds.yaml"
    
    print_info "Downloading OLM CRDs from: ${crds_url}"
    
    # Download CRDs file
    local crds_file="olm-crds.yaml"
    if curl -L -o "${crds_file}" "${crds_url}" 2>/dev/null; then
        print_info "Deleting OLM CRDs..."
        if oc delete -f "${crds_file}" &> /dev/null; then
            print_success "OLM CRDs removed successfully"
        else
            print_warning "Some OLM CRDs may not have been removed (possibly already deleted)"
        fi
        rm -f "${crds_file}"
    else
        print_error "Failed to download OLM CRDs from ${crds_url}"
        print_info "Trying alternative method..."
        
        # Try alternative URL for master branch
        local alt_crds_url="https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/crds.yaml"
        print_info "Trying alternative URL: ${alt_crds_url}"
        
        if curl -L -o "${crds_file}" "${alt_crds_url}" 2>/dev/null; then
            print_info "Deleting OLM CRDs from alternative source..."
            if oc delete -f "${crds_file}" &> /dev/null; then
                print_success "OLM CRDs removed successfully"
            else
                print_warning "Some OLM CRDs may not have been removed (possibly already deleted)"
            fi
            rm -f "${crds_file}"
        else
            print_error "Failed to download OLM CRDs from both sources"
            print_info "Continuing with manual CRD removal..."
            remove_olm_crds_manually
        fi
    fi
}

# Function to manually remove OLM CRDs
remove_olm_crds_manually() {
    print_info "Manually removing OLM CRDs..."
    
    local olm_crds=(
        "catalogsources.operators.coreos.com"
        "clusterserviceversions.operators.coreos.com"
        "installplans.operators.coreos.com"
        "operatorgroups.operators.coreos.com"
        "subscriptions.operators.coreos.com"
        "packages.operators.coreos.com"
    )
    
    for crd in "${olm_crds[@]}"; do
        if oc delete crd "${crd}" &> /dev/null; then
            print_success "Removed CRD: ${crd}"
        else
            print_warning "CRD ${crd} not found or already removed"
        fi
    done
}

# Function to remove OLM deployment resources
remove_olm_deployment() {
    print_info "Removing OLM deployment resources..."
    
    local olm_url="https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/olm.yaml"
    
    print_info "Downloading OLM deployment from: ${olm_url}"
    
    # Download OLM deployment file
    local olm_file="olm-deployment.yaml"
    if curl -L -o "${olm_file}" "${olm_url}" 2>/dev/null; then
        print_info "Deleting OLM deployment resources..."
        if oc delete -f "${olm_file}" &> /dev/null; then
            print_success "OLM deployment resources removed successfully"
        else
            print_warning "Some OLM deployment resources may not have been removed (possibly already deleted)"
        fi
        rm -f "${olm_file}"
    else
        print_error "Failed to download OLM deployment from ${olm_url}"
        print_info "Trying alternative method..."
        
        # Try alternative URL for master branch
        local alt_olm_url="https://raw.githubusercontent.com/operator-framework/operator-lifecycle-manager/master/deploy/upstream/quickstart/olm.yaml"
        print_info "Trying alternative URL: ${alt_olm_url}"
        
        if curl -L -o "${olm_file}" "${alt_olm_url}" 2>/dev/null; then
            print_info "Deleting OLM deployment resources from alternative source..."
            if oc delete -f "${olm_file}" &> /dev/null; then
                print_success "OLM deployment resources removed successfully"
            else
                print_warning "Some OLM deployment resources may not have been removed (possibly already deleted)"
            fi
            rm -f "${olm_file}"
        else
            print_error "Failed to download OLM deployment from both sources"
            print_info "Continuing with manual resource removal..."
            remove_olm_resources_manually
        fi
    fi
}

# Function to manually remove OLM resources
remove_olm_resources_manually() {
    print_info "Manually removing OLM resources..."
    
    # Remove OLM namespace and all its resources
    if oc delete namespace "${OLM_NAMESPACE}" &> /dev/null; then
        print_success "Removed OLM namespace: ${OLM_NAMESPACE}"
    else
        print_warning "OLM namespace ${OLM_NAMESPACE} not found or already removed"
    fi
    
    # Remove operators namespace if it exists
    if oc delete namespace operators &> /dev/null; then
        print_success "Removed operators namespace"
    else
        print_warning "Operators namespace not found or already removed"
    fi
    
    # Remove any remaining OLM-related resources
    local olm_resources=(
        "deployment/olm-operator"
        "deployment/catalog-operator"
        "deployment/packageserver"
        "service/olm-operator"
        "service/catalog-operator"
        "service/packageserver"
        "serviceaccount/olm-operator"
        "serviceaccount/catalog-operator"
        "serviceaccount/packageserver"
    )
    
    for resource in "${olm_resources[@]}"; do
        if oc delete "${resource}" -n "${OLM_NAMESPACE}" &> /dev/null; then
            print_success "Removed resource: ${resource}"
        fi
    done
}

# Function to verify OLM uninstall
verify_olm_uninstall() {
    print_info "Verifying OLM uninstall..."
    
    # Check if OLM namespace is removed
    if ! oc get namespace "${OLM_NAMESPACE}" &> /dev/null; then
        print_success "✅ OLM namespace '${OLM_NAMESPACE}' has been removed"
    else
        print_warning "⚠️  OLM namespace '${OLM_NAMESPACE}' still exists"
    fi
    
    # Check if operators namespace is removed
    if ! oc get namespace operators &> /dev/null; then
        print_success "✅ Operators namespace has been removed"
    else
        print_warning "⚠️  Operators namespace still exists"
    fi
    
    # Check if OLM CRDs are removed
    local olm_crds=(
        "catalogsources.operators.coreos.com"
        "clusterserviceversions.operators.coreos.com"
        "installplans.operators.coreos.com"
        "operatorgroups.operators.coreos.com"
        "subscriptions.operators.coreos.com"
        "packages.operators.coreos.com"
    )
    
    local crds_removed=true
    for crd in "${olm_crds[@]}"; do
        if oc get crd "${crd}" &> /dev/null; then
            print_warning "⚠️  CRD ${crd} still exists"
            crds_removed=false
        else
            print_success "✅ CRD ${crd} has been removed"
        fi
    done
    
    # Check if OLM deployments are removed
    if oc get deploy -n "${OLM_NAMESPACE}" &> /dev/null 2>&1; then
        print_warning "⚠️  Some OLM deployments still exist in ${OLM_NAMESPACE} namespace"
    else
        print_success "✅ OLM deployments have been removed"
    fi
    
    # Check if OLM roles and rolebindings are removed
    if oc get role -n "${OLM_NAMESPACE}" &> /dev/null 2>&1; then
        print_warning "⚠️  Some OLM roles still exist in ${OLM_NAMESPACE} namespace"
    else
        print_success "✅ OLM roles have been removed"
    fi
    
    if oc get rolebinding -n "${OLM_NAMESPACE}" &> /dev/null 2>&1; then
        print_warning "⚠️  Some OLM rolebindings still exist in ${OLM_NAMESPACE} namespace"
    else
        print_success "✅ OLM rolebindings have been removed"
    fi
    
    if [ "$crds_removed" = true ]; then
        print_success "OLM uninstall verification completed successfully!"
    else
        print_warning "OLM uninstall completed with some resources still present"
    fi
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_UNINSTALL=true
                shift
                ;;
            --version)
                if [[ $# -lt 2 ]]; then
                    print_error "Missing version value for --version option"
                    show_usage
                    exit 1
                fi
                OLM_VERSION="$2"
                shift 2
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
    
    print_info "Starting OLM uninstall process..."
    echo
    
    # Basic checks
    check_oc_command
    check_cluster_connection
    
    # Check if OLM is installed
    if check_olm_installed; then
        print_info "OLM is installed, proceeding with uninstall..."
    else
        if [ "$FORCE_UNINSTALL" = true ]; then
            print_warning "OLM does not appear to be installed, but --force specified"
            print_info "Proceeding with uninstall process..."
        else
            print_info "OLM does not appear to be installed"
            print_info "Use --force to attempt uninstall anyway"
            exit 0
        fi
    fi
    
    # Detect OLM version if OLM is installed
    if check_olm_installed; then
        detect_olm_version
    fi
    
    print_info "Uninstalling OLM version: ${OLM_VERSION}"
    echo
    
    # Remove API services first (prevents dangling resources)
    remove_api_services
    
    # Remove OLM CRDs
    remove_olm_crds
    
    # Remove OLM deployment resources
    remove_olm_deployment
    
    # Wait a moment for resources to be cleaned up
    print_info "Waiting for resources to be cleaned up..."
    sleep 5
    
    # Verify uninstall
    verify_olm_uninstall
    
    print_success "OLM uninstall completed!"
    echo
    print_info "Note: This script only removes OLM itself."
    print_info "Any operators installed by OLM may still need to be cleaned up manually."
}

# Run main function with all arguments
main "$@" 