#!/bin/bash

#======================================
# BASH DATA ANALYZER - MAIN SCRIPT
#======================================

# Verificar dependencias
command -v whiptail >/dev/null 2>&1 || { echo >&2 "whiptail is not installed. Aborting."; exit 1; }

# Definir rutas base
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
functions_dir="$script_dir/functions"
output_dir="$script_dir/output"
mkdir -p "$functions_dir" "$output_dir"

# Entrada: directorio con archivos CSV/TSV
directory=$(whiptail --inputbox "Enter directory path with CSV/TSV files:" 10 70 --title "BASH DATA ANALYZER" 3>&1 1>&2 2>&3)

# Validar ruta ingresada
if [ -z "$directory" ]; then
    whiptail --title "Error" --msgbox "Directory path cannot be empty. Please enter a valid path." 8 70
    exit 1
elif [ ! -d "$directory" ]; then
    whiptail --title "Error" --msgbox "Directory not found. Please check the path and try again." 8 70
    exit 1
fi

# Guardar ruta para acceso global
echo "$directory" > "$functions_dir/directory.txt"
echo "" > "$output_dir/output.txt"

# Menú interactivo
display_menu() {
  while true; do
    choice=$(whiptail --title "BASH DATA ANALYZER" --menu "Choose an option:" 20 80 10 \
    "0" "File Scan" \
    "1" "Search & filter" \
    "2" "Exit" \
    3>&1 1>&2 2>&3)

    # Salir si no hay selección
    if [ -z "$choice" ]; then
        break
    fi

    case "$choice" in
        0) bash "$functions_dir/file-scan.sh" ;;
        1) bash "$functions_dir/search.sh" ;;
        2) whiptail --title "Exit" --msgbox "Session Ended" 10 50; break ;;
        *) break ;;
    esac
  done
}

# Ejecutar menú
display_menu

# Post-procesamiento opcional
[ -f "$output_dir/algorithm/set-date.sh" ] && bash "$output_dir/algorithm/set-date.sh"
[ -f "$script_dir/move.sh" ] && bash "$script_dir/move.sh"
