#!/bin/bash
# ============================================================
# MOCK WHIPTAIL — Automated Test Harness
# ============================================================
# Replaces real whiptail with scripted responses.
# Reads a response queue from $MOCK_WHIPTAIL_RESPONSES (one per line).
# Logs every invocation to $MOCK_WHIPTAIL_LOG for assertion.
#
# Behavior:
#   --yesno  → return 0 (Yes) or 1 (No) based on queue
#   --menu   → echo the queued value to fd 3 (whiptail convention)
#   --msgbox → log and continue (no user input needed)
#   --inputbox   → echo the queued value to fd 3
#   --radiolist  → echo the queued value to fd 3
#   --checklist  → echo the queued value to fd 3
#   --textbox    → log and continue
# ============================================================

QUEUE_FILE="${MOCK_WHIPTAIL_RESPONSES:-/tmp/mock_whiptail_queue.txt}"
LOG_FILE="${MOCK_WHIPTAIL_LOG:-/tmp/mock_whiptail.log}"
COUNTER_FILE="${MOCK_WHIPTAIL_COUNTER:-/tmp/mock_whiptail_counter.txt}"

# Initialize counter if not present
[ ! -f "$COUNTER_FILE" ] && echo "0" > "$COUNTER_FILE"

# Read current position
pos=$(< "$COUNTER_FILE")

# Detect the whiptail mode from arguments
mode=""
title=""
for arg in "$@"; do
  case "$arg" in
    --yesno)     mode="yesno" ;;
    --menu)      mode="menu" ;;
    --msgbox)    mode="msgbox" ;;
    --inputbox)  mode="inputbox" ;;
    --radiolist) mode="radiolist" ;;
    --checklist) mode="checklist" ;;
    --textbox)   mode="textbox" ;;
    --title)     :;; # next arg is the title
  esac
done

# Extract --title value
title_next=false
for arg in "$@"; do
  if $title_next; then title="$arg"; title_next=false; continue; fi
  [[ "$arg" == "--title" ]] && title_next=true
done

# Log this call
echo "[CALL #$pos] mode=$mode title=\"$title\" args: $*" >> "$LOG_FILE"

# Read the next response from the queue
response=""
if [ -f "$QUEUE_FILE" ]; then
  response=$(sed -n "$((pos + 1))p" "$QUEUE_FILE")
fi

# Advance counter
echo "$((pos + 1))" > "$COUNTER_FILE"

case "$mode" in
  yesno)
    echo "[CALL #$pos] yesno → response='$response' (0=yes, 1=no)" >> "$LOG_FILE"
    if [[ "$response" == "NO" || "$response" == "1" ]]; then
      exit 1
    fi
    exit 0
    ;;
  menu|inputbox|radiolist)
    echo "[CALL #$pos] $mode → returning '$response'" >> "$LOG_FILE"
    # whiptail writes to stderr, which gets redirected to fd 3 by caller
    echo "$response" >&2
    exit 0
    ;;
  checklist)
    echo "[CALL #$pos] checklist → returning '$response'" >> "$LOG_FILE"
    echo "$response" >&2
    exit 0
    ;;
  msgbox|textbox)
    echo "[CALL #$pos] $mode → acknowledged (no response needed)" >> "$LOG_FILE"
    exit 0
    ;;
  *)
    echo "[CALL #$pos] UNKNOWN mode → passing through, response='$response'" >> "$LOG_FILE"
    echo "$response" >&2
    exit 0
    ;;
esac
