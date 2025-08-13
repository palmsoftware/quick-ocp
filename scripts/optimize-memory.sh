#!/usr/bin/env bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

# Memory optimization for GitHub Actions runners running CRC
optimize_runner_memory() {
    info "Optimizing GitHub Actions runner memory usage"
    
    # Disable swap to prevent memory swapping overhead
    sudo swapoff -a || true
    
    # Tune kernel memory parameters for low-memory environments
    sudo sysctl -w vm.swappiness=1
    sudo sysctl -w vm.dirty_ratio=5
    sudo sysctl -w vm.dirty_background_ratio=2
    sudo sysctl -w vm.vfs_cache_pressure=150
    sudo sysctl -w vm.min_free_kbytes=65536
    
    # Reduce memory overcommit to prevent OOM
    sudo sysctl -w vm.overcommit_memory=2
    sudo sysctl -w vm.overcommit_ratio=80
    
    # Stop and disable memory-heavy services permanently
    services_to_stop=(
        "snapd.service"
        "unattended-upgrades.service" 
        "packagekit.service"
        "accounts-daemon.service"
        "udisks2.service"
        "polkit.service"
        "thermald.service"
        "ModemManager.service"
        "avahi-daemon.service"
        "mysql.service"
        "postgresql.service"
        "mongod.service"
        "redis.service"
        "apache2.service"
        "nginx.service"
        "cups.service"
    )
    
    for service in "${services_to_stop[@]}"; do
        sudo systemctl stop "$service" 2>/dev/null || true
        sudo systemctl disable "$service" 2>/dev/null || true
    done
    
    # Aggressively clean package cache and temporary files
    sudo apt-get autoremove --purge -y
    sudo apt-get autoclean
    sudo apt-get clean
    
    # Remove unnecessary packages that consume memory
    packages_to_remove=(
        "firefox"
        "chromium-browser" 
        "libreoffice*"
        "thunderbird"
        "cups"
        "whoopsie"
        "popularity-contest"
        "ubuntu-report"
        "apport"
        "landscape-client"
        "snapd"
        "snap-confine"
        "squashfs-tools"
        "modemmanager"
        "avahi-daemon"
        "speech-dispatcher*"
        "orca"
        "brltty"
        "packagekit"
        "unattended-upgrades"
    )
    
    sudo apt-get remove -y --auto-remove "${packages_to_remove[@]}" 2>/dev/null || true
    
    # Clear system caches and logs
    sudo journalctl --vacuum-time=1h
    sudo journalctl --vacuum-size=10M
    sudo rm -rf /tmp/* /var/tmp/* /var/cache/* 2>/dev/null || true
    
    # Drop all caches to free memory
    sync
    sudo sysctl vm.drop_caches=3
    
    # Set up memory monitoring
    setup_memory_monitoring
    
    ok "Runner memory optimization completed"
}

setup_memory_monitoring() {
    info "Setting up memory monitoring during CRC execution"
    
    # Create a memory monitoring script
    cat > /tmp/memory_monitor.sh << 'EOF'
#!/bin/bash
while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    MEMINFO=$(cat /proc/meminfo)
    TOTAL_KB=$(echo "$MEMINFO" | awk '/MemTotal:/ {print $2}')
    AVAILABLE_KB=$(echo "$MEMINFO" | awk '/MemAvailable:/ {print $2}')
    USED_KB=$((TOTAL_KB - AVAILABLE_KB))
    USED_PCT=$((USED_KB * 100 / TOTAL_KB))
    
    echo "[$TIMESTAMP] Memory: ${USED_PCT}% used (${USED_KB}KB/${TOTAL_KB}KB)"
    
    # Alert if memory usage is high
    if [ "$USED_PCT" -gt 90 ]; then
        echo "[$TIMESTAMP] WARNING: Memory usage is ${USED_PCT}%!"
        # Show top memory consumers
        ps aux --sort=-%mem | head -10
    fi
    
    sleep 30
done
EOF
    
    chmod +x /tmp/memory_monitor.sh
    
    # Start monitoring in background
    nohup /tmp/memory_monitor.sh > /tmp/memory_monitor.log 2>&1 &
    echo $! > /tmp/memory_monitor.pid
    
    info "Memory monitoring started (PID: $(cat /tmp/memory_monitor.pid))"
}

optimize_crc_memory() {
    info "Optimizing CRC memory configuration"
    
    # Check current memory
    total_mem_gb=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
    available_mem_gb=$(awk '/MemAvailable/ {printf "%.1f", $2/1024/1024}' /proc/meminfo)
    
    info "System memory - Total: ${total_mem_gb}GB, Available: ${available_mem_gb}GB"
    
    # CRC has strict minimum requirements that cannot be reduced
    # Minimum: 4 CPUs, 10752MB memory
    optimal_crc_mem=10752
    warn "CRC requires minimum 10752MB memory - cannot be reduced"
    
    info "Calculated optimal CRC memory: ${optimal_crc_mem}MB"
    
    # Configure CRC with minimum required settings (cannot be reduced further)
    crc config set memory "$optimal_crc_mem"
    crc config set cpus 4
    crc config set disk-size 31
    crc config set enable-cluster-monitoring false
    crc config set disable-update-check true
    crc config set consent-telemetry no
    crc config set network-mode user
    
    # Additional CRC optimizations for stability
    export CRC_MEMORY_OPTIMIZED=true
    export OPENSHIFT_INSTALL_SKIP_HOSTCERT_VERIFICATION=true
    export CRC_MACHINE_LOG_LEVEL=debug
    export CRC_DIAL_TIMEOUT=30s
    export CRC_SSH_TIMEOUT=60s
    
    # Optimize host for VM stability
    optimize_host_for_vm_stability
    
    ok "CRC memory optimization configured"
}

optimize_host_for_vm_stability() {
    info "Optimizing host environment for VM stability"
    
    # Tune VM-related kernel parameters
    sudo sysctl -w vm.max_map_count=262144
    sudo sysctl -w fs.inotify.max_user_watches=524288
    sudo sysctl -w fs.inotify.max_user_instances=8192
    sudo sysctl -w kernel.pid_max=4194304
    
    # Optimize I/O scheduler for VM workloads
    for dev in /sys/block/*/queue/scheduler; do
        if [ -w "$dev" ]; then
            echo "mq-deadline" | sudo tee "$dev" 2>/dev/null || true
        fi
    done
    
    # Increase network buffer sizes for SSH stability
    sudo sysctl -w net.core.rmem_max=16777216
    sudo sysctl -w net.core.wmem_max=16777216
    sudo sysctl -w net.ipv4.tcp_rmem="4096 65536 16777216"
    sudo sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216"
    
    # Disable CPU frequency scaling to improve VM stability
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo "performance" | sudo tee "$cpu" 2>/dev/null || true
        done
    fi
    
    # Ensure libvirt/QEMU has sufficient resources
    if systemctl is-active libvirtd >/dev/null 2>&1; then
        sudo systemctl restart libvirtd
    fi
    
    # Clear all caches one more time before VM start
    sync
    sudo sysctl vm.drop_caches=3
    
    ok "Host VM stability optimizations applied"
}

post_crc_memory_optimization() {
    info "Applying post-CRC memory optimizations"
    
    # Wait for cluster to be accessible
    local retries=30
    while ! oc cluster-info >/dev/null 2>&1 && [ $retries -gt 0 ]; do
        info "Waiting for cluster to be accessible... ($retries retries left)"
        sleep 10
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        err "Cluster did not become accessible within timeout"
        return 1
    fi
    
    # Scale down memory-intensive components immediately
    scale_down_components
    
    # Clean up node filesystem
    cleanup_node_filesystem
    
    ok "Post-CRC memory optimization completed"
}

scale_down_components() {
    info "Scaling down memory-intensive OpenShift components"
    
    # Critical memory-saving scale downs
    local components=(
        "deployment.apps/cluster-monitoring-operator -n openshift-monitoring"
        "deployment.apps/prometheus-operator -n openshift-monitoring"
        "statefulset.apps/prometheus-k8s -n openshift-monitoring"
        "statefulset.apps/alertmanager-main -n openshift-monitoring"
        "deployment.apps/grafana -n openshift-monitoring"
        "deployment.apps/kube-state-metrics -n openshift-monitoring"
        "daemonset.apps/node-exporter -n openshift-monitoring"
        "deployment.apps/console -n openshift-console"
        "deployment.apps/downloads -n openshift-console"
        "deployment.apps/console-operator -n openshift-console"
        "deployment.apps/marketplace-operator -n openshift-marketplace"
        "deployment.apps/cluster-version-operator -n openshift-cluster-version"
        "deployment.apps/image-registry -n openshift-image-registry"
        "deployment.apps/insights-operator -n openshift-insights"
    )
    
    for component in "${components[@]}"; do
        oc scale --replicas=0 $component 2>/dev/null || true
    done
    
    # Give it time to scale down
    sleep 30
    
    info "Component scaling completed"
}

cleanup_node_filesystem() {
    info "Cleaning up node filesystem to free memory"
    
    local node_name
    node_name=$(oc get nodes -o jsonpath='{.items[0].metadata.name}')
    
    # Clean up node filesystem via debug pod
    oc debug node/"$node_name" -- chroot /host sh -c '
        # Clear container logs
        find /var/log/containers -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
        find /var/log/pods -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
        
        # Clear system logs
        journalctl --vacuum-time=1h
        journalctl --vacuum-size=50M
        
        # Clear temporary files
        rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
        
        # Clear package caches
        rm -rf /var/cache/dnf/* /var/cache/yum/* 2>/dev/null || true
        
        # Drop caches
        sync
        echo 3 > /proc/sys/vm/drop_caches
    ' 2>/dev/null || warn "Some cleanup operations failed"
    
    ok "Node filesystem cleanup completed"
}

show_memory_status() {
    info "=== Final Memory Status ==="
    free -h
    echo
    
    info "=== Top Memory Consumers ==="
    ps aux --sort=-%mem | head -10
    echo
    
    info "=== Available Memory ==="
    awk '/MemAvailable/ {printf "Available: %.2f GB\n", $2/1024/1024}' /proc/meminfo
    
    if [ -f /tmp/memory_monitor.log ]; then
        info "=== Memory Monitoring Log (last 10 lines) ==="
        tail -10 /tmp/memory_monitor.log
    fi
}

cleanup_monitoring() {
    if [ -f /tmp/memory_monitor.pid ]; then
        local pid=$(cat /tmp/memory_monitor.pid)
        kill "$pid" 2>/dev/null || true
        rm -f /tmp/memory_monitor.pid
        info "Stopped memory monitoring"
    fi
}

check_crc_stability() {
    info "Checking CRC stability and SSH connectivity"
    
    # Check if CRC VM is responsive
    local max_attempts=10
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        info "Testing CRC SSH connectivity (attempt $attempt/$max_attempts)"
        
        if crc ssh -- echo "SSH test successful" >/dev/null 2>&1; then
            ok "CRC SSH connectivity verified"
            return 0
        else
            warn "CRC SSH test failed, attempt $attempt"
            if [ $attempt -lt $max_attempts ]; then
                sleep 10
            fi
        fi
        ((attempt++))
    done
    
    err "CRC SSH connectivity failed after $max_attempts attempts"
    return 1
}

main() {
    case "${1:-optimize}" in
        "optimize")
            optimize_runner_memory
            ;;
        "crc")
            optimize_crc_memory
            ;;
        "post-crc")
            post_crc_memory_optimization
            ;;
        "check-crc")
            check_crc_stability
            ;;
        "status")
            show_memory_status
            ;;
        "cleanup")
            cleanup_monitoring
            ;;
        *)
            echo "Usage: $0 [optimize|crc|post-crc|check-crc|status|cleanup]"
            echo "  optimize  - Optimize GitHub runner memory"
            echo "  crc       - Optimize CRC memory configuration"
            echo "  post-crc  - Apply post-CRC memory optimizations"
            echo "  check-crc - Check CRC stability and SSH connectivity"
            echo "  status    - Show current memory status"
            echo "  cleanup   - Stop memory monitoring"
            exit 1
            ;;
    esac
}

# Trap to cleanup on exit
trap cleanup_monitoring EXIT

main "$@"
