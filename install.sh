#!/bin/sh

# Version
VERSION="2.0"

# Default: auto-detect instances, or specify via environment variables
# Usage: ./install.sh                    # Auto-detect all instances
# Usage: ./install.sh -i 1               # Install only for instance 1
# Usage: ./install.sh -i 1,2,3           # Install for instances 1,2,3
# Usage: KLIPPER_INSTANCE=2 ./install.sh # Install for specific instance

# Parse arguments
INSTANCE_SPEC="auto"
UNINSTALL=0

while getopts "i:uhv" arg; do
    case $arg in
        i) INSTANCE_SPEC="$OPTARG" ;;
        u) UNINSTALL=1 ;;
        h) usage ;;
        v) show_version ;;
        *) usage ;;
    esac
done

usage() {
    echo "Usage: $0 [-i instance] [-u] [-h] [-v]" 1>&2
    echo "Options:" 1>&2
    echo "  -i <num>    Instance number(s): 1, 2, 3 or 1,2,3 (default: auto-detect)" 1>&2
    echo "  -u          Uninstall ValgACE" 1>&2
    echo "  -h          Show this help" 1>&2
    echo "  -v          Show version" 1>&2
    echo "" 1>&2
    echo "Examples:" 1>&2
    echo "  $0                    # Auto-detect and install for all instances" 1>&2
    echo "  $0 -i 1               # Install only for instance 1" 1>&2
    echo "  $0 -i 1,2             # Install for instances 1 and 2" 1>&2
    echo "  $0 -u -i 2            # Uninstall from instance 2" 1>&2
    exit 1
}

show_version() {
    echo "ValgACE installer v${VERSION}"
    exit 0
}

# Detect system architecture
IS_MIPS=0
if echo "$(uname -m)" | grep -q "mips"; then
    IS_MIPS=1
fi

# Base paths
SRCDIR="$PWD"

# Get paths for a specific instance (0 = default/no suffix)
get_instance_paths() {
    local num=$1
    
    if [ "$num" -eq 0 ]; then
        # Default instance (no suffix)
        echo "KLIPPER_SERVICE=klipper"
        echo "MOONRAKER_SERVICE=moonraker"
        echo "KLIPPER_HOME=${HOME}/klipper"
        echo "KLIPPER_CONFIG_HOME=${HOME}/printer_data/config"
        echo "MOONRAKER_CONFIG_DIR=${HOME}/printer_data/config"
        echo "MOONRAKER_HOME=${HOME}/moonraker"
        echo "KLIPPER_ENV=${HOME}/klippy-env/bin"
    else
        # Numbered instance
        echo "KLIPPER_SERVICE=klipper-${num}"
        echo "MOONRAKER_SERVICE=moonraker-${num}"
        echo "KLIPPER_HOME=${HOME}/klipper-${num}"
        echo "KLIPPER_CONFIG_HOME=${HOME}/printer_data${num}/config"
        echo "MOONRAKER_CONFIG_DIR=${HOME}/printer_data${num}/config"
        echo "MOONRAKER_HOME=${HOME}/moonraker-${num}"
        echo "KLIPPER_ENV=${HOME}/klippy-env${num}/bin"
    fi
}

# Detect available instances
detect_instances() {
    local instances=""
    
    # Check default instance (no suffix)
    if [ -d "${HOME}/klipper" ] && [ -d "${HOME}/printer_data/config" ]; then
        instances="0"
    fi
    
    # Check numbered instances (1-9)
    for i in 1 2 3 4 5 6 7 8 9; do
        if [ -d "${HOME}/klipper-${i}" ] || [ -d "${HOME}/printer_data${i}" ]; then
            if [ -n "$instances" ]; then
                instances="${instances},${i}"
            else
                instances="${i}"
            fi
        fi
    done
    
    echo "$instances"
}

# Parse instance specification
parse_instances() {
    local spec=$1
    
    if [ "$spec" = "auto" ]; then
        detect_instances
    else
        # Convert "1,2,3" to validated list
        echo "$spec" | tr ',' '\n' | while read -r num; do
            if echo "$num" | grep -qE '^[0-9]+$'; then
                echo "$num"
            fi
        done | sort -u | tr '\n' ',' | sed 's/,$//'
    fi
}

# Verify instance exists
verify_instance() {
    local num=$1
    eval "$(get_instance_paths "$num")"
    
    local missing=0
    
    if [ ! -d "$KLIPPER_HOME/klippy/extras/" ]; then
        echo "[ERROR] Klipper installation not found: $KLIPPER_HOME"
        missing=1
    fi
    
    if [ ! -d "$KLIPPER_CONFIG_HOME/" ]; then
        echo "[ERROR] Config directory not found: $KLIPPER_CONFIG_HOME"
        missing=1
    fi
    
    if [ "$missing" -ne 0 ]; then
        return 1
    fi
    
    return 0
}

# Install for a specific instance
install_instance() {
    local num=$1
    eval "$(get_instance_paths "$num")"
    
    local instance_label
    if [ "$num" -eq 0 ]; then
        instance_label="default"
    else
        instance_label="instance-${num}"
    fi
    
    echo ""
    echo "=========================================="
    echo "Installing for ${instance_label}"
    echo "=========================================="
    
    # Verify paths
    if ! verify_instance "$num"; then
        echo "[SKIP] Instance ${instance_label} verification failed"
        return 1
    fi
    
    # Stop klipper
    echo -n "Stopping ${KLIPPER_SERVICE}... "
    if sudo systemctl stop "$KLIPPER_SERVICE" 2>/dev/null; then
        echo "[OK]"
    else
        echo "[WARNING] Service not running or not found"
    fi
    
    # Install requirements
    if [ -f "${SRCDIR}/requirements.txt" ] && [ -f "${KLIPPER_ENV}/pip3" ]; then
        echo -n "Installing requirements... "
        if "${KLIPPER_ENV}/pip3" install -r "${SRCDIR}/requirements.txt" >/dev/null 2>&1; then
            echo "[OK]"
        else
            echo "[FAILED]"
        fi
    fi
    
    # Link extensions
    echo -n "Linking ace.py... "
    if ln -sf "${SRCDIR}/extras/ace.py" "${KLIPPER_HOME}/klippy/extras/ace.py"; then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi
    
    echo -n "Linking temperature_ace.py... "
    if ln -sf "${SRCDIR}/extras/temperature_ace.py" "${KLIPPER_HOME}/klippy/extras/temperature_ace.py"; then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi
    
    # Link Moonraker component
    if [ -d "$MOONRAKER_HOME" ]; then
        local dest_dir="${MOONRAKER_HOME}/moonraker/components"
        mkdir -p "$dest_dir"
        
        echo -n "Linking Moonraker component... "
        if ln -sf "${SRCDIR}/moonraker/ace_status.py" "${dest_dir}/ace_status.py"; then
            echo "[OK]"
        else
            echo "[FAILED]"
        fi
        
        # Add ace_status to moonraker.conf
        if [ -f "${MOONRAKER_CONFIG_DIR}/moonraker.conf" ]; then
            if ! grep -q "^\[ace_status\]" "${MOONRAKER_CONFIG_DIR}/moonraker.conf" 2>/dev/null; then
                echo -n "Adding [ace_status] to moonraker.conf... "
                printf "\n[ace_status]\n" >> "${MOONRAKER_CONFIG_DIR}/moonraker.conf" && echo "[OK]" || echo "[FAILED]"
            else
                echo "[SKIP] [ace_status] already in moonraker.conf"
            fi
        fi
    fi
    
    # Copy config
    echo -n "Copying ace.cfg... "
    if [ ! -f "${KLIPPER_CONFIG_HOME}/ace.cfg" ]; then
        if cp "${SRCDIR}/ace.cfg" "${KLIPPER_CONFIG_HOME}/"; then
            echo "[OK]"
            echo "[INFO] Add [include ace.cfg] to your printer.cfg"
        else
            echo "[FAILED]"
        fi
    else
        echo "[SKIP] ace.cfg already exists"
    fi
    
    # Add update manager (only for default instance or if moonraker.conf exists)
    if [ -f "${MOONRAKER_CONFIG_DIR}/moonraker.conf" ]; then
        local updater_name="ValgACE"
        if [ "$num" -ne 0 ]; then
            updater_name="ValgACE${num}"
        fi
        
        if ! grep -q "\[update_manager ${updater_name}\]" "${MOONRAKER_CONFIG_DIR}/moonraker.conf" 2>/dev/null; then
            echo -n "Adding update manager... "
            cat << EOF >> "${MOONRAKER_CONFIG_DIR}/moonraker.conf"

[update_manager ${updater_name}]
type: git_repo
path: ${SRCDIR}
primary_branch: main
origin: https://github.com/agrloki/ValgACE.git
managed_services: ${KLIPPER_SERVICE}
EOF
            echo "[OK]"
        else
            echo "[SKIP] Update manager already configured"
        fi
    fi
    
    # Restart services
    if [ -d "$MOONRAKER_HOME" ]; then
        echo -n "Restarting ${MOONRAKER_SERVICE}... "
        if sudo systemctl restart "$MOONRAKER_SERVICE" 2>/dev/null; then
            echo "[OK]"
        else
            echo "[WARNING] Failed to restart moonraker"
        fi
    fi
    
    echo -n "Starting ${KLIPPER_SERVICE}... "
    if sudo systemctl start "$KLIPPER_SERVICE" 2>/dev/null; then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi
    
    echo "[SUCCESS] Installed for ${instance_label}"
    return 0
}

# Uninstall from instance
uninstall_instance() {
    local num=$1
    eval "$(get_instance_paths "$num")"
    
    local instance_label
    if [ "$num" -eq 0 ]; then
        instance_label="default"
    else
        instance_label="instance-${num}"
    fi
    
    echo ""
    echo "=========================================="
    echo "Uninstalling from ${instance_label}"
    echo "=========================================="
    
    # Stop klipper
    sudo systemctl stop "$KLIPPER_SERVICE" 2>/dev/null || true
    
    # Remove files
    local removed=0
    
    if [ -f "${KLIPPER_HOME}/klippy/extras/ace.py" ]; then
        rm -f "${KLIPPER_HOME}/klippy/extras/ace.py" && echo "[OK] Removed ace.py" && removed=1
    fi
    
    if [ -f "${KLIPPER_HOME}/klippy/extras/temperature_ace.py" ]; then
        rm -f "${KLIPPER_HOME}/klippy/extras/temperature_ace.py" && echo "[OK] Removed temperature_ace.py" && removed=1
    fi
    
    if [ -f "${MOONRAKER_HOME}/moonraker/components/ace_status.py" ]; then
        rm -f "${MOONRAKER_HOME}/moonraker/components/ace_status.py" && echo "[OK] Removed moonraker component" && removed=1
    fi
    
    if [ "$removed" -eq 0 ]; then
        echo "[SKIP] No ValgACE files found"
    fi
    
    # Start klipper
    sudo systemctl start "$KLIPPER_SERVICE" 2>/dev/null || true
    
    echo "[SUCCESS] Uninstalled from ${instance_label}"
}

# Main execution
main() {
    echo "ValgACE Multi-Instance Installer v${VERSION}"
    echo ""
    
    # Check if running as root (only for MIPS)
    if [ "$IS_MIPS" -ne 1 ] && [ "$EUID" -eq 0 ]; then
        echo "[ERROR] Do not run as root (except on MIPS systems)"
        exit 1
    fi
    
    # Get instances to process
    local instances
    instances=$(parse_instances "$INSTANCE_SPEC")
    
    if [ -z "$instances" ]; then
        echo "[ERROR] No Klipper instances found"
        echo "Searched for:"
        echo "  ${HOME}/klipper (default)"
        echo "  ${HOME}/klipper-1 through ${HOME}/klipper-9"
        echo ""
        echo "To specify manually: $0 -i 1"
        exit 1
    fi
    
    echo "Target instances: $(echo "$instances" | tr ',' ' ')"
    echo ""
    
    # Process each instance
    echo "$instances" | tr ',' '\n' | while read -r num; do
        if [ "$UNINSTALL" -eq 1 ]; then
            uninstall_instance "$num"
        else
            install_instance "$num"
        fi
    done
    
    echo ""
    echo "=========================================="
    echo "Operation completed"
    echo "=========================================="
    
    if [ "$UNINSTALL" -ne 1 ]; then
        echo ""
        echo "Next steps:"
        echo "1. Edit ${KLIPPER_CONFIG_HOME}/ace.cfg for each instance"
        echo "2. Add [include ace.cfg] to each printer.cfg"
        echo "3. Update serial port in ace.cfg for each instance"
        echo "4. Restart Klipper instances"
    fi
}

main
