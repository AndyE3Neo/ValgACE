#!/bin/sh

# Version
VERSION="2.1"

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
    echo "  -i <num>    Instance number(s): 1, 2 or 1,2 (default: auto-detect)" 1>&2
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

# Base paths (shared)
SRCDIR="$PWD"
KLIPPER_HOME="${HOME}/klipper"
MOONRAKER_HOME="${HOME}/moonraker"
KLIPPER_ENV="${HOME}/klippy-env/bin"

# Get paths for a specific instance
get_instance_paths() {
    local num=$1
    
    # Instance 0 = default (printer_data), Instance 1+ = printer_1_data, printer_2_data, etc.
    if [ "$num" -eq 0 ]; then
        echo "INSTANCE_NUM=0"
        echo "INSTANCE_NAME=default"
        echo "PRINTER_DATA_HOME=${HOME}/printer_data"
        echo "KLIPPER_CONFIG_HOME=${HOME}/printer_data/config"
        echo "MOONRAKER_CONFIG_DIR=${HOME}/printer_data/config"
    else
        echo "INSTANCE_NUM=${num}"
        echo "INSTANCE_NAME=printer_${num}"
        echo "PRINTER_DATA_HOME=${HOME}/printer_${num}_data"
        echo "KLIPPER_CONFIG_HOME=${HOME}/printer_${num}_data/config"
        echo "MOONRAKER_CONFIG_DIR=${HOME}/printer_${num}_data/config"
    fi
    
    # Shared paths
    echo "KLIPPER_HOME=${KLIPPER_HOME}"
    echo "MOONRAKER_HOME=${MOONRAKER_HOME}"
    echo "KLIPPER_ENV=${KLIPPER_ENV}"
}

# Detect available instances
detect_instances() {
    local instances=""
    
    # Check default instance (printer_data)
    if [ -d "${HOME}/printer_data/config" ]; then
        instances="0"
    fi
    
    # Check numbered instances (printer_1_data, printer_2_data, etc.)
    for i in 1 2 3 4 5 6 7 8 9; do
        if [ -d "${HOME}/printer_${i}_data/config" ]; then
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
        # Validate and clean input
        echo "$spec" | tr ',' '\n' | grep -E '^[0-9]+$' | sort -u | tr '\n' ',' | sed 's/,$//'
    fi
}

# Verify shared installation
verify_shared_install() {
    local missing=0
    
    if [ ! -d "$KLIPPER_HOME/klippy/extras/" ]; then
        echo "[ERROR] Klipper installation not found: $KLIPPER_HOME"
        missing=1
    fi
    
    if [ ! -d "$MOONRAKER_HOME/moonraker/" ]; then
        echo "[ERROR] Moonraker installation not found: $MOONRAKER_HOME"
        missing=1
    fi
    
    if [ ! -f "${KLIPPER_ENV}/python" ] && [ ! -f "${KLIPPER_ENV}/python3" ]; then
        echo "[ERROR] Klipper virtual environment not found: $KLIPPER_ENV"
        missing=1
    fi
    
    if [ $missing -ne 0 ]; then
        exit 1
    fi
    
    echo "[OK] Shared Klipper/Moonraker installation found"
}

# Verify specific instance
verify_instance() {
    local num=$1
    eval "$(get_instance_paths "$num")"
    
    if [ ! -d "$KLIPPER_CONFIG_HOME" ]; then
        echo "[ERROR] Config directory not found: $KLIPPER_CONFIG_HOME"
        return 1
    fi
    
    if [ ! -f "${MOONRAKER_CONFIG_DIR}/moonraker.conf" ]; then
        echo "[ERROR] moonraker.conf not found: ${MOONRAKER_CONFIG_DIR}/moonraker.conf"
        return 1
    fi
    
    return 0
}

# Install shared components (run once)
install_shared() {
    echo ""
    echo "=========================================="
    echo "Installing shared components"
    echo "=========================================="
    
    # Install requirements
    if [ -f "${SRCDIR}/requirements.txt" ]; then
        echo -n "Installing Python requirements... "
        if "${KLIPPER_ENV}/pip3" install -r "${SRCDIR}/requirements.txt" >/dev/null 2>&1; then
            echo "[OK]"
        else
            echo "[FAILED]"
        fi
    fi
    
    # Link Klipper extensions (shared)
    echo -n "Linking ace.py to Klipper... "
    if ln -sf "${SRCDIR}/extras/ace.py" "${KLIPPER_HOME}/klippy/extras/ace.py"; then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi
    
    echo -n "Linking temperature_ace.py to Klipper... "
    if ln -sf "${SRCDIR}/extras/temperature_ace.py" "${KLIPPER_HOME}/klippy/extras/temperature_ace.py"; then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi
    
    # Link Moonraker component (shared)
    local dest_dir="${MOONRAKER_HOME}/moonraker/components"
    mkdir -p "$dest_dir"
    
    echo -n "Linking Moonraker component... "
    if ln -sf "${SRCDIR}/moonraker/ace_status.py" "${dest_dir}/ace_status.py"; then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi
}

# Install for a specific instance
install_instance() {
    local num=$1
    eval "$(get_instance_paths "$num")"
    
    echo ""
    echo "=========================================="
    echo "Configuring instance: ${INSTANCE_NAME}"
    echo "Data directory: ${PRINTER_DATA_HOME}"
    echo "=========================================="
    
    # Verify instance
    if ! verify_instance "$num"; then
        echo "[SKIP] Instance ${INSTANCE_NAME} verification failed"
        return 1
    fi
    
    # Copy config file (per-instance)
    echo -n "Copying ace.cfg... "
    if [ ! -f "${KLIPPER_CONFIG_HOME}/ace.cfg" ]; then
        if cp "${SRCDIR}/ace.cfg" "${KLIPPER_CONFIG_HOME}/"; then
            echo "[OK]"
            echo "[INFO] Edit ${KLIPPER_CONFIG_HOME}/ace.cfg and set unique serial port"
            echo "[INFO] Add [include ace.cfg] to your printer.cfg for this instance"
        else
            echo "[FAILED]"
        fi
    else
        echo "[SKIP] ace.cfg already exists"
    fi
    
    # Add ace_status to moonraker.conf (per-instance)
    if ! grep -q "^\[ace_status\]" "${MOONRAKER_CONFIG_DIR}/moonraker.conf" 2>/dev/null; then
        echo -n "Adding [ace_status] to moonraker.conf... "
        printf "\n[ace_status]\n" >> "${MOONRAKER_CONFIG_DIR}/moonraker.conf" && echo "[OK]" || echo "[FAILED]"
    else
        echo "[SKIP] [ace_status] already in moonraker.conf"
    fi
    
    # Add update manager (per-instance, with unique name)
    local updater_name="ValgACE"
    if [ "$num" -ne 0 ]; then
        updater_name="ValgACE_${INSTANCE_NAME}"
    fi
    
    if ! grep -q "\[update_manager ${updater_name}\]" "${MOONRAKER_CONFIG_DIR}/moonraker.conf" 2>/dev/null; then
        echo -n "Adding update manager... "
        cat << EOF >> "${MOONRAKER_CONFIG_DIR}/moonraker.conf"

[update_manager ${updater_name}]
type: git_repo
path: ${SRCDIR}
primary_branch: main
origin: https://github.com/agrloki/ValgACE.git
managed_services: klipper
EOF
        echo "[OK]"
    else
        echo "[SKIP] Update manager already configured"
    fi
    
    echo "[SUCCESS] Configured ${INSTANCE_NAME}"
    return 0
}

# Uninstall from instance (removes config only)
uninstall_instance() {
    local num=$1
    eval "$(get_instance_paths "$num")"
    
    echo ""
    echo "=========================================="
    echo "Uninstalling from instance: ${INSTANCE_NAME}"
    echo "=========================================="
    
    # Remove ace.cfg
    if [ -f "${KLIPPER_CONFIG_HOME}/ace.cfg" ]; then
        rm -f "${KLIPPER_CONFIG_HOME}/ace.cfg" && echo "[OK] Removed ace.cfg"
    else
        echo "[SKIP] ace.cfg not found"
    fi
    
    # Note: We don't remove shared components in per-instance uninstall
    # Use -u with no -i to remove shared components
    
    echo "[SUCCESS] Uninstalled from ${INSTANCE_NAME}"
}

# Uninstall shared components
uninstall_shared() {
    echo ""
    echo "=========================================="
    echo "Uninstalling shared components"
    echo "=========================================="
    
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
        echo "[SKIP] No shared components found"
    fi
    
    echo "Note: Config files in printer_data folders were not removed."
    echo "Delete ace.cfg manually from each instance if needed."
}

# Restart services
restart_services() {
    echo ""
    echo "=========================================="
    echo "Restarting services"
    echo "=========================================="
    
    echo -n "Restarting Moonraker... "
    if sudo systemctl restart moonraker 2>/dev/null; then
        echo "[OK]"
    else
        echo "[WARNING] Failed to restart moonraker"
    fi
    
    echo -n "Restarting Klipper... "
    if sudo systemctl restart klipper 2>/dev/null; then
        echo "[OK]"
    else
        echo "[WARNING] Failed to restart klipper"
    fi
}

# Main execution
main() {
    echo "ValgACE Multi-Instance Installer v${VERSION}"
    echo "Setup: Shared Klipper + Multiple Data Folders"
    echo ""
    
    # Check root (only for non-MIPS)
    if [ "$IS_MIPS" -ne 1 ] && [ "$EUID" -eq 0 ]; then
        echo "[ERROR] Do not run as root"
        exit 1
    fi
    
    # Get instances to process
    local instances
    instances=$(parse_instances "$INSTANCE_SPEC")
    
    if [ -z "$instances" ]; then
        echo "[ERROR] No printer data folders found"
        echo "Searched for:"
        echo "  ${HOME}/printer_data/config"
        echo "  ${HOME}/printer_1_data/config"
        echo "  ${HOME}/printer_2_data/config, etc."
        echo ""
        echo "To specify manually: $0 -i 1"
        exit 1
    fi
    
    echo "Detected instances: $(echo "$instances" | tr ',' ' ')"
    echo "Shared paths:"
    echo "  Klipper: ${KLIPPER_HOME}"
    echo "  Moonraker: ${MOONRAKER_HOME}"
    echo "  Python env: ${KLIPPER_ENV}"
    echo ""
    
    # Verify shared installation first
    verify_shared_install
    
    if [ "$UNINSTALL" -eq 1 ]; then
        # Uninstall mode
        if [ "$INSTANCE_SPEC" = "auto" ] && [ "$instances" = "$(detect_instances)" ]; then
            # No specific instance specified - uninstall everything
            uninstall_shared
        else
            # Uninstall from specific instances
            echo "$instances" | tr ',' '\n' | while read -r num; do
                uninstall_instance "$num"
            done
            echo ""
            echo "To remove shared components, run: $0 -u (without -i)"
        fi
    else
        # Install mode
        install_shared
        
        echo "$instances" | tr ',' '\n' | while read -r num; do
            install_instance "$num"
        done
        
        restart_services
    fi
    
    echo ""
    echo "=========================================="
    echo "Operation completed"
    echo "=========================================="
    
    if [ "$UNINSTALL" -ne 1 ]; then
        echo ""
        echo "IMPORTANT: Configure each instance separately!"
        echo ""
        echo "For each printer instance:"
        echo "1. Edit ~/printer_X_data/config/ace.cfg"
        echo "2. Set unique serial port for each ACE device:"
        echo "   instance 1: serial: /dev/serial/by-id/usb-1a86_USB_Serial_XXX"
        echo "   instance 2: serial: /dev/serial/by-id/usb-1a86_USB_Serial_YYY"
        echo "3. Add [include ace.cfg] to each printer.cfg"
        echo "4. Restart Klipper"
    fi
}

main
