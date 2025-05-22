# ================================
# SEARCH TOOL – SEARCH.SH
# ================================

script_dir="$(dirname "$0")"
mkdir -p "$script_dir/../output"

# Leer ruta de directorio desde archivo
directory_file="$script_dir/../functions/directory.txt"
[ ! -f "$directory_file" ] && whiptail --msgbox "File not found" 10 60 && exit 1
directory=$(cat "$directory_file")

# Buscar archivos CSV/TSV
mapfile -t files < <(find "$directory" -maxdepth 1 -type f \( -iname "*.csv" -o -iname "*.tsv" \))
[ "${#files[@]}" -eq 0 ] && whiptail --msgbox "No CSV/TSV found" 10 60 && exit 1

# Menú para seleccionar archivo
choices=()
for i in "${!files[@]}"; do
  fname=$(basename "${files[$i]}")
  choices+=("$i" "$fname")
done
selected_idx=$(whiptail --title "SELECT FILE" --menu "Files:" 20 70 10 "${choices[@]}" 3>&1 1>&2 2>&3)
[ -z "$selected_idx" ] && exit 0
file="${files[$selected_idx]}"
[ ! -f "$file" ] && whiptail --msgbox "File not found." 10 60 && exit 1

# Detectar delimitador
detect_delimiter() {
  local line
  line=$(head -n 2 "$1" | tail -n 1)
  if grep -q $'\t' <<< "$line"; then echo -e "\t"
  elif grep -q ';' <<< "$line"; then echo ";"
  else echo ","
  fi
}
delimiter=$(detect_delimiter "$file")

# Leer encabezado
IFS="$delimiter" read -ra headers <<< "$(head -n 1 "$file")"
options=()
for i in "${!headers[@]}"; do
  colname="${headers[$i]}"
  options+=("$((i+1))" "$colname")
done

# Funciones
select_column() {
  whiptail --title "SELECT COLUMN" --menu "Columns:" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3
}

# ================================
# Menú principal
# ================================
ACTION=$(whiptail --title "SEARCH TOOL" --menu "Select an action:" 20 70 10 \
"1" "Regex search" \
"2" "Columns filter" \
"3" "Sort column" \
"4" "Unique values" 3>&1 1>&2 2>&3)

[ -z "$ACTION" ] && exit 0

case "$ACTION" in


# -------------------------
# 1. Búsqueda por regex
# -------------------------
"1")
  output_file="$script_dir/../output/regex_result.txt"

  scope=$(whiptail --title "SEARCH" --menu "Find regex in:" 15 60 3 \
    "1" "All files" \
    "2" "Specific column" 3>&1 1>&2 2>&3)
  [ -z "$scope" ] && exit 0

  if [[ "$scope" == "2" ]]; then
    col_index=$(select_column)
    [ -z "$col_index" ] && exit 0
  fi

  regex=$(whiptail --inputbox "Enter regex:" 10 60 3>&1 1>&2 2>&3)
  [ -z "$regex" ] && exit 0

  if [[ "$scope" == "1" ]]; then
    # Buscar en todo el archivo sin cabecera
    match_lines=$(tail -n +2 "$file" | grep -Ei "$regex")
    match_count=$(echo "$match_lines" | wc -l)

    {
      echo "🔍 REGEX – SEARCH TOOL"
      echo "File: $(basename "$file")"
      echo "Directory: $directory"
      echo "Date: $(date)"
      echo "=============================================================="
      echo "Regex: $regex"
      echo "Records found: $match_count"
      echo ""
      head -n 1 "$file"           # Mostrar encabezado
      echo "$match_lines"         # Mostrar coincidencias
    } > "$output_file"
  else
    match_lines=$(awk -F"$delimiter" -v idx="$col_index" -v re="$regex" 'NR > 1 && $idx ~ re' "$file")
    match_count=$(echo "$match_lines" | wc -l)

    {
      echo "REGEX – SEARCH TOOL"
      echo "File: $(basename "$file")"
      echo "Directory: $directory"
      echo "Date: $(date)"
      echo "=============================================================="
      echo "Regex: $regex"
      echo "Column: ${headers[$((col_index-1))]} (\$$col_index)"
      echo "Records found: $((match_count - 1))"
      echo ""
      echo "$(head -n 1 "$file")"
      echo "$match_lines"
    } > "$output_file"
  fi

  whiptail --title "REGEX – SEARCH TOOL" --textbox "$output_file" 25 80
  whiptail --msgbox "Records saved in: output/regex_result.txt" 10 60
  ;;

# -------------------------
# 2. Filtro por condiciones múltiples
# -------------------------
"2")
output_file="$script_dir/../output/condition_result.txt"
tmpfile=$(mktemp)
cp "$file" "$tmpfile"

condition_list=()
condition_desc=""

while true; do
  col_index=$(whiptail --title "SELECT COLUMN" --menu "Columns:" 20 70 12 \
    "${options[@]}" \
    "none" "Not add more columns" 3>&1 1>&2 2>&3)
  [ -z "$col_index" ] && exit 0
  if [[ "$col_index" == "none" ]]; then break; fi

  operator=$(whiptail --title "LOGICAL OPERADOR" --menu "Operadors:" 15 60 6 \
    "==" "Equal to" \
    "!=" "Not equal " \
    ">"  "Graater than" \
    "<"  "Less than" \
    ">=" "Greater than o equal" \
    "<=" "Less than o equal" 3>&1 1>&2 2>&3)
  [ -z "$operator" ] && exit 0

  value=$(whiptail --inputbox "Column value ${headers[$((col_index-1))]} (columna \$$col_index):" 10 70 3>&1 1>&2 2>&3)
  [ -z "$value" ] && continue

  condition="(\$$col_index $operator \"$value\")"
  condition_desc+="\$$col_index $operator \"$value\"; "

  awk -F"$delimiter" "$condition || NR==1" "$tmpfile" > "$tmpfile.filtered"
  mv "$tmpfile.filtered" "$tmpfile"
done

count=$(awk 'END{print NR-1}' "$tmpfile")

{
  echo "FILTER – SEARCH TOOL"
  echo "File: $(basename "$file")"
  echo "Directory: $directory"
  echo "Date: $(date)"
  echo "=============================================================="
  echo "Condition: ${condition_desc:-NINGUNA}"
  echo "Records found: $count"
  echo ""
  cat "$tmpfile"
} > "$output_file"

rm -f "$tmpfile"
whiptail --title "FILTER – SEARCH TOOL" --textbox "$output_file" 25 80
whiptail --msgbox " Filtered save in: output/condition_result.txt" 10 60
;;



# -------------------------
# 3. Ordenar por columna
# -------------------------
"3")
output_file="$script_dir/../output/sort_result.txt"
col_index=$(select_column)
[ -z "$col_index" ] && exit 0

sorted_data=$(tail -n +2 "$file" | sort -t"$delimiter" -k"$col_index","$col_index")
result_count=$(echo "$sorted_data" | wc -l)

{
  echo "SORT – SEARCH TOOL"
  echo "File: $(basename "$file")"
  echo "Directory: $directory"
  echo "Date: $(date)"
  echo "=============================================================="
  echo "Sorted column: ${headers[$((col_index-1))]} (\$$col_index)"
  echo "Records found: $result_count"
  echo ""
  head -n 1 "$file"
  echo "$sorted_data"
} > "$output_file"

whiptail --title "SORT – SEARCH TOOL" --textbox "$output_file" 25 80
whiptail --msgbox "Records saved in: output/sort_result.txt" 10 60
;;

# -------------------------
# 4. Listar valores únicos por columna
# -------------------------
"4")
output_file="$script_dir/../output/unique_result.txt"
col_index=$(select_column)
[ -z "$col_index" ] && exit 0

unique_values=$(awk -F"$delimiter" -v idx="$col_index" 'NR > 1 && $idx ~ /[^[:space:]]/ { gsub(/^[ \t]+|[ \t]+$/, "", $idx); print $idx }' "$file" | sort | uniq)
unique_count=$(echo "$unique_values" | wc -l)


{
  echo "UNIQUE VALUES – SEARCH TOOL"
  echo "File: $(basename "$file")"
  echo "Column: ${headers[$((col_index-1))]} (\$$col_index)"
  echo "=============================================================="
  echo "Unique values: $unique_count"
  echo "$unique_values"
} > "$output_file"

whiptail --title "UNIQUE VALUES – SEARCH TOOL" --textbox "$output_file" 25 80
whiptail --msgbox "Records saved in: output/unique_result.txt" 10 60
;;


esac
