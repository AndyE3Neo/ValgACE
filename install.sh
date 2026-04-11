#!/bin/sh

# Version
VERSION="2.2-interactive"

# Parse arguments
INSTANCE_SPEC="auto"
UNINSTALL=0
ALL_INSTANCES=0
INTERACTIVE=1

while getopts "i:auhv" arg; do
 case $arg in
 i) INSTANCE_SPEC="$OPTARG"; INTERACTIVE=0;;
 a) ALL_INSTANCES=1;;
 u) UNINSTALL=1;;
 h) usage ;;
 v) show_version ;;
 *) usage ;;
 esac
done

usage() {
 echo "Usage: $0 [-i instance] [-a] [-u] [-h] [-v]" 1>&2
 echo "Options:" 1>&2
 echo "  -i    Instance number(s): 1, 2 or 1,2 (non-interactive)" 1>&2
 echo "  -a    Install/Uninstall from ALL instances (non-interactive)" 1>&2
 echo "  -u    Uninstall ValgACE" 1>&2
 echo "  -h    Show this help" 1>&2
 echo "  -v    Show version" 1>&2
 echo "" 1>&2
 echo "Examples:" 1>&2
 echo "  $0                # Interactive mode - select instances" 1>&2
 echo "  $0 -a             # Auto mode - all instances" 1>&2
 echo "  $0 -i 1           # Install only for instance 1" 1>&2
 echo "  $0 -i 1,2        # Install for instances 1 and 2" 1>&2
 echo "  $0 -u -a          # Uninstall from all instances" 1>&2
 echo "  $0 -u -i 2        # Uninstall from instance 2" 1>&2
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
KLIPPER_ENV="${HOME}/klippy-env/bin"

# Arrays for storing detected instances
declare -a INSTANCE_NUMS
declare -a INSTANCE_NAMES
declare -a PRINTER_DATA_HOMES
declare -a KLIPPER_CONFIG_HOMES
declare -a MOONRAKER_CONFIG_DIRS
declare -a MOONRAKER_HOMES
declare -a KLIPPER_SERVICES
declare -a MOONRAKER_SERVICES

# Get paths for a specific instance
get_instance_paths() {
 local num=$1

 # Instance 0 = default (printer_data), Instance 1+ = printer_1_data, etc.
 if [ "$num" -eq 0 ]; then
  echo "INSTANCE_NUM=0"
  echo "INSTANCE_NAME=default"
  echo "PRINTER_DATA_HOME=${HOME}/printer_data"
  echo "KLIPPER_CONFIG_HOME=${HOME}/printer_data/config"
  echo "MOONRAKER_CONFIG_DIR=${HOME}/printer_data/config"
  # Try to find moonraker home - check multiple locations
  if [ -d "${HOME}/moonraker" ]; then
   echo "MOONRAKER_HOME=${HOME}/moonraker"
  elif [ -d "${HOME}/moonraker-0" ]; then
   echo "MOONRAKER_HOME=${HOME}/moonraker-0"
  elif [ -d "${HOME}/moonraker_0" ]; then
   echo "MOONRAKER_HOME=${HOME}/moonraker_0"
  else
   echo "MOONRAKER_HOME=${HOME}/moonraker"
  fi
 else
  echo "INSTANCE_NUM=${num}"
  echo "INSTANCE_NAME=printer_${num}"
  echo "PRINTER_DATA_HOME=${HOME}/printer_${num}_data"
  echo "KLIPPER_CONFIG_HOME=${HOME}/printer_${num}_data/config"
  echo "MOONRAKER_CONFIG_DIR=${HOME}/printer_${num}_data/config"
  # Check for separate moonraker home for this instance
  if [ -d "${HOME}/moonraker-${num}" ]; then
   echo "MOONRAKER_HOME=${HOME}/moonraker-${num}"
  elif [ -d "${HOME}/moonraker_${num}" ]; then
   echo "MOONRAKER_HOME=${HOME}/moonraker_${num}"
  elif [ -d "${HOME}/moonraker" ]; then
   echo "MOONRAKER_HOME=${HOME}/moonraker"
  else
   echo "MOONRAKER_HOME=${HOME}/moonraker"
  fi
 fi
 echo "KLIPPER_HOME=${KLIPPER_HOME}"
 echo "KLIPPER_ENV=${KLIPPER_ENV}"
}

# Detect available instances and populate arrays
detect_instances() {
 local count=0

 # Check default instance (printer_data)
 if [ -d "${HOME}/printer_data/config" ] && [ -f "${HOME}/printer_data/config/moonraker.conf" ]; then
  INSTANCE_NUMS[$count]=0
  INSTANCE_NAMES[$count]="default"
  PRINTER_DATA_HOMES[$count]="${HOME}/printer_data"
  KLIPPER_CONFIG_HOMES[$count]="${HOME}/printer_data/config"
  MOONRAKER_CONFIG_DIRS[$count]="${HOME}/printer_data/config"

  # Detect moonraker home
  if [ -d "${HOME}/moonraker" ]; then
   MOONRAKER_HOMES[$count]="${HOME}/moonraker"
  elif [ -d "${HOME}/moonraker-0" ]; then
   MOONRAKER_HOMES[$count]="${HOME}/moonraker-0"
  elif [ -d "${HOME}/moonraker_0" ]; then
   MOONRAKER_HOMES[$count]="${HOME}/moonraker_0"
  else
   MOONRAKER_HOMES[$count]="${HOME}/moonraker"
  fi

  # Detect services
  KLIPPER_SERVICES[$count]="klipper"
  if systemctl list-unit-files 2>/dev/null | grep -q "^moonraker-0.service"; then
   MOONRAKER_SERVICES[$count]="moonraker-0"
  elif systemctl list-unit-files 2>/dev/null | grep -q "^moonraker_0.service"; then
   MOONRAKER_SERVICES[$count]="moonraker_0"
  else
   MOONRAKER_SERVICES[$count]="moonraker"
  fi

  count=$((count + 1))
 fi

 # Check numbered instances (printer_1_data, printer_2_data, etc.)
 for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  local data_dir="${HOME}/printer_${i}_data"
  local config_dir="${data_dir}/config"
  local moonraker_conf="${config_dir}/moonraker.conf"

  if [ -d "$config_dir" ] && [ -f "$moonraker_conf" ]; then
   INSTANCE_NUMS[$count]=$i
   INSTANCE_NAMES[$count]="printer_${i}"
   PRINTER_DATA_HOMES[$count]="$data_dir"
   KLIPPER_CONFIG_HOMES[$count]="$config_dir"
   MOONRAKER_CONFIG_DIRS[$count]="$config_dir"

   # Detect moonraker home - check for separate first
   if [ -d "${HOME}/moonraker-${i}" ]; then
    MOONRAKER_HOMES[$count]="${HOME}/moonraker-${i}"
   elif [ -d "${HOME}/moonraker_${i}" ]; then
    MOONRAKER_HOMES[$count]="${HOME}/moonraker_${i}"
   elif [ -d "${HOME}/moonraker" ]; then
    MOONRAKER_HOMES[$count]="${HOME}/moonraker"
   else
    MOONRAKER_HOMES[$count]="${HOME}/moonraker"
   fi

   # Detect klipper service
   if systemctl list-unit-files 2>/dev/null | grep -q "^klipper-${i}.service"; then
    KLIPPER_SERVICES[$count]="klipper-${i}"
   elif systemctl list-unit-files 2>/dev/null | grep -q "^klipper_${i}.service"; then
    KLIPPER_SERVICES[$count]="klipper_${i}"
   elif systemctl list-units --full -all 2>/dev/null | grep -q "klipper@${i}"; then
    KLIPPER_SERVICES[$count]="klipper@${i}"
   else
    KLIPPER_SERVICES[$count]="klipper-${i}"
   fi

   # Detect moonraker service
   if systemctl list-unit-files 2>/dev/null | grep -q "^moonraker-${i}.service"; then
    MOONRAKER_SERVICES[$count]="moonraker-${i}"
   elif systemctl list-unit-files 2>/dev/null | grep -q "^moonraker_${i}.service"; then
    MOONRAKER_SERVICES[$count]="moonraker_${i}"
   elif systemctl list-units --full -all 2>/dev/null | grep -q "moonraker@${i}"; then
    MOONRAKER_SERVICES[$count]="moonraker@${i}"
   else
    MOONRAKER_SERVICES[$count]="moonraker-${i}"
   fi

   count=$((count + 1))
  fi
 done

 return $count
}

# Display detected instances in a nice format
show_instances_table() {
 local total=$1

 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║                    DETECTED KLIPPER/MOONRAKER INSTANCES                      ║"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 if [ $total -eq 0 ]; then
  echo "  [ERROR] No instances found!"
  echo ""
  echo "  Searched for:"
  echo "    ${HOME}/printer_data/config"
  echo "    ${HOME}/printer_1_data/config"
  echo "    ${HOME}/printer_2_data/config, etc."
  echo ""
  return 1
 fi

 printf "  %-4s %-12s %-25s %-20s\n" "Num" "Name" "Config Dir" "Moonraker Home"
 echo "  ─────────────────────────────────────────────────────────────────────────"

 local idx=0
 while [ $idx -lt $total ]; do
  local num_display="${INSTANCE_NUMS[$idx]}"
  [ "$num_display" -eq 0 ] && num_display="0 (default)"
  printf "  [%d]  %-12s %-25s %-20s\n" "$((idx+1))" "${INSTANCE_NAMES[$idx]}" "${MOONRAKER_CONFIG_DIRS[$idx]}" "${MOONRAKER_HOMES[$idx]}"
  idx=$((idx + 1))
 done

 echo ""
 echo "  Total instances found: $total"
 echo ""
 return 0
}

# Interactive instance selection
select_instances_interactive() {
 local total=$1

 if [ "$ALL_INSTANCES" -eq 1 ]; then
  echo "  [AUTO] Selecting ALL instances"
  SELECTED_INDICES=""
  local idx=0
  while [ $idx -lt $total ]; do
   if [ -z "$SELECTED_INDICES" ]; then
    SELECTED_INDICES="$idx"
   else
    SELECTED_INDICES="$SELECTED_INDICES $idx"
   fi
   idx=$((idx + 1))
  done
  return
 fi

 echo "═══════════════════════════════════════════════════════════════════════════════"
 echo ""
 echo "  Select instances to $([ "$UNINSTALL" -eq 1 ] && echo "UNINSTALL from" || echo "INSTALL to"):"
 echo ""
 echo "    • Enter numbers separated by spaces (e.g., 1 2 3)"
 echo "    • Enter 'all' for all instances"
 echo "    • Press ENTER for instance 1 only"
 echo ""
 printf "  Your choice: "
 read -r choice
 echo ""

 if [ -z "$choice" ]; then
  # Default to first instance
  SELECTED_INDICES="0"
  echo "  [OK] Selected instance 1 (default)"
 elif [ "$choice" = "all" ] || [ "$choice" = "ALL" ]; then
  SELECTED_INDICES=""
  local idx=0
  while [ $idx -lt $total ]; do
   if [ -z "$SELECTED_INDICES" ]; then
    SELECTED_INDICES="$idx"
   else
    SELECTED_INDICES="$SELECTED_INDICES $idx"
   fi
   idx=$((idx + 1))
  done
  echo "  [OK] Selected ALL instances"
 else
  # Validate and convert to 0-based indices
  SELECTED_INDICES=""
  for num in $choice; do
   if echo "$num" | grep -qE '^[0-9]+$'; then
    local idx=$((num-1))
    if [ $idx -ge 0 ] && [ $idx -lt $total ]; then
     if [ -z "$SELECTED_INDICES" ]; then
      SELECTED_INDICES="$idx"
     else
      SELECTED_INDICES="$SELECTED_INDICES $idx"
     fi
    else
     echo "  [WARNING] Invalid instance number: $num (skipping)"
    fi
   else
    echo "  [WARNING] Invalid input: $num (skipping)"
   fi
  done

  if [ -z "$SELECTED_INDICES" ]; then
   echo "  [ERROR] No valid instances selected. Exiting."
   exit 1
  fi
 fi

 # Show selection summary
 echo ""
 echo "  Selected:"
 for idx in $SELECTED_INDICES; do
  echo "    • ${INSTANCE_NAMES[$idx]} (Config: ${MOONRAKER_CONFIG_DIRS[$idx]})"
 done
 echo ""
}

# Parse instance specification (for non-interactive mode)
parse_instances() {
 local spec=$1
 local total=$2

 if [ "$spec" = "auto" ]; then
  # Auto-detect - use all instances
  SELECTED_INDICES=""
  local idx=0
  while [ $idx -lt $total ]; do
   if [ -z "$SELECTED_INDICES" ]; then
    SELECTED_INDICES="$idx"
   else
    SELECTED_INDICES="$SELECTED_INDICES $idx"
   fi
   idx=$((idx + 1))
  done
 else
  # Parse comma or space separated list
  SELECTED_INDICES=""
  local items=$(echo "$spec" | tr ',' ' ')
  for item in $items; do
   if echo "$item" | grep -qE '^[0-9]+$'; then
    # Convert instance number to array index
    local found=0
    local idx=0
    while [ $idx -lt $total ]; do
     if [ "${INSTANCE_NUMS[$idx]}" -eq "$item" ]; then
      found=1
      if [ -z "$SELECTED_INDICES" ]; then
       SELECTED_INDICES="$idx"
      else
       SELECTED_INDICES="$SELECTED_INDICES $idx"
      fi
      break
     fi
     idx=$((idx + 1))
    done
    if [ $found -eq 0 ]; then
     echo "  [WARNING] Instance $item not found (skipping)"
    fi
   fi
  done
 fi
}

# Verify shared installation
verify_shared_install() {
 local missing=0

 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║                      VERIFYING SHARED INSTALLATION                           ║"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 if [ ! -d "$KLIPPER_HOME/klippy/extras/" ]; then
  echo "  [ERROR] Klipper installation not found: $KLIPPER_HOME"
  missing=1
 fi

 if [ ! -d "$KLIPPER_ENV" ] && [ ! -f "$KLIPPER_ENV/python" ] && [ ! -f "$KLIPPER_ENV/python3" ]; then
  if ! command -v python3 >/dev/null 2>&1; then
   echo "  [ERROR] Klipper virtual environment not found: $KLIPPER_ENV"
   missing=1
  fi
 fi

 if [ $missing -ne 0 ]; then
  exit 1
 fi

 echo "  [OK] Klipper: $KLIPPER_HOME"
 echo "  [OK] Python env: $KLIPPER_ENV"
 echo ""
}

# Verify specific instance
verify_instance() {
 local idx=$1
 local num="${INSTANCE_NUMS[$idx]}"

 echo ""
 echo "  [${INSTANCE_NAMES[$idx]}] Verifying..."

 if [ ! -d "${KLIPPER_CONFIG_HOMES[$idx]}" ]; then
  echo "    [ERROR] Config directory not found: ${KLIPPER_CONFIG_HOMES[$idx]}"
  return 1
 fi

 if [ ! -f "${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf" ]; then
  echo "    [ERROR] moonraker.conf not found: ${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf"
  return 1
 fi

 if [ ! -d "${MOONRAKER_HOMES[$idx]}" ]; then
  echo "    [WARNING] Moonraker home not found: ${MOONRAKER_HOMES[$idx]}"
  echo "    [INFO] Will try to use shared moonraker components"
 fi

 echo "    [OK] Config: ${KLIPPER_CONFIG_HOMES[$idx]}"
 echo "    [OK] Moonraker: ${MOONRAKER_HOMES[$idx]}"
 return 0
}

# Install shared components (run once)
install_shared() {
 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║                      INSTALLING SHARED COMPONENTS                            ║"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 # Install requirements
 if [ -f "${SRCDIR}/requirements.txt" ]; then
  echo -n "  Installing Python requirements... "
  if "${KLIPPER_ENV}/pip3" install -r "${SRCDIR}/requirements.txt" >/dev/null 2>&1; then
   echo "[OK]"
  else
   echo "[FAILED]"
  fi
 fi

 # Link Klipper extensions (shared)
 echo -n "  Linking ace.py to Klipper... "
 if ln -sf "${SRCDIR}/extras/ace.py" "${KLIPPER_HOME}/klippy/extras/ace.py"; then
  echo "[OK]"
 else
  echo "[FAILED]"
 fi

 echo -n "  Linking temperature_ace.py to Klipper... "
 if ln -sf "${SRCDIR}/extras/temperature_ace.py" "${KLIPPER_HOME}/klippy/extras/temperature_ace.py"; then
  echo "[OK]"
 else
  echo "[FAILED]"
 fi
}

# Install Moonraker component for specific instance
install_moonraker_component() {
 local idx=$1
 local moonraker_home="${MOONRAKER_HOMES[$idx]}"

 echo -n "  Linking Moonraker component... "

 # Ensure destination directory exists
 local dest_dir="${moonraker_home}/moonraker/components"
 if mkdir -p "${dest_dir}" 2>/dev/null; then
  if ln -sf "${SRCDIR}/moonraker/ace_status.py" "${dest_dir}/ace_status.py"; then
   echo "[OK]"
   return 0
  else
   echo "[FAILED]"
   return 1
  fi
 else
  echo "[FAILED] (cannot create directory)"
  return 1
 fi
}

# Install for a specific instance
install_instance() {
 local idx=$1
 local num="${INSTANCE_NUMS[$idx]}"

 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║  Configuring: ${INSTANCE_NAMES[$idx]}"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 # Verify instance
 if ! verify_instance "$idx"; then
  echo "  [SKIP] Instance verification failed"
  return 1
 fi

 # Install Moonraker component (per-instance for separate moonraker homes)
 install_moonraker_component "$idx"

 # Copy config file (per-instance)
 echo -n "  Copying ace.cfg... "
 if [ ! -f "${KLIPPER_CONFIG_HOMES[$idx]}/ace.cfg" ]; then
  if cp "${SRCDIR}/ace.cfg" "${KLIPPER_CONFIG_HOMES[$idx]}/"; then
   echo "[OK]"
   echo ""
   echo "  [IMPORTANT] Edit ${KLIPPER_CONFIG_HOMES[$idx]}/ace.cfg"
   echo "  [IMPORTANT] Set unique serial port for this instance!"
   echo ""
  else
   echo "[FAILED]"
  fi
 else
  echo "[SKIP] (already exists)"
 fi

 # Add ace_status to moonraker.conf (per-instance)
 if ! grep -q "^\[ace_status\]" "${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf" 2>/dev/null; then
  echo -n "  Adding [ace_status] to moonraker.conf... "
  printf "\n[ace_status]\n" >> "${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf" && echo "[OK]" || echo "[FAILED]"
 else
  echo "  [ace_status] already in moonraker.conf [SKIP]"
 fi

 # Add update manager (per-instance, with unique name)
 local updater_name="ValgACE"
 if [ "$num" -ne 0 ]; then
  updater_name="ValgACE_${INSTANCE_NAMES[$idx]}"
 fi

 if ! grep -q "\[update_manager ${updater_name}\]" "${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf" 2>/dev/null; then
  echo -n "  Adding update manager [${updater_name}]... "
  cat << EOF >> "${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf"

[update_manager ${updater_name}]
type: git_repo
path: ${SRCDIR}
primary_branch: main
origin: https://github.com/AndyE3Neo/ValgACE.git
managed_services: klipper
EOF
  echo "[OK]"
 else
  echo "  Update manager [${updater_name}] already configured [SKIP]"
 fi

 echo ""
 echo "  [SUCCESS] Configured ${INSTANCE_NAMES[$idx]}"
 return 0
}

# Uninstall from instance
uninstall_instance() {
 local idx=$1
 local num="${INSTANCE_NUMS[$idx]}"

 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║  Uninstalling from: ${INSTANCE_NAMES[$idx]}"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 # Remove ace.cfg
 if [ -f "${KLIPPER_CONFIG_HOMES[$idx]}/ace.cfg" ]; then
  rm -f "${KLIPPER_CONFIG_HOMES[$idx]}/ace.cfg" && echo "  [OK] Removed ace.cfg"
 else
  echo "  [SKIP] ace.cfg not found"
 fi

 # Remove Moonraker component (only if separate moonraker home)
 local moonraker_home="${MOONRAKER_HOMES[$idx]}"
 local component_file="${moonraker_home}/moonraker/components/ace_status.py"
 if [ -L "$component_file" ] || [ -f "$component_file" ]; then
  rm -f "$component_file" && echo "  [OK] Removed Moonraker component"
 fi

 # Remove ace_status from moonraker.conf
 local config_file="${MOONRAKER_CONFIG_DIRS[$idx]}/moonraker.conf"
 if grep -q "^\[ace_status\]" "$config_file" 2>/dev/null; then
  # Create backup
  cp "$config_file" "${config_file}.bak"
  # Remove the section
  sed -i '/^\[ace_status\]/d' "$config_file" 2>/dev/null ||    grep -v "^\[ace_status\]" "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
  echo "  [OK] Removed [ace_status] from moonraker.conf"
 fi

 # Remove update manager section
 local updater_name="ValgACE"
 if [ "$num" -ne 0 ]; then
  updater_name="ValgACE_${INSTANCE_NAMES[$idx]}"
 fi
 if grep -q "\[update_manager ${updater_name}\]" "$config_file" 2>/dev/null; then
  # This is more complex - need to remove section with its content
  # Simple approach: backup and notify user
  echo "  [INFO] Update manager [${updater_name}] section found in moonraker.conf"
  echo "  [INFO] Please remove it manually or edit ${config_file}"
 fi

 echo ""
 echo "  [SUCCESS] Uninstalled from ${INSTANCE_NAMES[$idx]}"
}

# Uninstall shared components
uninstall_shared() {
 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║                      UNINSTALLING SHARED COMPONENTS                          ║"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 local removed=0

 if [ -f "${KLIPPER_HOME}/klippy/extras/ace.py" ]; then
  rm -f "${KLIPPER_HOME}/klippy/extras/ace.py" && echo "  [OK] Removed ace.py" && removed=1
 fi

 if [ -f "${KLIPPER_HOME}/klippy/extras/temperature_ace.py" ]; then
  rm -f "${KLIPPER_HOME}/klippy/extras/temperature_ace.py" && echo "  [OK] Removed temperature_ace.py" && removed=1
 fi

 if [ "$removed" -eq 0 ]; then
  echo "  [SKIP] No shared components found"
 fi

 echo ""
 echo "  [NOTE] Config files in printer data folders were preserved."
 echo "  [NOTE] Run with -u and specific instances to remove those."
}

# Restart services for an instance
restart_instance_services() {
 local idx=$1

 echo ""
 echo "  Restarting services for ${INSTANCE_NAMES[$idx]}..."

 echo -n "    Stopping Klipper (${KLIPPER_SERVICES[$idx]})... "
 if sudo systemctl stop "${KLIPPER_SERVICES[$idx]}" 2>/dev/null; then
  echo "[OK]"
 else
  echo "[WARNING]"
 fi

 echo -n "    Restarting Moonraker (${MOONRAKER_SERVICES[$idx]})... "
 if sudo systemctl restart "${MOONRAKER_SERVICES[$idx]}" 2>/dev/null; then
  echo "[OK]"
 else
  echo "[WARNING]"
 fi

 echo -n "    Starting Klipper (${KLIPPER_SERVICES[$idx]})... "
 if sudo systemctl start "${KLIPPER_SERVICES[$idx]}" 2>/dev/null; then
  echo "[OK]"
 else
  echo "[WARNING]"
 fi
}

# Main execution
main() {
 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║           ValgACE Multi-Instance Installer v${VERSION}"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 # Check root (only for non-MIPS)
 if [ "$IS_MIPS" -ne 1 ] && [ "$EUID" -eq 0 ]; then
  echo "  [ERROR] Do not run as root"
  exit 1
 fi

 # Detect all instances
 detect_instances
 TOTAL_INSTANCES=$?

 # Show detected instances
 if ! show_instances_table $TOTAL_INSTANCES; then
  exit 1
 fi

 # Get instances to process
 if [ "$INTERACTIVE" -eq 1 ] && [ "$ALL_INSTANCES" -eq 0 ] && [ "$INSTANCE_SPEC" = "auto" ]; then
  # Interactive mode
  select_instances_interactive $TOTAL_INSTANCES
 else
  # Non-interactive mode
  parse_instances "$INSTANCE_SPEC" $TOTAL_INSTANCES
 fi

 if [ -z "$SELECTED_INDICES" ]; then
  echo "  [ERROR] No instances selected"
  exit 1
 fi

 # Show final selection
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║                         FINAL SELECTION                                      ║"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""
 echo "  Will $([ "$UNINSTALL" -eq 1 ] && echo "UNINSTALL from" || echo "INSTALL to"):"
 for idx in $SELECTED_INDICES; do
  echo "    • ${INSTANCE_NAMES[$idx]}"
 done
 echo ""

 # Verify shared installation
 verify_shared_install

 if [ "$UNINSTALL" -eq 1 ]; then
  # Uninstall mode
  uninstall_shared

  for idx in $SELECTED_INDICES; do
   uninstall_instance "$idx"
  done
 else
  # Install mode
  install_shared

  for idx in $SELECTED_INDICES; do
   install_instance "$idx"
  done

  # Restart services for each instance
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════════════════╗"
  echo "║                      RESTARTING SERVICES                                       ║"
  echo "╚══════════════════════════════════════════════════════════════════════════════╝"
  for idx in $SELECTED_INDICES; do
   restart_instance_services "$idx"
  done
 fi

 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════════════╗"
 echo "║                     OPERATION COMPLETED                                      ║"
 echo "╚══════════════════════════════════════════════════════════════════════════════╝"
 echo ""

 if [ "$UNINSTALL" -ne 1 ]; then
  echo "  IMPORTANT POST-INSTALL STEPS:"
  echo ""
  echo "  For each configured instance:"
  echo "  1. Edit ~/printer_X_data/config/ace.cfg"
  echo "  2. Set unique serial port for each ACE device:"
  echo "     Instance 1: serial: /dev/serial/by-id/usb-1a86_USB_Serial_XXX"
  echo "     Instance 2: serial: /dev/serial/by-id/usb-1a86_USB_Serial_YYY"
  echo "  3. Add [include ace.cfg] to each printer.cfg"
  echo "  4. Restart Klipper for that instance"
  echo ""
 fi
}

main
