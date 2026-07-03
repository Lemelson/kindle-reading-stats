#!/bin/sh

BASE="/mnt/us/extensions/readingstats"
BIN="$BASE/bin"
DATA="$BASE/data"
STATE="$BASE/state"
RUNLOG="$DATA/readingstats.log"
PIDFILE="$STATE/collector.pid"

LOGFILES="/var/log/metrics_generic /var/log/metrics_high_priority /var/log/messages /var/log/cvm"
MATCH_EXPR="ereader_|mar_book_read_stats|reader\\.activeDuration|ReadingSession|book_page_turn|book_consume_content|open_book|close_book|content_point"

mkdir -p "$DATA" "$STATE"

msg_screen() {
    text="$1"
    echo "$text" >> "$RUNLOG"
    if command -v eips >/dev/null 2>&1; then
        eips 2 38 "                                      "
        eips 2 39 "                                      "
        eips 2 40 "                                      "
        eips 2 38 "$text"
    fi
}

now_utc() {
    date -u "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date "+%Y-%m-%dT%H:%M:%S"
}

month_id() {
    date "+%Y-%m"
}

json_escape() {
    sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

is_running() {
    if [ -f "$PIDFILE" ]; then
        pid="$(cat "$PIDFILE" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

event_file() {
    echo "$DATA/events-$(month_id).jsonl"
}

extract_schema() {
    line="$1"
    schema="$(printf '%s\n' "$line" | sed -n 's/.*SchemaName\[\([^]]*\)\].*/\1/p')"
    if [ -z "$schema" ]; then
        case "$line" in
            *reader.activeDuration*) schema="reader.activeDuration" ;;
            *) schema="unknown" ;;
        esac
    fi
    printf '%s' "$schema"
}

extract_fields() {
    line="$1"
    fields="$(printf '%s\n' "$line" | sed -n 's/.*Fields\[\(.*\)\][[:space:]]*\\.[[:space:]]*:.*/\1/p')"
    if [ -z "$fields" ]; then
        fields="$(printf '%s\n' "$line" | sed -n 's/.*Fields\[\(.*\)\].*/\1/p')"
    fi
    printf '%s' "$fields"
}

extract_value() {
    key="$1"
    line="$2"
    printf '%s\n' "$line" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

extract_number() {
    key="$1"
    line="$2"
    printf '%s\n' "$line" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -1
}

write_event() {
    src="$1"
    line="$2"

    printf '%s\n' "$line" | grep -E "$MATCH_EXPR" >/dev/null 2>&1 || return 0

    schema="$(extract_schema "$line")"
    fields="$(extract_fields "$line")"
    cde_key="$(extract_value "cde_key" "$line")"
    action_id="$(extract_value "action_id" "$line")"
    context="$(extract_value "context" "$line")"
    point_type="$(extract_value "point_type" "$line")"
    close_method="$(extract_value "close_method" "$line")"
    start_position="$(extract_number "start_position" "$line")"
    end_position="$(extract_number "end_position" "$line")"
    close_position="$(extract_number "close_position" "$line")"
    action_start_time="$(extract_number "action_start_time" "$line")"
    close_timestamp="$(extract_number "close_timestamp" "$line")"

    ts="$(now_utc)"
    out="${EVENT_OUT:-$(event_file)}"

    raw_e="$(printf '%s' "$line" | json_escape)"
    fields_e="$(printf '%s' "$fields" | json_escape)"
    src_e="$(printf '%s' "$src" | json_escape)"
    schema_e="$(printf '%s' "$schema" | json_escape)"
    cde_e="$(printf '%s' "$cde_key" | json_escape)"
    action_e="$(printf '%s' "$action_id" | json_escape)"
    context_e="$(printf '%s' "$context" | json_escape)"
    point_e="$(printf '%s' "$point_type" | json_escape)"
    close_e="$(printf '%s' "$close_method" | json_escape)"

    printf '{"captured_at":"%s","source":"%s","schema":"%s","cde_key":"%s","action_id":"%s","context":"%s","point_type":"%s","close_method":"%s","start_position":"%s","end_position":"%s","close_position":"%s","action_start_time":"%s","close_timestamp":"%s","fields_text":"%s","raw":"%s"}\n' \
        "$ts" "$src_e" "$schema_e" "$cde_e" "$action_e" "$context_e" "$point_e" "$close_e" \
        "$start_position" "$end_position" "$close_position" "$action_start_time" "$close_timestamp" \
        "$fields_e" "$raw_e" >> "$out"
}

offset_file_for() {
    b="$(basename "$1")"
    echo "$STATE/offset.$b"
}

init_offsets_at_end() {
    for f in $LOGFILES; do
        if [ -f "$f" ]; then
            wc -c < "$f" > "$(offset_file_for "$f")" 2>/dev/null
        else
            echo 0 > "$(offset_file_for "$f")"
        fi
    done
}

collect_file_delta() {
    f="$1"
    [ -f "$f" ] || return 0
    offile="$(offset_file_for "$f")"
    old="$(cat "$offile" 2>/dev/null)"
    [ -n "$old" ] || old=0
    size="$(wc -c < "$f" 2>/dev/null)"
    [ -n "$size" ] || return 0

    if [ "$size" -lt "$old" ]; then
        old=0
    fi
    if [ "$size" -gt "$old" ]; then
        count=$((size - old))
        dd if="$f" bs=1 skip="$old" count="$count" 2>/dev/null | while IFS= read -r line; do
            write_event "$f" "$line"
        done
        echo "$size" > "$offile"
    fi
}

collector_loop() {
    echo "$$" > "$PIDFILE"
    echo "$(now_utc) collector started" >> "$RUNLOG"
    init_offsets_at_end

    while true; do
        for f in $LOGFILES; do
            collect_file_delta "$f"
        done
        sleep 2
    done
}

start_logger() {
    if is_running; then
        msg_screen "ReadingStats already running"
        exit 0
    fi
    nohup "$0" collect >/dev/null 2>&1 &
    sleep 1
    if is_running; then
        msg_screen "ReadingStats started"
    else
        msg_screen "ReadingStats start failed"
    fi
}

stop_logger() {
    if is_running; then
        pid="$(cat "$PIDFILE" 2>/dev/null)"
        kill "$pid" 2>/dev/null
        sleep 1
        kill -9 "$pid" 2>/dev/null
        rm -f "$PIDFILE"
        echo "$(now_utc) collector stopped" >> "$RUNLOG"
        msg_screen "ReadingStats stopped"
    else
        rm -f "$PIDFILE"
        msg_screen "ReadingStats not running"
    fi
}

status_logger() {
    total=0
    today=0
    current="$(event_file)"
    [ -f "$current" ] && today="$(grep -c "$(date '+%Y-%m-%d')" "$current" 2>/dev/null)"
    for f in "$DATA"/events-*.jsonl; do
        [ -f "$f" ] || continue
        n="$(wc -l < "$f" 2>/dev/null)"
        total=$((total + n))
    done
    if is_running; then
        msg_screen "ReadingStats running. Events: $total"
    else
        msg_screen "ReadingStats stopped. Events: $total"
    fi
    echo "today=$today total=$total data=$DATA" >> "$RUNLOG"
}

snapshot_now() {
    EVENT_OUT="$DATA/snapshot-$(date '+%Y%m%d-%H%M%S').jsonl"
    export EVENT_OUT
    for f in $LOGFILES; do
        [ -f "$f" ] || continue
        grep -E "$MATCH_EXPR" "$f" 2>/dev/null | while IFS= read -r line; do
            write_event "$f" "$line"
        done
    done
    for f in /mnt/us/system/logbackup/*.gz; do
        [ -f "$f" ] || continue
        gzip -cd "$f" 2>/dev/null | grep -E "$MATCH_EXPR" | while IFS= read -r line; do
            write_event "$f" "$line"
        done
    done
    unset EVENT_OUT
    msg_screen "Snapshot saved"
}

today_summary() {
    current="$(event_file)"
    day="$(date '+%Y-%m-%d')"
    if [ ! -f "$current" ]; then
        msg_screen "No events for today yet"
        exit 0
    fi
    pt="$(grep "$day" "$current" | grep -E -c 'ereader_book_page_turn|ereader_reader_page_turn_latency_ops|ereader_book_page_actions_ops' 2>/dev/null)"
    open="$(grep "$day" "$current" | grep -c 'ereader_open_book' 2>/dev/null)"
    close="$(grep "$day" "$current" | grep -c 'ereader_close_book' 2>/dev/null)"
    msg_screen "Today: turns $pt open $open close $close"
}

case "$1" in
    start) start_logger ;;
    stop) stop_logger ;;
    status) status_logger ;;
    snapshot) snapshot_now ;;
    today) today_summary ;;
    collect) collector_loop ;;
    *) status_logger ;;
esac
