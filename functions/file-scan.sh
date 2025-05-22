#!/bin/bash

script_dir="$(dirname "$0")"
directory=$(<"$script_dir/../functions/directory.txt")
output_file="$script_dir/../output/scan-report.txt"
mkdir -p "$script_dir/../output"

# Funciones auxiliares
detect_delimiter() {
  local line
  line=$(head -n 2 "$1" | tail -n 1)
  if grep -q $'\t' <<< "$line"; then
    echo -e "\t"
  elif grep -q ';' <<< "$line"; then
    echo ";"
  else
    echo ","
  fi
}

classify_columns() {
  local file="$1"
  local delimiter="$2"
  awk -F"$delimiter" '
  NR == 1 { for (i = 1; i <= NF; i++) header[i] = $i; next }
  {
    for (i = 1; i <= NF; i++) {
      if ($i !~ /^[0-9]+([.][0-9]+)?$/) nonnum[i]++;
      total[i]++;
    }
  }
  END {
    for (i = 1; i <= length(header); i++) {
      tipo = (nonnum[i] > 0) ? "NON NUMERIC" : "NUMERIC";
      printf "Column %d (%s): %s\n", i, header[i], tipo;
    }
  }' "$file"
}

# Buscar archivos CSV/TSV
mapfile -t files < <(find "$directory" -maxdepth 1 -type f \( -iname "*.csv" -o -iname "*.tsv" \))
[[ "${#files[@]}" -eq 0 ]] && whiptail --msgbox "No CSV/TSV found in: $directory" 10 60 && exit 1

# Escoger escaneo total o individual
scan_option=$(whiptail --title "FILE SCAN" --menu " Scan:" 15 60 2 \
"1" "All files in the directory" \
"2" "Select files" 3>&1 1>&2 2>&3)

[[ -z "$scan_option" ]] && exit 0   # ←←← CORRECCIÓN: volver al menú principal si se presiona Cancel

if [[ "$scan_option" == "2" ]]; then
  file_choices=()
  for i in "${!files[@]}"; do
    fname=$(basename "${files[$i]}")
    file_choices+=("$i" "$fname")
  done
  selected_idx=$(whiptail --title "SELECT FILE" --menu "File to scan:" 20 70 10 "${file_choices[@]}" 3>&1 1>&2 2>&3)
  [[ -z "$selected_idx" ]] && exit 0
  selected_file="${files[$selected_idx]}"
  files=("$selected_file")
  check_duplicates_single=true
fi

# Mostrar opción de líneas a visualizar
lines_view=$(whiptail --radiolist "Lines to show:" 15 60 4 \
"H" "Head" ON \
"T" "Tail" OFF \
"B" "Both" OFF \
"N" "None" OFF 3>&1 1>&2 2>&3)
[[ -z "$lines_view" ]] && exit 0

# Preguntar cuántas líneas solo si no es "none"
if [[ "$lines_view" != "N" ]]; then
  num_lines=$(whiptail --inputbox "Lines to display (default 5):" 10 60 5 3>&1 1>&2 2>&3)
  [[ $? -ne 0 ]] && exit 0
  [[ -z "$num_lines" ]] && num_lines=5
else
  num_lines=0
fi

# Iniciar reporte
echo "File Scan CSV/TSV" > "$output_file"
echo "Directory: $directory" >> "$output_file"
echo "Analyzed files $(date)" >> "$output_file"
echo "======================================================" >> "$output_file"
echo "" >> "$output_file"

declare -A file_hashes
declare -A duplicate_groups
group_counter=1

for file in "${files[@]}"; do
  base=$(basename "$file")
  echo "File: $base" >> "$output_file"

  delimiter=$(detect_delimiter "$file")
  [[ "$delimiter" == $'\t' ]] && delimname="Tabulador" || delimname="$delimiter"
  echo "Field separator: $delimname" >> "$output_file"

  rows=$(wc -l < "$file")
  cols=$(head -n 1 "$file" | awk -F"$delimiter" '{print NF}')
  echo "Rows: $rows" >> "$output_file"
  echo "Columns: $cols" >> "$output_file"
  echo "" >> "$output_file"

  if [[ "$lines_view" == "H" || "$lines_view" == "B" ]]; then
    echo "Head ($num_lines):" >> "$output_file"
    head -n "$num_lines" "$file" >> "$output_file"
    echo "" >> "$output_file"
  fi

  if [[ "$lines_view" == "T" || "$lines_view" == "B" ]]; then
    echo "Tail ($num_lines):" >> "$output_file"
    tail -n "$num_lines" "$file" >> "$output_file"
    echo "" >> "$output_file"
  fi

  echo "Column type:" >> "$output_file"
  classify_columns "$file" "$delimiter" >> "$output_file"

  # Calcular hash de contenido del archivo (sin importar nombre)
  hash=$(sha256sum "$file" | awk '{print $1}')
  if [[ -n "${file_hashes[$hash]}" ]]; then
    duplicate_groups["$hash"]+=$'\n'"$base"
  else
    file_hashes["$hash"]="1"
    duplicate_groups["$hash"]="$base"
  fi

  echo -e "\n------------------------------------------------------\n" >> "$output_file"
done

# Comparar con archivos restantes si solo se seleccionó uno
if [[ "$check_duplicates_single" == true ]]; then
  original_hash=$(sha256sum "$selected_file" | awk '{print $1}')
  for other_file in "${directory}"/*.csv "${directory}"/*.tsv; do
    [[ "$other_file" == "$selected_file" ]] && continue
    [[ ! -f "$other_file" ]] && continue
    other_hash=$(sha256sum "$other_file" | awk '{print $1}')
    if [[ "$original_hash" == "$other_hash" ]]; then
      duplicate_groups["$original_hash"]+=$'\n'"$(basename "$other_file")"
    fi
  done
fi

# Verificar duplicados por contenido
echo -e "\nDuplicate check (by content):" >> "$output_file"
dupes_found=0
for hash in "${!duplicate_groups[@]}"; do
  group="${duplicate_groups[$hash]}"
  lines=$(grep -c '^' <<< "$group")
  if [[ "$lines" -gt 1 ]]; then
    echo "Duplicate files (group $group_counter):" >> "$output_file"
    echo "$group" >> "$output_file"
    echo "" >> "$output_file"
    ((group_counter++))
    ((dupes_found++))
  fi
done
[[ "$dupes_found" -eq 0 ]] && echo " No duplicate files" >> "$output_file"

# Confirmación final
echo -e "\n Saving results: $output_file" >> "$output_file"

# Mostrar reporte
whiptail --title "SCAN REPORT PREVIEW" --scrolltext --msgbox "$(cat "$output_file")" 30 100
