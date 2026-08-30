#!/bin/bash

DOWNLOAD_DIRS=(
    "/bigboi/media/downloads/sab/complete"
    "/bigboi/media/downloads/qbit/complete"
)
MEDIA_DIRS=(
    "/bigboi/media/movies"
    "/bigboi/media/music"
    "/bigboi/media/tv"
)

# A file must be at least this many minutes old before cleanup touches it.
MIN_AGE_MINUTES=60

# Set to 1 to log what the script would delete, and delete nothing.
DRY_RUN=0

# Number of parallel jobs. 0 means one job per CPU core.
PARALLEL_JOBS=0

LOG_FILE="/var/log/hardlink-cleanup.log"
LOG_MAX_SIZE_MB=10  # Rotate the log when it passes this size.
LOG_MAX_BACKUPS=2   # Number of old log files to keep.
VERBOSE=0

rotate_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    local log_size=$(stat -c '%s' "$LOG_FILE" 2>/dev/null || stat -f '%z' "$LOG_FILE" 2>/dev/null)
    local max_size=$((LOG_MAX_SIZE_MB * 1024 * 1024))

    if [ "$log_size" -gt "$max_size" ]; then
        if [ -f "${LOG_FILE}.${LOG_MAX_BACKUPS}" ]; then
            rm "${LOG_FILE}.${LOG_MAX_BACKUPS}"
        fi

        for i in $(seq $((LOG_MAX_BACKUPS - 1)) -1 1); do
            if [ -f "${LOG_FILE}.${i}" ]; then
                mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
            fi
        done

        mv "$LOG_FILE" "${LOG_FILE}.1"

        # Compress the old logs.
        if command -v gzip &> /dev/null; then
            for i in $(seq 2 $LOG_MAX_BACKUPS); do
                if [ -f "${LOG_FILE}.${i}" ] && [ ! -f "${LOG_FILE}.${i}.gz" ]; then
                    gzip "${LOG_FILE}.${i}"
                fi
            done
        fi
    fi
}

log() {
    if [ $VERBOSE -eq 1 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

export MEDIA_DIRS
export MIN_AGE_MINUTES
export DRY_RUN
export LOG_FILE

find_hardlink_target() {
    local file="$1"
    local inode=$(stat -c '%i' "$file" 2>/dev/null || stat -f '%i' "$file" 2>/dev/null)

    if [ -z "$inode" ]; then
        return 1
    fi

    for media_dir in "${MEDIA_DIRS[@]}"; do
        if [ ! -d "$media_dir" ]; then
            continue
        fi

        local target=$(find "$media_dir" -inum "$inode" -type f 2>/dev/null | while read -r f; do
            [ "$f" != "$file" ] && echo "$f" && break
        done)

        if [ -n "$target" ]; then
            echo "$target"
            return 0
        fi
    done

    return 1
}
export -f find_hardlink_target

is_old_enough() {
    local file="$1"
    local current_time=$(date +%s)
    local file_time=$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null)
    local age_minutes=$(( (current_time - file_time) / 60 ))

    [ $age_minutes -ge $MIN_AGE_MINUTES ]
}
export -f is_old_enough

get_size() {
    local file="$1"
    du -h "$file" 2>/dev/null | cut -f1
}
export -f get_size

# Process one file. parallel runs many copies of this function at once.
process_file() {
    local file="$1"

    if ! is_old_enough "$file"; then
        return 0
    fi

    # Count the hardlinks.
    local link_count=$(stat -c '%h' "$file" 2>/dev/null || stat -f '%l' "$file" 2>/dev/null)

    # More than one link means the file is hardlinked.
    if [ "$link_count" -gt 1 ]; then
        # Find the other link under the media directories.
        local target=$(find_hardlink_target "$file")

        if [ -n "$target" ]; then
            local size=$(stat -c '%s' "$file" 2>/dev/null || stat -f '%z' "$file" 2>/dev/null)
            local human_size=$(get_size "$file")

            echo "FOUND|$file|$target|$human_size|$size"

            if [ $DRY_RUN -eq 1 ]; then
                echo "DRYRUN|$file"
            else
                if rm "$file" 2>/dev/null; then
                    echo "DELETED|$file|$size"
                else
                    echo "ERROR|$file"
                fi
            fi
        fi
    fi
}
export -f process_file

cleanup_hardlinks() {
    local temp_results=$(mktemp)
    local files_processed=0
    local files_deleted=0
    local total_freed=0

    if ! command -v parallel &> /dev/null; then
        log "ERROR: GNU parallel not found. Install with: sudo apt-get install parallel"
        log "Falling back to sequential processing..."
        USE_PARALLEL=0
    else
        USE_PARALLEL=1
    fi

    for download_dir in "${DOWNLOAD_DIRS[@]}"; do
        if [ ! -d "$download_dir" ]; then
            log "Warning: Download directory does not exist: $download_dir"
            continue
        fi

        log "Processing directory: $download_dir"

        local file_list=$(mktemp)
        find "$download_dir" -type f > "$file_list"
        files_processed=$(wc -l < "$file_list")

        log "Found $files_processed files to check"

        if [ $USE_PARALLEL -eq 1 ]; then
            local jobs_flag=""
            if [ $PARALLEL_JOBS -gt 0 ]; then
                jobs_flag="-j $PARALLEL_JOBS"
            fi

            parallel $jobs_flag process_file :::: "$file_list" >> "$temp_results"
        else
            # No parallel, so process the files one at a time.
            while IFS= read -r file; do
                process_file "$file" >> "$temp_results"
            done < "$file_list"
        fi

        rm "$file_list"
    done

    while IFS='|' read -r action file rest; do
        case "$action" in
            FOUND)
                local target=$(echo "$rest" | cut -d'|' -f1)
                local human_size=$(echo "$rest" | cut -d'|' -f2)
                log "Found hardlinked file: $file"
                log "  -> Linked to: $target"
                log "  -> Size: $human_size"
                ;;
            DRYRUN)
                log "  -> [DRY RUN] Would delete download copy"
                ;;
            DELETED)
                local size=$(echo "$rest" | cut -d'|' -f1)
                log "  -> Deleted download copy"
                files_deleted=$((files_deleted + 1))
                total_freed=$((total_freed + size))
                ;;
            ERROR)
                log "  -> ERROR: Failed to delete file"
                ;;
        esac
    done < "$temp_results"

    rm "$temp_results"

    local freed_mb=$((total_freed / 1024 / 1024))
    log "----------------------------------------"
    log "Cleanup complete!"
    log "Files processed: $files_processed"
    log "Files deleted: $files_deleted"
    log "Space freed: ${freed_mb} MB"
}

rotate_logs
log "========================================"
log "Starting hardlink cleanup"
log "Dry run mode: $DRY_RUN"
log "Minimum file age: $MIN_AGE_MINUTES minutes"
log "Parallel jobs: $PARALLEL_JOBS (0 = auto)"
cleanup_hardlinks
log "========================================"
