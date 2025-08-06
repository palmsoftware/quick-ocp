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

# Install OLM (Operator Lifecycle Manager) for microshift compatibility
#
# This script installs OLM components to make microshift more compatible
# with OpenShift tooling and certsuite.
#
# Usage:
#   ./install-olm.sh [--force]
#
# Examples:
#   ./install-olm.sh                    # Install OLM if not present
#   ./install-olm.sh --force            # Force reinstall OLM

set -euo pipefail

# Default values
FORCE_INSTALL=false
OLM_VERSION="v0.32.0"
DEPLOYMENT_TIMEOUT="300s"

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
Install OLM (Operator Lifecycle Manager) for microshift compatibility

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --force     Force reinstall OLM even if already present
    --help      Show this help message

EXAMPLES:
    $0                    # Install OLM if not present
    $0 --force           # Force reinstall OLM

DESCRIPTION:
    This script installs OLM components to make microshift more compatible
    with OpenShift tooling and certsuite. It checks for existing OLM
    components and only installs what's missing unless --force is specified.
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
        print_info "Please ensure you're connected to your microshift cluster."
        exit 1
    fi
}

# Function to check if OLM is already installed
check_olm_installed() {
    if oc get namespace olm &> /dev/null; then
        print_info "OLM namespace exists"
        return 0
    else
        print_info "OLM namespace not found"
        return 1
    fi
}

# Function to check if operator-sdk is installed
check_operator_sdk() {
    if command -v operator-sdk &> /dev/null; then
        print_success "operator-sdk found in PATH"
        return 0
    else
        print_warning "operator-sdk not found in PATH"
        return 1
    fi
}

# Function to install operator-sdk (delegates to install script in this repo)
install_operator_sdk() {
    print_info "Installing operator-sdk using scripts/install-operator-sdk.sh"
    local script_dir script_path
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    script_path="${script_dir}/install-operator-sdk.sh"
    if [[ ! -x "${script_path}" ]]; then
        print_error "installer not found or not executable: ${script_path}"
        exit 1
    fi
    "${script_path}" || {
        print_error "operator-sdk installation failed"
        exit 1
    }
    print_success "operator-sdk installed"
}

# Function to install OLM
install_olm() {
    print_info "Installing OLM ${OLM_VERSION}..."
    
    # Download OLM install script
    local install_script="olm-install.sh"
    local download_url="https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${OLM_VERSION}/install.sh"
    
    print_info "Downloading OLM install script..."
    if curl -L -o "${install_script}" "${download_url}"; then
        chmod +x "${install_script}"
        
        # Run OLM installation
        print_info "Running OLM installation..."
        if ./"${install_script}" "${OLM_VERSION}"; then
            print_success "OLM installation completed"
        else
            print_error "OLM installation failed"
            rm -f "${install_script}"
            exit 1
        fi
        
        # Clean up install script
        rm -f "${install_script}"
    else
        print_error "Failed to download OLM install script"
        exit 1
    fi
}

# Function to wait for OLM pods to be ready
wait_for_olm_pods() {
    print_info "Waiting for OLM pods to be ready..."
    
    # Wait for olm namespace to exist
    local timeout=60
    local count=0
    while ! oc get namespace olm &> /dev/null && [ $count -lt $timeout ]; do
        sleep 2
        count=$((count + 2))
    done
    
    if ! oc get namespace olm &> /dev/null; then
        print_error "OLM namespace not created within timeout"
        exit 1
    fi
    
    # Wait for OLM pods to be ready
    if oc wait --for=condition=ready pod --all=true -n olm --timeout="${DEPLOYMENT_TIMEOUT}" 2>/dev/null; then
        print_success "All OLM pods are ready"
    else
        print_warning "Some OLM pods may not be ready, but continuing..."
    fi
    
    # Additional wait to ensure stability
    print_info "Waiting additional 5 seconds for OLM to stabilize..."
    sleep 5
}

# Function to verify OLM installation
verify_olm_installation() {
    print_info "Verifying OLM installation..."
    
    # Check for OLM namespaces
    local olm_namespaces=("olm" "operators")
    for ns in "${olm_namespaces[@]}"; do
        if oc get namespace "${ns}" &> /dev/null; then
            print_success "✅ Namespace ${ns} exists"
        else
            print_warning "⚠️  Namespace ${ns} not found"
        fi
    done
    
    # Check for OLM CRDs
    local olm_crds=(
        "catalogsources.operators.coreos.com"
        "clusterserviceversions.operators.coreos.com"
        "installplans.operators.coreos.com"
        "operatorgroups.operators.coreos.com"
        "subscriptions.operators.coreos.com"
    )
    
    for crd in "${olm_crds[@]}"; do
        if oc get crd "${crd}" &> /dev/null; then
            print_success "✅ CRD ${crd} exists"
        else
            print_warning "⚠️  CRD ${crd} not found"
        fi
    done
    
    # Check for OLM pods
    if oc get pods -n olm --no-headers 2>/dev/null | grep -q Running; then
        print_success "✅ OLM pods are running"
    else
        print_warning "⚠️  OLM pods may not be running"
    fi
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_INSTALL=true
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
    
    print_info "Starting OLM installation for microshift compatibility..."
    echo
    
    # Basic checks
    check_oc_command
    check_cluster_connection
    
    # Check if OLM is already installed
    if check_olm_installed; then
        if [ "$FORCE_INSTALL" = true ]; then
            print_warning "OLM appears to be already installed, but --force specified"
            print_info "Proceeding with installation..."
        else
            print_info "OLM appears to be already installed"
            print_info "Use --force to reinstall"
            verify_olm_installation
            exit 0
        fi
    fi
    
    # Check and install operator-sdk if needed (host-level)
    if ! check_operator_sdk; then
        install_operator_sdk
    fi
    
    # Install OLM
    install_olm
    
    # Wait for OLM pods
    wait_for_olm_pods
    
    # Verify installation
    verify_olm_installation
    
    print_success "OLM installation completed successfully!"
    echo
    print_info "You can now use OLM features:"
    echo "  oc get catalogsources -A"
    echo "  oc get subscriptions -A"
    echo "  oc get clusterserviceversions -A"
}

# Run main function with all arguments
main "$@"
