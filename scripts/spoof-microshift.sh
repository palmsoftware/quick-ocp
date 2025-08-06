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

# Setup fake OpenShift ClusterOperator for certsuite compatibility on microshift
#
# This script creates the necessary OpenShift config.openshift.io API resources
# to make certsuite think it's running on a proper OpenShift cluster.
#
# Usage:
#   ./setup-microshift-clusteroperator.sh [install|remove] [version]
#
# Examples:
#   ./setup-microshift-clusteroperator.sh install 4.14.0
#   ./setup-microshift-clusteroperator.sh remove
#   ./setup-microshift-clusteroperator.sh install  # uses default version 4.14.0

set -euo pipefail

# Default values
DEFAULT_OPENSHIFT_VERSION="4.14.0"
CLUSTER_OPERATOR_NAME="openshift-apiserver"
CLUSTER_VERSION_NAME="version"
CLUSTEROPERATOR_CRD_NAME="clusteroperators.config.openshift.io"
CLUSTERVERSION_CRD_NAME="clusterversions.config.openshift.io"
REMOVE_OLM=false

# OLM CRD names
CATALOGSOURCE_CRD_NAME="catalogsources.operators.coreos.com"
CSV_CRD_NAME="clusterserviceversions.operators.coreos.com"
SUBSCRIPTION_CRD_NAME="subscriptions.operators.coreos.com"
INSTALLPLAN_CRD_NAME="installplans.operators.coreos.com"

# Additional OpenShift CRD names
OAUTH_CRD_NAME="oauths.config.openshift.io"
PROJECT_CRD_NAME="projects.project.openshift.io"
OPERATORHUB_CRD_NAME="operatorhubs.config.openshift.io"

# MCO CRD names for platform alteration compatibility
MACHINECONFIG_CRD_NAME="machineconfigs.machineconfiguration.openshift.io"
MACHINECONFIGPOOL_CRD_NAME="machineconfigpools.machineconfiguration.openshift.io"

# Multus CNI CRD names for networking compatibility
NETWORKATTACHMENTDEFINITION_CRD_NAME="network-attachment-definitions.k8s.cni.cncf.io"

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
Setup fake OpenShift ClusterOperator for certsuite compatibility on microshift

USAGE:
    $0 [COMMAND] [VERSION] [OPTIONS]

COMMANDS:
    install     Install fake ClusterOperator (default)
    remove      Remove fake ClusterOperator and CRD
    check       Check current status
    help        Show this help message

ARGUMENTS:
    VERSION     OpenShift version to simulate (default: ${DEFAULT_OPENSHIFT_VERSION})

OPTIONS:
    --remove-olm    Also remove OLM installation when removing fake resources
    --help          Show this help message

EXAMPLES:
    $0 install 4.14.0              Install with OpenShift 4.14.0
    $0 install                     Install with default version (${DEFAULT_OPENSHIFT_VERSION})
    $0 remove                      Remove all fake resources
    $0 remove --remove-olm         Remove fake resources and OLM installation
    $0 check                       Check if fake resources exist

DESCRIPTION:
    This script helps certsuite work with microshift by creating fake OpenShift
    config.openshift.io API resources. Certsuite checks for a ClusterOperator
    named 'openshift-apiserver' to determine if it's running on OpenShift.

    Without this, certsuite detects microshift as a non-OpenShift cluster and
    may skip certain tests or behave differently.

WARNING:
    This creates fake OpenShift resources that may cause some OpenShift-specific
    tests to run and potentially fail if microshift doesn't support those features.
    
    Using --remove-olm will completely remove OLM installation using the official
    OLM uninstall process, which may break any operators that were installed via OLM.
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

# Function to check if ClusterOperator CRD exists
clusteroperator_crd_exists() {
    oc get crd "$CLUSTEROPERATOR_CRD_NAME" &> /dev/null
}

# Function to check if ClusterVersion CRD exists
clusterversion_crd_exists() {
    oc get crd "$CLUSTERVERSION_CRD_NAME" &> /dev/null
}

# Function to check if ClusterOperator exists
clusteroperator_exists() {
    oc get clusteroperator "$CLUSTER_OPERATOR_NAME" &> /dev/null
}

# Function to check if ClusterVersion exists
clusterversion_exists() {
    oc get clusterversion "$CLUSTER_VERSION_NAME" &> /dev/null
}

# Function to check if OLM CRDs exist
catalogsource_crd_exists() {
    oc get crd "$CATALOGSOURCE_CRD_NAME" &> /dev/null
}

csv_crd_exists() {
    oc get crd "$CSV_CRD_NAME" &> /dev/null
}

subscription_crd_exists() {
    oc get crd "$SUBSCRIPTION_CRD_NAME" &> /dev/null
}

installplan_crd_exists() {
    oc get crd "$INSTALLPLAN_CRD_NAME" &> /dev/null
}

# Function to check if additional OpenShift CRDs exist
oauth_crd_exists() {
    oc get crd "$OAUTH_CRD_NAME" &> /dev/null
}

project_crd_exists() {
    oc get crd "$PROJECT_CRD_NAME" &> /dev/null
}

# Function to check if OperatorHub CRD exists
operatorhub_crd_exists() {
    oc get crd "$OPERATORHUB_CRD_NAME" &> /dev/null
}

# Function to check if OperatorHub instance exists
operatorhub_exists() {
    oc get operatorhub cluster &> /dev/null || oc get operatorhubs cluster &> /dev/null
}

# Function to check if MCO CRDs exist
machineconfig_crd_exists() {
    oc get crd "$MACHINECONFIG_CRD_NAME" &> /dev/null
}

machineconfigpool_crd_exists() {
    oc get crd "$MACHINECONFIGPOOL_CRD_NAME" &> /dev/null
}

 

# Function to create ClusterOperator CRD
create_clusteroperator_crd() {
    print_info "Creating ClusterOperator CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${CLUSTEROPERATOR_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: config.openshift.io
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: VERSION
      type: string
      description: The version of the operator
      jsonPath: .status.versions[?(@.name=="operator")].version
    - name: AVAILABLE
      type: string
      description: Whether the operator is available
      jsonPath: .status.conditions[?(@.type=="Available")].status
    - name: PROGRESSING
      type: string
      description: Whether the operator is progressing
      jsonPath: .status.conditions[?(@.type=="Progressing")].status
    - name: DEGRADED
      type: string
      description: Whether the operator is degraded
      jsonPath: .status.conditions[?(@.type=="Degraded")].status
    - name: SINCE
      type: date
      description: The time the current status was reached
      jsonPath: .status.conditions[?(@.type=="Available")].lastTransitionTime
    - name: MESSAGE
      type: string
      description: A human readable message about the current status
      jsonPath: .status.conditions[?(@.type=="Available")].message
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            properties:
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    lastTransitionTime:
                      type: string
                      format: date-time
                    reason:
                      type: string
                    message:
                      type: string
                  required:
                  - type
                  - status
              versions:
                type: array
                items:
                  type: object
                  properties:
                    name:
                      type: string
                    version:
                      type: string
                  required:
                  - name
                  - version
            x-kubernetes-preserve-unknown-fields: true
  scope: Cluster
  names:
    plural: clusteroperators
    singular: clusteroperator
    kind: ClusterOperator
    shortNames:
    - co
EOF

    # Wait for CRD to be established
    print_info "Waiting for CRD to be established..."
    local timeout=30
    local count=0
    while ! oc get crd "$CLUSTEROPERATOR_CRD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null | grep -q "True"; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            print_error "Timeout waiting for CRD to be established"
            exit 1
        fi
    done
    
    print_success "ClusterOperator CRD created successfully"
}

# Function to create ClusterVersion CRD
create_clusterversion_crd() {
    print_info "Creating ClusterVersion CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${CLUSTERVERSION_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: config.openshift.io
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: VERSION
      type: string
      description: The desired release version of the cluster
      jsonPath: .status.desired.version
    - name: AVAILABLE
      type: string  
      description: Whether the cluster version is available
      jsonPath: .status.conditions[?(@.type=="Available")].status
    - name: PROGRESSING
      type: string
      description: Whether the cluster is progressing towards the desired version
      jsonPath: .status.conditions[?(@.type=="Progressing")].status
    - name: SINCE
      type: date
      description: The time the current status was reached
      jsonPath: .status.conditions[?(@.type=="Available")].lastTransitionTime
    - name: STATUS
      type: string
      description: Message describing the current status
      jsonPath: .status.conditions[?(@.type=="Available")].message
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              clusterID:
                type: string
              channel:
                type: string
              desiredUpdate:
                type: object
                properties:
                  version:
                    type: string
                  image:
                    type: string
              upstream:
                type: string
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            properties:
              desired:
                type: object
                properties:
                  version:
                    type: string
                  image:
                    type: string
              history:
                type: array
                items:
                  type: object
                  properties:
                    state:
                      type: string
                    startedTime:
                      type: string
                      format: date-time
                    completionTime:
                      type: string
                      format: date-time
                    version:
                      type: string
                    image:
                      type: string
              observedGeneration:
                type: integer
                format: int64
              versionHash:
                type: string
              availableUpdates:
                type: array
                items:
                  type: object
                  properties:
                    version:
                      type: string
                    image:
                      type: string
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    lastTransitionTime:
                      type: string
                      format: date-time
                    reason:
                      type: string
                    message:
                      type: string
            x-kubernetes-preserve-unknown-fields: true
  scope: Cluster
  names:
    plural: clusterversions
    singular: clusterversion
    kind: ClusterVersion
    shortNames:
    - cv
EOF

    # Wait for CRD to be established
    print_info "Waiting for ClusterVersion CRD to be established..."
    local timeout=30
    local count=0
    while ! oc get crd "$CLUSTERVERSION_CRD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}' 2>/dev/null | grep -q "True"; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $timeout ]; then
            print_error "Timeout waiting for ClusterVersion CRD to be established"
            exit 1
        fi
    done
    
    print_success "ClusterVersion CRD created successfully"
}

# Function to create fake ClusterOperator
create_clusteroperator() {
    local version=$1
    print_info "Creating fake openshift-apiserver ClusterOperator with version ${version}..."
    
    cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: ClusterOperator
metadata:
  name: ${CLUSTER_OPERATOR_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec: {}
status:
  conditions:
  - type: Available
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "Fake ClusterOperator for certsuite compatibility on microshift"
  - type: Progressing
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "No updates in progress"
  - type: Degraded
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "All is well"
  - type: Upgradeable
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "Fake ClusterOperator for certsuite compatibility on microshift"
  versions:
  - name: operator
    version: "${version}"
  - name: openshift-apiserver
    version: "${version}"
  - name: raw-internal
    version: "${version}"
EOF

    print_success "ClusterOperator '${CLUSTER_OPERATOR_NAME}' created successfully"
}

# Function to create additional fake ClusterOperators
create_additional_clusteroperators() {
    local version=$1
    print_info "Creating additional fake ClusterOperators for microshift compatibility..."
    
    local additional_operators=(
        "openshift-controller-manager"
        "openshift-etcd"
        "openshift-kube-apiserver"
        "openshift-kube-controller-manager"
        "openshift-kube-scheduler"
        "authentication"
        "console"
        "image-registry"
        "ingress"
        "monitoring"
        "logging"
        "security"
        "compliance"
    )
    
    for operator in "${additional_operators[@]}"; do
        print_info "Creating ClusterOperator: $operator"
        cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: ClusterOperator
metadata:
  name: ${operator}
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec: {}
status:
  conditions:
  - type: Available
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "Fake ClusterOperator for microshift compatibility"
  - type: Progressing
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "No updates in progress"
  - type: Degraded
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "All is well"
  - type: Upgradeable
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "Fake ClusterOperator for microshift compatibility"
  versions:
  - name: operator
    version: "${version}"
  - name: ${operator}
    version: "${version}"
  - name: raw-internal
    version: "${version}"
EOF
        print_success "ClusterOperator '$operator' created successfully"
    done
}

# Function to create fake ClusterVersion
create_clusterversion() {
    local version=$1
    print_info "Creating fake ClusterVersion resource with version ${version}..."
    
    cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: ClusterVersion
metadata:
  name: ${CLUSTER_VERSION_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec:
  clusterID: "$(uuidgen)"
  channel: "stable-${version%.*}"
  desiredUpdate:
    version: "${version}"
    image: "quay.io/openshift-release-dev/ocp-release@sha256:fake-${version}"
status:
  desired:
    version: "${version}"
    image: "quay.io/openshift-release-dev/ocp-release@sha256:fake-${version}"
  history:
  - state: "Completed"
    startedTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    completionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    version: "${version}"
    image: "quay.io/openshift-release-dev/ocp-release@sha256:fake-${version}"
  observedGeneration: 1
  versionHash: "fake-hash-${version}"
  availableUpdates: []
  conditions:
  - type: Available
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "Done"
    message: "Done applying ${version}"
  - type: Progressing
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "Done"
    message: "Cluster version is ${version}"
  - type: Degraded
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "Cluster version is ${version}"
EOF

    print_success "ClusterVersion '${CLUSTER_VERSION_NAME}' created successfully"
}

# Function to create CatalogSource CRD
create_catalogsource_crd() {
    print_info "Creating CatalogSource CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${CATALOGSOURCE_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: operators.coreos.com
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              sourceType:
                type: string
              image:
                type: string
              displayName:
                type: string
              description:
                type: string
          status:
            type: object
  scope: Namespaced
  names:
    plural: catalogsources
    singular: catalogsource
    kind: CatalogSource
    shortNames:
    - catsrc
EOF

    print_success "CatalogSource CRD created successfully"
}

# Function to create ClusterServiceVersion CRD
create_csv_crd() {
    print_info "Creating ClusterServiceVersion CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${CSV_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: operators.coreos.com
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              displayName:
                type: string
              description:
                type: string
              version:
                type: string
              installModes:
                type: array
                items:
                  type: object
          status:
            type: object
            properties:
              phase:
                type: string
  scope: Namespaced
  names:
    plural: clusterserviceversions
    singular: clusterserviceversion
    kind: ClusterServiceVersion
    shortNames:
    - csv
EOF

    print_success "ClusterServiceVersion CRD created successfully"
}

# Function to create Subscription CRD
create_subscription_crd() {
    print_info "Creating Subscription CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${SUBSCRIPTION_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: operators.coreos.com
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              channel:
                type: string
              name:
                type: string
              source:
                type: string
              sourceNamespace:
                type: string
          status:
            type: object
            properties:
              installedCSV:
                type: string
  scope: Namespaced
  names:
    plural: subscriptions
    singular: subscription
    kind: Subscription
    shortNames:
    - sub
EOF

    print_success "Subscription CRD created successfully"
}

# Function to create InstallPlan CRD
create_installplan_crd() {
    print_info "Creating InstallPlan CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${INSTALLPLAN_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: operators.coreos.com
  versions:
  - name: v1alpha1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              clusterServiceVersionNames:
                type: array
                items:
                  type: string
              approval:
                type: string
          status:
            type: object
            properties:
              phase:
                type: string
              bundleLookups:
                type: array
                items:
                  type: object
  scope: Namespaced
  names:
    plural: installplans
    singular: installplan
    kind: InstallPlan
    shortNames:
    - ip
EOF

    print_success "InstallPlan CRD created successfully"
}

# Function to create OAuth CRD
create_oauth_crd() {
    print_info "Creating OAuth CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${OAUTH_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: config.openshift.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              identityProviders:
                type: array
                items:
                  type: object
          status:
            type: object
  scope: Cluster
  names:
    plural: oauths
    singular: oauth
    kind: OAuth
EOF

    print_success "OAuth CRD created successfully"
}

# Function to create Project CRD
create_project_crd() {
    print_info "Creating Project CRD..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${PROJECT_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: project.openshift.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              finalizers:
                type: array
                items:
                  type: string
          status:
            type: object
  scope: Cluster
  names:
    plural: projects
    singular: project
    kind: Project
    shortNames:
    - proj
EOF

    print_success "Project CRD created successfully"
}

# Function to create OperatorHub CRD
create_operatorhub_crd() {
    print_info "Creating OperatorHub CRD..."
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${OPERATORHUB_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: config.openshift.io
  names:
    kind: OperatorHub
    listKind: OperatorHubList
    plural: operatorhubs
    singular: operatorhub
  scope: Cluster
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            x-kubernetes-preserve-unknown-fields: true
EOF
    print_success "OperatorHub CRD created successfully"
}

# Function to create default OperatorHub instance
create_operatorhub_resource() {
    print_info "Creating OperatorHub instance 'cluster'..."
    cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OperatorHub
metadata:
  name: cluster
spec:
  disableAllDefaultSources: false
  sources: []
EOF
    print_success "OperatorHub instance 'cluster' created/updated successfully"
}

# Function to create MachineConfig CRD
create_machineconfig_crd() {
    print_info "Creating MachineConfig CRD for platform alteration compatibility..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${MACHINECONFIG_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: machineconfiguration.openshift.io
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: GENERATEDBYCONTROLLER
      type: string
      description: Generated by controller
      jsonPath: .metadata.labels.machineconfiguration\.openshift\.io/generated-by-controller
    - name: IGNITIONVERSION
      type: string
      description: Ignition version
      jsonPath: .spec.config.ignition.version
    - name: AGE
      type: date
      description: Creation time
      jsonPath: .metadata.creationTimestamp
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              config:
                type: object
                properties:
                  ignition:
                    type: object
                    properties:
                      version:
                        type: string
                  storage:
                    type: object
                    properties:
                      files:
                        type: array
                        items:
                          type: object
                  systemd:
                    type: object
                    properties:
                      units:
                        type: array
                        items:
                          type: object
              kernelArguments:
                type: array
                items:
                  type: string
              kernelType:
                type: string
              fips:
                type: boolean
              osImageURL:
                type: string
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            x-kubernetes-preserve-unknown-fields: true
  scope: Cluster
  names:
    plural: machineconfigs
    singular: machineconfig
    kind: MachineConfig
    shortNames:
    - mc
EOF

    print_success "MachineConfig CRD created successfully"
}

# Function to create MachineConfigPool CRD
create_machineconfigpool_crd() {
    print_info "Creating MachineConfigPool CRD for platform alteration compatibility..."
    
    cat <<EOF | oc apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${MACHINECONFIGPOOL_CRD_NAME}
  annotations:
    created-by: certsuite-microshift-setup-script
spec:
  group: machineconfiguration.openshift.io
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - name: CONFIG
      type: string
      description: Current configuration
      jsonPath: .status.configuration.name
    - name: UPDATED
      type: integer
      description: Updated machines
      jsonPath: .status.updatedMachineCount
    - name: UPDATING
      type: integer
      description: Updating machines
      jsonPath: .status.machineCount
    - name: DEGRADED
      type: integer
      description: Degraded machines
      jsonPath: .status.degradedMachineCount
    - name: MACHINECOUNT
      type: integer
      description: Total machines
      jsonPath: .status.machineCount
    - name: READYMACHINECOUNT
      type: integer
      description: Ready machines
      jsonPath: .status.readyMachineCount
    - name: AGE
      type: date
      description: Creation time
      jsonPath: .metadata.creationTimestamp
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              machineConfigSelector:
                type: object
                properties:
                  matchLabels:
                    type: object
                    additionalProperties:
                      type: string
                  matchExpressions:
                    type: array
                    items:
                      type: object
              nodeSelector:
                type: object
                properties:
                  matchLabels:
                    type: object
                    additionalProperties:
                      type: string
                  matchExpressions:
                    type: array
                    items:
                      type: object
              configuration:
                type: object
                properties:
                  name:
                    type: string
                  source:
                    type: array
                    items:
                      type: object
              paused:
                type: boolean
              maxUnavailable:
                type: string
            x-kubernetes-preserve-unknown-fields: true
          status:
            type: object
            properties:
              observedGeneration:
                type: integer
                format: int64
              configuration:
                type: object
                properties:
                  name:
                    type: string
                  source:
                    type: array
                    items:
                      type: object
              machineCount:
                type: integer
                format: int32
              updatedMachineCount:
                type: integer
                format: int32
              readyMachineCount:
                type: integer
                format: int32
              unavailableMachineCount:
                type: integer
                format: int32
              degradedMachineCount:
                type: integer
                format: int32
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    lastTransitionTime:
                      type: string
                      format: date-time
                    reason:
                      type: string
                    message:
                      type: string
            x-kubernetes-preserve-unknown-fields: true
  scope: Cluster
  names:
    plural: machineconfigpools
    singular: machineconfigpool
    kind: MachineConfigPool
    shortNames:
    - mcp
EOF

    print_success "MachineConfigPool CRD created successfully"
}

 

# Function to create fake OAuth resource
create_oauth_resource() {
    local version=$1
    print_info "Creating fake OAuth resource..."
    
    cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec:
  identityProviders: []
status: {}
EOF

    print_success "OAuth resource created successfully"
}

# Function to create fake MachineConfigs
create_fake_machineconfigs() {
    local version=$1
    print_info "Creating fake MachineConfig resources for platform alteration compatibility..."
    
    # Create master MachineConfig
    cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 00-master
  labels:
    machineconfiguration.openshift.io/role: master
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec:
  config:
    ignition:
      version: 3.2.0
  kernelArguments: []
  fips: false
EOF

    # Create worker MachineConfig
    cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 00-worker
  labels:
    machineconfiguration.openshift.io/role: worker
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec:
  config:
    ignition:
      version: 3.2.0
  kernelArguments: []
  fips: false
EOF

    print_success "Fake MachineConfig resources created successfully"
}

# Function to create fake MachineConfigPools
create_fake_machineconfigpools() {
    local version=$1
    print_info "Creating fake MachineConfigPool resources for platform alteration compatibility..."
    
    # Create master MachineConfigPool
    cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: master
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec:
  machineConfigSelector:
    matchLabels:
      machineconfiguration.openshift.io/role: master
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/master: ""
  configuration:
    name: rendered-master-fake
    source:
    - name: 00-master
status:
  observedGeneration: 1
  configuration:
    name: rendered-master-fake
    source:
    - name: 00-master
  machineCount: 1
  updatedMachineCount: 1
  readyMachineCount: 1
  unavailableMachineCount: 0
  degradedMachineCount: 0
  conditions:
  - type: Updated
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AllNodesUpdated"
    message: "All nodes are updated with rendered-master-fake"
  - type: Updating
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AllNodesUpdated"
    message: "All nodes are updated with rendered-master-fake"
  - type: Degraded
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "All nodes are reporting Degraded=False"
EOF

    # Create worker MachineConfigPool
    cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: worker
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "${version}"
spec:
  machineConfigSelector:
    matchLabels:
      machineconfiguration.openshift.io/role: worker
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/worker: ""
  configuration:
    name: rendered-worker-fake
    source:
    - name: 00-worker
status:
  observedGeneration: 1
  configuration:
    name: rendered-worker-fake
    source:
    - name: 00-worker
  machineCount: 1
  updatedMachineCount: 1
  readyMachineCount: 1
  unavailableMachineCount: 0
  degradedMachineCount: 0
  conditions:
  - type: Updated
    status: "True"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AllNodesUpdated"
    message: "All nodes are updated with rendered-worker-fake"
  - type: Updating
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AllNodesUpdated"
    message: "All nodes are updated with rendered-worker-fake"
  - type: Degraded
    status: "False"
    lastTransitionTime: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    reason: "AsExpected"
    message: "All nodes are reporting Degraded=False"
EOF

    print_success "Fake MachineConfigPool resources created successfully"
}

 

# Function to install OLM
install_olm() {
    print_info "Installing OLM for microshift compatibility..."
    
    # Check if install-olm.sh script exists
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local install_olm_script="${script_dir}/install-olm.sh"
    
    if [[ -f "${install_olm_script}" ]]; then
        print_info "Using dedicated OLM install script: ${install_olm_script}"
        
        # Run the install-olm.sh script
        if "${install_olm_script}"; then
            print_success "OLM installation completed using dedicated script!"
        else
            print_warning "OLM installation script encountered some issues, but continuing with spoofing..."
        fi
    else
        print_warning "install-olm.sh script not found at ${install_olm_script}"
        print_info "Falling back to basic OLM installation..."
        
        # Fallback to basic installation (keeping minimal logic as backup)
        if oc get namespace olm &> /dev/null; then
            print_info "OLM namespace already exists, skipping installation"
            return 0
        fi
        
        # Check if operator-sdk is available
        if ! command -v operator-sdk &> /dev/null; then
            print_warning "operator-sdk not found, OLM installation may fail"
            print_info "Consider installing operator-sdk manually if needed"
        fi
        
        # Download and run OLM installation
        local install_script="olm-install.sh"
        local olm_version="v0.31.0"
        local download_url="https://github.com/operator-framework/operator-lifecycle-manager/releases/download/${olm_version}/install.sh"
        
        print_info "Downloading OLM install script..."
        if curl -L -o "${install_script}" "${download_url}"; then
            chmod +x "${install_script}"
            
            print_info "Running OLM installation..."
            # Run OLM installation but don't fail if it doesn't complete perfectly
            if ./"${install_script}" "${olm_version}"; then
                print_success "OLM installation completed"
            else
                print_warning "OLM installation had issues, but continuing with spoofing..."
            fi
            
            # Wait for OLM namespace to exist
            print_info "Waiting for OLM namespace to be created..."
            local timeout=120
            local count=0
            while ! oc get namespace olm &> /dev/null && [ $count -lt $timeout ]; do
                sleep 2
                count=$((count + 2))
            done
            
            if oc get namespace olm &> /dev/null; then
                print_success "OLM namespace created"
                
                # Wait for OLM pods to be ready (but don't fail if they're not)
                print_info "Waiting for OLM pods to be ready..."
                if oc wait --for=condition=ready pod --all=true -n olm --timeout="300s" 2>/dev/null; then
                    print_success "All OLM pods are ready"
                else
                    print_warning "Some OLM pods may not be ready, but continuing with spoofing..."
                fi
            else
                print_warning "OLM namespace not created, but continuing with spoofing..."
            fi
            
            # Additional wait for stability
            sleep 5
            
            # Clean up install script
            rm -f "${install_script}"
        else
            print_error "Failed to download OLM install script"
            print_warning "Continuing with spoofing without OLM..."
            return 0  # Don't fail the entire process
        fi
    fi
}

# Function to create openshift-marketplace namespace
create_openshift_marketplace_namespace() {
    print_info "Creating openshift-marketplace namespace..."
    
    cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-marketplace
  annotations:
    created-by: certsuite-microshift-setup-script
    simulated-version: "microshift-compatibility"
EOF

    print_success "openshift-marketplace namespace created successfully"
}

# Function to remove OLM installation
remove_olm() {
    print_info "Removing OLM installation using official uninstall process..."
    
    # Check if remove-olm.sh script exists
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local remove_olm_script="${script_dir}/remove-olm.sh"
    
    if [[ -f "${remove_olm_script}" ]]; then
        print_info "Using official OLM uninstall script: ${remove_olm_script}"
        
        # Run the remove-olm.sh script with force flag to ensure complete removal
        if "${remove_olm_script}" --force; then
            print_success "OLM removal completed using official uninstall process!"
        else
            print_warning "OLM removal script encountered some issues, but continuing..."
        fi
    else
        print_warning "remove-olm.sh script not found at ${remove_olm_script}"
        print_info "Falling back to basic OLM cleanup..."
        
        # Fallback to basic cleanup (keeping the original logic as backup)
        local removed_something=false
        
        # Remove OLM namespaces
        local olm_namespaces=("olm" "operators")
        for ns in "${olm_namespaces[@]}"; do
            if oc get namespace "${ns}" &> /dev/null; then
                print_info "Removing namespace ${ns}..."
                if oc delete namespace "${ns}" --timeout=60s; then
                    print_success "Namespace ${ns} removed"
                    removed_something=true
                else
                    print_warning "Failed to remove namespace ${ns}, it may have dependencies"
                fi
            else
                print_info "Namespace ${ns} not found"
            fi
        done
        
        # Remove OLM CRDs
        local olm_crds=(
            "catalogsources.operators.coreos.com"
            "clusterserviceversions.operators.coreos.com"
            "installplans.operators.coreos.com"
            "olmconfigs.operators.coreos.com"
            "operatorconditions.operators.coreos.com"
            "operatorgroups.operators.coreos.com"
            "operators.operators.coreos.com"
            "subscriptions.operators.coreos.com"
            "packages.operators.coreos.com"
        )
        
        for crd in "${olm_crds[@]}"; do
            if oc get crd "${crd}" &> /dev/null; then
                print_info "Removing CRD ${crd}..."
                if oc delete crd "${crd}"; then
                    print_success "CRD ${crd} removed"
                    removed_something=true
                else
                    print_warning "Failed to remove CRD ${crd}"
                fi
            else
                print_info "CRD ${crd} not found"
            fi
        done
        
        # Remove OLM cluster roles and bindings
        local olm_resources=(
            "clusterrole.rbac.authorization.k8s.io/system:controller:operator-lifecycle-manager"
            "clusterrole.rbac.authorization.k8s.io/aggregate-olm-edit"
            "clusterrole.rbac.authorization.k8s.io/aggregate-olm-view"
            "clusterrolebinding.rbac.authorization.k8s.io/olm-operator-binding-olm"
        )
        
        for resource in "${olm_resources[@]}"; do
            if oc get "${resource}" &> /dev/null; then
                print_info "Removing ${resource}..."
                if oc delete "${resource}"; then
                    print_success "${resource} removed"
                    removed_something=true
                else
                    print_warning "Failed to remove ${resource}"
                fi
            else
                print_info "${resource} not found"
            fi
        done
        
        if [ "$removed_something" = true ]; then
            print_success "Basic OLM removal completed!"
            print_warning "Note: Any operators installed via OLM may no longer function"
        else
            print_info "No OLM resources found to remove"
        fi
    fi
}

# Function to install fake resources
install_fake_resources() {
    local version=${1:-$DEFAULT_OPENSHIFT_VERSION}
    
    print_info "Setting up fake OpenShift resources for certsuite compatibility"
    print_info "Target version: ${version}"
    
    # Install OLM first if not already present
    install_olm
    
    # Check if config.openshift.io API group exists, create CRDs if needed
    if ! oc api-resources --api-group=config.openshift.io &>/dev/null; then
        print_info "config.openshift.io API group not found, creating CRDs..."
        create_clusteroperator_crd
        create_clusterversion_crd
    else
        print_info "config.openshift.io API group already exists"
        
        # Check and create individual CRDs if missing
        if ! clusteroperator_crd_exists; then
            print_info "ClusterOperator CRD not found, creating it..."
            create_clusteroperator_crd
        fi
        
        if ! clusterversion_crd_exists; then
            print_info "ClusterVersion CRD not found, creating it..."
            create_clusterversion_crd
        fi
        
        if ! operatorhub_crd_exists; then
            print_info "OperatorHub CRD not found, creating it..."
            create_operatorhub_crd
        fi
    fi
    
    # Check if operators.coreos.com API group exists, create OLM CRDs if needed
    if ! oc api-resources --api-group=operators.coreos.com &>/dev/null; then
        print_info "operators.coreos.com API group not found, creating OLM CRDs..."
        create_catalogsource_crd
        create_csv_crd
        create_subscription_crd
        create_installplan_crd
    else
        print_info "operators.coreos.com API group already exists"
        
        # Check and create individual OLM CRDs if missing
        if ! catalogsource_crd_exists; then
            print_info "CatalogSource CRD not found, creating it..."
            create_catalogsource_crd
        fi
        
        if ! csv_crd_exists; then
            print_info "ClusterServiceVersion CRD not found, creating it..."
            create_csv_crd
        fi
        
        if ! subscription_crd_exists; then
            print_info "Subscription CRD not found, creating it..."
            create_subscription_crd
        fi
        
        if ! installplan_crd_exists; then
            print_info "InstallPlan CRD not found, creating it..."
            create_installplan_crd
        fi
    fi
    
    # Create or update ClusterOperator
    if clusteroperator_exists; then
        print_warning "ClusterOperator '${CLUSTER_OPERATOR_NAME}' already exists, updating..."
    fi
    create_clusteroperator "$version"
    
    # Create additional ClusterOperators for better compatibility
    create_additional_clusteroperators "$version"
    
    # Create or update ClusterVersion
    if clusterversion_exists; then
        print_warning "ClusterVersion '${CLUSTER_VERSION_NAME}' already exists, updating..."
    fi
    create_clusterversion "$version"

    # Ensure OperatorHub CRD and default instance exist
    if ! operatorhub_crd_exists; then
        print_info "OperatorHub CRD not found, creating it..."
        create_operatorhub_crd
    fi
    if operatorhub_exists; then
        print_warning "OperatorHub 'cluster' already exists, updating..."
    fi
    create_operatorhub_resource
    
    # Create additional OpenShift CRDs and resources
    if ! oauth_crd_exists; then
        print_info "OAuth CRD not found, creating it..."
        create_oauth_crd
    fi
    
    if ! project_crd_exists; then
        print_info "Project CRD not found, creating it..."
        create_project_crd
    fi
    
    # Create MCO CRDs for platform alteration compatibility
    if ! machineconfig_crd_exists; then
        print_info "MachineConfig CRD not found, creating it for platform alteration compatibility..."
        create_machineconfig_crd
    fi
    
    if ! machineconfigpool_crd_exists; then
        print_info "MachineConfigPool CRD not found, creating it for platform alteration compatibility..."
        create_machineconfigpool_crd
    fi
    
    # Create OAuth resource
    create_oauth_resource "$version"
    
    # Create fake MCO resources for platform alteration tests
    create_fake_machineconfigs "$version"
    create_fake_machineconfigpools "$version"
    
    # Install real Multus (DaemonSet) rather than spoofing NAD API/resources
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local install_multus_script="${script_dir}/install-multus.sh"
    if [[ -x "${install_multus_script}" ]]; then
        print_info "Installing real Multus (DaemonSet) via ${install_multus_script}..."
        if "${install_multus_script}"; then
            print_success "Real Multus installed successfully"
        else
            print_warning "Multus installer returned non-zero exit; continuing"
        fi
    else
        print_warning "install-multus.sh not found or not executable at ${install_multus_script}; skipping real Multus install"
    fi
    
    # Create openshift-marketplace namespace for compatibility
    create_openshift_marketplace_namespace
    
    # Verify installation
    print_info "Verifying installation..."
    local co_exists=false
    local cv_exists=false
    
    if clusteroperator_exists; then
        co_exists=true
        print_success "✅ ClusterOperator created successfully"
    else
        print_error "❌ ClusterOperator verification failed"
    fi
    
    if clusterversion_exists; then
        cv_exists=true
        print_success "✅ ClusterVersion created successfully"
    else
        print_error "❌ ClusterVersion verification failed"
    fi
    
    # Check MCO resources
    local mco_exists=false
    if oc get machineconfigs --no-headers &>/dev/null; then
        mco_exists=true
        print_success "✅ MachineConfigs created successfully"
        local mc_count
        mc_count=$(oc get machineconfigs --no-headers | wc -l)
        print_info "Found $mc_count MachineConfig(s)"
    else
        print_warning "⚠️ MachineConfigs verification failed"
    fi
    
    if oc get machineconfigpools --no-headers &>/dev/null; then
        print_success "✅ MachineConfigPools created successfully"
        local mcp_count
        mcp_count=$(oc get machineconfigpools --no-headers | wc -l)
        print_info "Found $mcp_count MachineConfigPool(s)"
    else
        print_warning "⚠️ MachineConfigPools verification failed"
    fi
    
    # Check Multus resources
    local multus_exists=false
    if oc get networkattachmentdefinitions --no-headers &>/dev/null; then
        multus_exists=true
        print_success "✅ NetworkAttachmentDefinitions created successfully"
        local nad_count
        nad_count=$(oc get networkattachmentdefinitions --all-namespaces --no-headers | wc -l)
        print_info "Found $nad_count NetworkAttachmentDefinition(s)"
    else
        print_warning "⚠️ NetworkAttachmentDefinitions verification failed"
    fi
    
    if [[ "$co_exists" == true && "$cv_exists" == true ]]; then
        local installed_version
        installed_version=$(oc get clusteroperator "$CLUSTER_OPERATOR_NAME" -o jsonpath='{.status.versions[?(@.name=="operator")].version}' 2>/dev/null || echo "unknown")
        print_success "Installation complete!"
        print_success "Certsuite should now detect this as OpenShift version: ${installed_version}"
        echo
        print_info "You can now run certsuite:"
        echo "  certsuite run --log-level debug"
        echo
        print_info "To check the detected version:"
        echo "  oc get clusteroperator ${CLUSTER_OPERATOR_NAME} -o yaml"
        echo "  oc get clusterversion ${CLUSTER_VERSION_NAME} -o yaml"
        echo
        print_info "To test OpenShift resources:"
        echo "  oc get clusterversion"
        echo "  oc get machineconfigs"
        echo "  oc get machineconfigpools"
        echo "  oc get networkattachmentdefinitions --all-namespaces"
        echo
        if [ "$mco_exists" = true ]; then
            print_success "✅ Platform alteration tests should now work with MCO resources!"
        else
            print_warning "⚠️ MCO resources may not be fully available - some platform tests might still fail"
        fi
        
        if [ "$multus_exists" = true ]; then
            print_success "✅ Networking tests should now work with Multus NAD resources!"
        else
            print_warning "⚠️ Multus resources may not be fully available - some networking tests might still fail"
        fi
    else
        print_error "Verification failed - some resources missing"
        exit 1
    fi
}

# Function to remove fake resources
remove_fake_resources() {
    print_info "Removing fake OpenShift resources..."
    
    local removed_something=false
    
    # Remove OLM if requested
    if [ "$REMOVE_OLM" = true ]; then
        remove_olm
    fi
    
    # Remove ClusterVersion
    if clusterversion_exists; then
        print_info "Removing ClusterVersion '${CLUSTER_VERSION_NAME}'..."
        oc delete clusterversion "$CLUSTER_VERSION_NAME"
        print_success "ClusterVersion removed"
        removed_something=true
    else
        print_info "ClusterVersion '${CLUSTER_VERSION_NAME}' not found"
    fi
    
    # Remove ClusterOperator
    if clusteroperator_exists; then
        print_info "Removing ClusterOperator '${CLUSTER_OPERATOR_NAME}'..."
        oc delete clusteroperator "$CLUSTER_OPERATOR_NAME"
        print_success "ClusterOperator removed"
        removed_something=true
    else
        print_info "ClusterOperator '${CLUSTER_OPERATOR_NAME}' not found"
    fi
    
    # Remove ClusterVersion CRD (be careful here - only remove if we created it)
    if clusterversion_crd_exists; then
        local created_by_us
        created_by_us=$(oc get crd "$CLUSTERVERSION_CRD_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
        if [[ "$created_by_us" == "certsuite-microshift-setup-script" ]]; then
            print_info "Removing ClusterVersion CRD..."
            oc delete crd "$CLUSTERVERSION_CRD_NAME"
            print_success "ClusterVersion CRD removed"
            removed_something=true
        else
            print_warning "ClusterVersion CRD exists but was not created by this script, leaving it alone"
        fi
    else
        print_info "ClusterVersion CRD not found"
    fi
    
    # Remove ClusterOperator CRD (be careful here - only remove if we created it)
    if clusteroperator_crd_exists; then
        local created_by_us
        created_by_us=$(oc get crd "$CLUSTEROPERATOR_CRD_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
        if [[ "$created_by_us" == "certsuite-microshift-setup-script" ]]; then
            print_info "Removing ClusterOperator CRD..."
            oc delete crd "$CLUSTEROPERATOR_CRD_NAME"
            print_success "ClusterOperator CRD removed"
            removed_something=true
        else
            print_warning "ClusterOperator CRD exists but was not created by this script, leaving it alone"
        fi
    else
        print_info "ClusterOperator CRD not found"
    fi
    
    # Remove OLM CRDs (be careful here - only remove if we created them, unless --remove-olm is specified)
    for crd_name in "$CATALOGSOURCE_CRD_NAME" "$CSV_CRD_NAME" "$SUBSCRIPTION_CRD_NAME" "$INSTALLPLAN_CRD_NAME"; do
        crd_display_name=$(echo "$crd_name" | cut -d'.' -f1)
        if oc get crd "$crd_name" &> /dev/null; then
            local created_by_us
            created_by_us=$(oc get crd "$crd_name" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
            if [[ "$created_by_us" == "certsuite-microshift-setup-script" ]]; then
                print_info "Removing ${crd_display_name} CRD..."
                oc delete crd "$crd_name"
                print_success "${crd_display_name} CRD removed"
                removed_something=true
            else
                print_warning "${crd_display_name} CRD exists but was not created by this script, leaving it alone"
            fi
        else
            print_info "${crd_display_name} CRD not found"
        fi
    done
    
    # Remove MCO resources created by this script
    local machineconfigs
    machineconfigs=$(oc get machineconfigs -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.created-by}{"\n"}{end}' 2>/dev/null | grep "certsuite-microshift-setup-script" | awk '{print $1}' || echo "")
    
    for mc in $machineconfigs; do
        if [ -n "$mc" ]; then
            print_info "Removing MachineConfig '$mc'..."
            oc delete machineconfig "$mc"
            print_success "MachineConfig '$mc' removed"
            removed_something=true
        fi
    done
    
    local machineconfigpools
    machineconfigpools=$(oc get machineconfigpools -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.created-by}{"\n"}{end}' 2>/dev/null | grep "certsuite-microshift-setup-script" | awk '{print $1}' || echo "")
    
    for mcp in $machineconfigpools; do
        if [ -n "$mcp" ]; then
            print_info "Removing MachineConfigPool '$mcp'..."
            oc delete machineconfigpool "$mcp"
            print_success "MachineConfigPool '$mcp' removed"
            removed_something=true
        fi
    done
    
    # Remove MCO CRDs (be careful here - only remove if we created them)
    for crd_name in "$MACHINECONFIG_CRD_NAME" "$MACHINECONFIGPOOL_CRD_NAME"; do
        if oc get crd "$crd_name" &> /dev/null; then
            local created_by_us
            created_by_us=$(oc get crd "$crd_name" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
            if [[ "$created_by_us" == "certsuite-microshift-setup-script" ]]; then
                print_info "Removing MCO CRD '$crd_name'..."
                oc delete crd "$crd_name"
                print_success "MCO CRD '$crd_name' removed"
                removed_something=true
            else
                print_warning "MCO CRD '$crd_name' exists but was not created by this script, leaving it alone"
            fi
        else
            print_info "MCO CRD '$crd_name' not found"
        fi
    done
    
    # Remove Multus resources created by this script
    local networkattachmentdefinitions
    networkattachmentdefinitions=$(oc get networkattachmentdefinitions --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{" "}{.metadata.annotations.created-by}{"\n"}{end}' 2>/dev/null | grep "certsuite-microshift-setup-script" | awk '{print $1}' || echo "")
    
    for nad in $networkattachmentdefinitions; do
        if [ -n "$nad" ]; then
            local namespace
            local name
            namespace=$(echo "$nad" | cut -d'/' -f1)
            name=$(echo "$nad" | cut -d'/' -f2)
            print_info "Removing NetworkAttachmentDefinition '$name' in namespace '$namespace'..."
            oc delete networkattachmentdefinition "$name" -n "$namespace"
            print_success "NetworkAttachmentDefinition '$name' removed"
            removed_something=true
        fi
    done
    
    # Remove Multus CRD (be careful here - only remove if we created it)
    if oc get crd "$NETWORKATTACHMENTDEFINITION_CRD_NAME" &> /dev/null; then
        local created_by_us
        created_by_us=$(oc get crd "$NETWORKATTACHMENTDEFINITION_CRD_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
        if [[ "$created_by_us" == "certsuite-microshift-setup-script" ]]; then
            print_info "Removing Multus CRD '$NETWORKATTACHMENTDEFINITION_CRD_NAME'..."
            oc delete crd "$NETWORKATTACHMENTDEFINITION_CRD_NAME"
            print_success "Multus CRD '$NETWORKATTACHMENTDEFINITION_CRD_NAME' removed"
            removed_something=true
        else
            print_warning "Multus CRD '$NETWORKATTACHMENTDEFINITION_CRD_NAME' exists but was not created by this script, leaving it alone"
        fi
    else
        print_info "Multus CRD '$NETWORKATTACHMENTDEFINITION_CRD_NAME' not found"
    fi
    
    # Remove openshift-marketplace namespace (be careful here - only remove if we created it)
    if oc get namespace openshift-marketplace &> /dev/null; then
        local created_by_us
        created_by_us=$(oc get namespace openshift-marketplace -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "")
        if [[ "$created_by_us" == "certsuite-microshift-setup-script" ]]; then
            print_info "Removing openshift-marketplace namespace..."
            oc delete namespace openshift-marketplace
            print_success "openshift-marketplace namespace removed"
            removed_something=true
        else
            print_warning "openshift-marketplace namespace exists but was not created by this script, leaving it alone"
        fi
    else
        print_info "openshift-marketplace namespace not found"
    fi
    
    if [ "$removed_something" = true ]; then
        print_success "Cleanup complete!"
        print_info "Certsuite will now detect microshift as a non-OpenShift cluster"
    else
        print_info "Nothing to remove"
    fi
}

# Function to check current status
check_status() {
    print_info "Checking fake OpenShift resources status..."
    echo
    
    # Check API group
    if oc api-resources --api-group=config.openshift.io &>/dev/null; then
        print_success "config.openshift.io API group: EXISTS"
    else
        print_warning "config.openshift.io API group: NOT FOUND"
    fi
    
    # Check ClusterOperator CRD
    if clusteroperator_crd_exists; then
        print_success "ClusterOperator CRD: EXISTS"
        local created_by
        created_by=$(oc get crd "$CLUSTEROPERATOR_CRD_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "unknown")
        echo "  Created by: $created_by"
    else
        print_warning "ClusterOperator CRD: NOT FOUND"
    fi
    
    # Check ClusterVersion CRD
    if clusterversion_crd_exists; then
        print_success "ClusterVersion CRD: EXISTS"
        local created_by
        created_by=$(oc get crd "$CLUSTERVERSION_CRD_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "unknown")
        echo "  Created by: $created_by"
    else
        print_warning "ClusterVersion CRD: NOT FOUND"
    fi
    
    # Check OLM CRDs
    echo
    print_info "OLM (Operator Lifecycle Manager) CRDs:"
    
    for crd_name in "$CATALOGSOURCE_CRD_NAME" "$CSV_CRD_NAME" "$SUBSCRIPTION_CRD_NAME" "$INSTALLPLAN_CRD_NAME"; do
        crd_display_name=$(echo "$crd_name" | cut -d'.' -f1 | tr '[:lower:]' '[:upper:]')
        if oc get crd "$crd_name" &> /dev/null; then
            print_success "${crd_display_name} CRD: EXISTS"
            local created_by
            created_by=$(oc get crd "$crd_name" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "unknown")
            echo "  Created by: $created_by"
        else
            print_warning "${crd_display_name} CRD: NOT FOUND"
        fi
    done
    
    echo
    
    # Check ClusterOperator
    if clusteroperator_exists; then
        print_success "ClusterOperator '${CLUSTER_OPERATOR_NAME}': EXISTS"
        local version
        version=$(oc get clusteroperator "$CLUSTER_OPERATOR_NAME" -o jsonpath='{.status.versions[?(@.name=="operator")].version}' 2>/dev/null || echo "unknown")
        echo "  Simulated OpenShift version: $version"
        
        local created_by
        created_by=$(oc get clusteroperator "$CLUSTER_OPERATOR_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "unknown")
        echo "  Created by: $created_by"
    else
        print_warning "ClusterOperator '${CLUSTER_OPERATOR_NAME}': NOT FOUND"
    fi
    
    # Check ClusterVersion
    if clusterversion_exists; then
        print_success "ClusterVersion '${CLUSTER_VERSION_NAME}': EXISTS"
        local version
        version=$(oc get clusterversion "$CLUSTER_VERSION_NAME" -o jsonpath='{.spec.desiredUpdate.version}' 2>/dev/null || echo "unknown")
        echo "  Desired version: $version"
        
        local created_by
        created_by=$(oc get clusterversion "$CLUSTER_VERSION_NAME" -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "unknown")
        echo "  Created by: $created_by"
    else
        print_warning "ClusterVersion '${CLUSTER_VERSION_NAME}': NOT FOUND"
    fi
    
    # Check openshift-marketplace namespace
    if oc get namespace openshift-marketplace &> /dev/null; then
        print_success "openshift-marketplace namespace: EXISTS"
        local created_by
        created_by=$(oc get namespace openshift-marketplace -o jsonpath='{.metadata.annotations.created-by}' 2>/dev/null || echo "unknown")
        echo "  Created by: $created_by"
    else
        print_warning "openshift-marketplace namespace: NOT FOUND"
    fi
    
    echo
    
    # Provide guidance based on status
    local olm_crds_exist=true
    for crd_name in "$CATALOGSOURCE_CRD_NAME" "$CSV_CRD_NAME" "$SUBSCRIPTION_CRD_NAME" "$INSTALLPLAN_CRD_NAME"; do
        if ! oc get crd "$crd_name" &> /dev/null; then
            olm_crds_exist=false
            break
        fi
    done
    
    # Check MCO resources
    echo
    print_info "MCO (Machine Config Operator) resources:"
    
    if oc get machineconfigs --no-headers &>/dev/null; then
        local mc_count
        mc_count=$(oc get machineconfigs --no-headers | wc -l)
        print_success "MachineConfigs: $mc_count found"
    else
        print_warning "MachineConfigs: NOT FOUND"
    fi
    
    if oc get machineconfigpools --no-headers &>/dev/null; then
        local mcp_count
        mcp_count=$(oc get machineconfigpools --no-headers | wc -l)
        print_success "MachineConfigPools: $mcp_count found"
    else
        print_warning "MachineConfigPools: NOT FOUND"
    fi
    
    local mco_resources_exist=false
    if oc get machineconfigs --no-headers &>/dev/null && oc get machineconfigpools --no-headers &>/dev/null; then
        mco_resources_exist=true
    fi
    
    # Check Multus resources
    echo
    print_info "Multus CNI resources:"
    
    if oc get networkattachmentdefinitions --no-headers &>/dev/null; then
        local nad_count
        nad_count=$(oc get networkattachmentdefinitions --all-namespaces --no-headers | wc -l)
        print_success "NetworkAttachmentDefinitions: $nad_count found"
    else
        print_warning "NetworkAttachmentDefinitions: NOT FOUND"
    fi
    
    local multus_resources_exist=false
    if oc get networkattachmentdefinitions --no-headers &>/dev/null; then
        multus_resources_exist=true
    fi
    
    echo
    
    if clusteroperator_exists && clusterversion_exists && [ "$olm_crds_exist" = true ] && [ "$mco_resources_exist" = true ] && [ "$multus_resources_exist" = true ]; then
        print_info "✅ All fake resources are set up - certsuite should detect this as OpenShift with OLM, MCO, and Multus support"
        echo
        print_info "Test commands:"
        echo "  oc get clusteroperator"
        echo "  oc get clusterversion"
        echo "  oc get catalogsources  # should not show 'resource not found'"
        echo "  oc get machineconfigs"
        echo "  oc get machineconfigpools"
        echo "  oc get networkattachmentdefinitions --all-namespaces"
        echo
        print_success "Platform alteration tests should now work!"
        print_success "Networking tests should now work!"
    elif clusteroperator_exists && clusterversion_exists && [ "$olm_crds_exist" = true ] && [ "$mco_resources_exist" = true ]; then
        print_info "✅ OpenShift, OLM, and MCO resources exist but Multus resources are missing"
        print_info "Networking tests may still fail with 'resource not found' errors"
        print_info "Run: $0 install  # to ensure all resources including Multus are created"
    elif clusteroperator_exists && clusterversion_exists && [ "$olm_crds_exist" = true ]; then
        print_info "⚠️  OpenShift and OLM resources exist but MCO/Multus resources are missing"
        print_info "Platform alteration and networking tests may still fail with 'resource not found' errors"
        print_info "Run: $0 install  # to ensure all resources including MCO and Multus are created"
    elif clusteroperator_exists && clusterversion_exists; then
        print_info "⚠️  Basic OpenShift resources exist but OLM/MCO/Multus CRDs are missing"
        print_info "Some operator-related, platform alteration, and networking tests may still fail"
        print_info "Run: $0 install  # to ensure all resources are created"
    else
        print_info "❌ Fake resources not found - certsuite will detect this as non-OpenShift"
        print_info "Run: $0 install"
    fi
}

# Main function
main() {
    # Parse all arguments first to handle flags
    local args=("$@")
    local command="install"
    local version="$DEFAULT_OPENSHIFT_VERSION"
    local processed_args=()
    
    # Process all arguments
    for arg in "${args[@]}"; do
        case "$arg" in
            --remove-olm)
                REMOVE_OLM=true
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            install|remove|check|help)
                command="$arg"
                ;;
            *)
                # If it's not a flag and not a command, treat as version
                if [[ "$command" != "help" ]] && [[ "$arg" != "--help" ]] && [[ "$arg" != "-h" ]]; then
                    if [[ "$command" == "install" ]] && [[ "$version" == "$DEFAULT_OPENSHIFT_VERSION" ]]; then
                        version="$arg"
                    else
                        print_error "Unknown option: $arg"
                        show_usage
                        exit 1
                    fi
                fi
                ;;
        esac
    done
    

    
    case "$command" in
        install)
            check_oc_command
            check_cluster_connection
            install_fake_resources "$version"
            ;;
        remove)
            check_oc_command
            check_cluster_connection
            remove_fake_resources
            ;;
        check)
            check_oc_command
            check_cluster_connection
            check_status
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            echo
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"