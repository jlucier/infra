#!/bin/bash

# Configuration
DOWNLOAD_DIRS=(
    "/bigboi/media/downloads/sab/complete"
    "/bigboi/media/downloads/qbit/complete"
)
MEDIA_DIRS=(
    "/bigboi/media/movies"
    "/bigboi/media/music"
    "/bigboi/media/tv"
)

# Minimum age in minutes before considering a file for cleanup
MIN_AGE_MINUTES=60

# Dry run mode - set to 1 to see what would be deleted without actually deleting
DRY_RUN=0

# Parallelization - number of concurrent jobs (0 = auto-detect CPU cores)
PARALLEL_JOBS=0

# Logging
LOG_FILE="/var/log/hardlink-cleanup.log"
LOG_MAX_SIZE_MB=10  # Rotate when log exceeds this size
LOG_MAX_BACKUPS=2   # Keep this many old log files
VERBOSE=0

# Rotate logs if needed
rotate_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        return
    fi

    local log_size=$(stat -c '%s' "$LOG_FILE" 2>/dev/null || stat -f '%z' "$LOG_FILE" 2>/dev/null)
    local max_size=$((LOG_MAX_SIZE_MB * 1024 * 1024))

    if [ "$log_size" -gt "$max_size" ]; then
        # Remove oldest backup if we're at max
        if [ -f "${LOG_FILE}.${LOG_MAX_BACKUPS}" ]; then
            rm "${LOG_FILE}.${LOG_MAX_BACKUPS}"
        fi

        # Rotate existing backups
        for i in $(seq $((LOG_MAX_BACKUPS - 1)) -1 1); do
            if [ -f "${LOG_FILE}.${i}" ]; then
                mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
            fi
        done

        # Rotate current log
        mv "$LOG_FILE" "${LOG_FILE}.1"

        # Compress old logs (optional)
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

# Export functions and variables for parallel
export MEDIA_DIRS
export MIN_AGE_MINUTES
export DRY_RUN
export LOG_FILE

# Function to find hardlink target in media directories
find_hardlink_target() {
    local file="$1"
    local inode=$(stat -c '%i' "$file" 2>/dev/null || stat -f '%i' "$file" 2>/dev/null)

    if [ -z "$inode" ]; then
        return 1
    fi

    # Search media directories for files with same inode
    for media_dir in "${MEDIA_DIRS[@]}"; do
        if [ ! -d "$media_dir" ]; then
            continue
        fi

        # Find files with same inode in media directory
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

# Function to check if file is old enough
is_old_enough() {
    local file="$1"
    local current_time=$(date +%s)
    local file_time=$(stat -c '%Y' "$file" 2>/dev/null || stat -f '%m' "$file" 2>/dev/null)
    local age_minutes=$(( (current_time - file_time) / 60 ))

    [ $age_minutes -ge $MIN_AGE_MINUTES ]
}
export -f is_old_enough

# Function to get human-readable size
get_size() {
    local file="$1"
    du -h "$file" 2>/dev/null | cut -f1
}
export -f get_size

# Process a single file (to be run in parallel)
process_file() {
    local file="$1"

    # Check if file is old enough
    if ! is_old_enough "$file"; then
        return 0
    fi

    # Get link count (number of hardlinks)
    local link_count=$(stat -c '%h' "$file" 2>/dev/null || stat -f '%l' "$file" 2>/dev/null)

    # If link count > 1, file has hardlinks
    if [ "$link_count" -gt 1 ]; then
        # Find the hardlink target in media directories
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

# Main cleanup function
cleanup_hardlinks() {
    local temp_results=$(mktemp)
    local files_processed=0
    local files_deleted=0
    local total_freed=0

    # Check if GNU parallel is available
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

        # Build file list
        local file_list=$(mktemp)
        find "$download_dir" -type f > "$file_list"
        files_processed=$(wc -l < "$file_list")

        log "Found $files_processed files to check"

        if [ $USE_PARALLEL -eq 1 ]; then
            # Process files in parallel
            local jobs_flag=""
            if [ $PARALLEL_JOBS -gt 0 ]; then
                jobs_flag="-j $PARALLEL_JOBS"
            fi

            parallel $jobs_flag process_file :::: "$file_list" >> "$temp_results"
        else
            # Sequential fallback
            while IFS= read -r file; do
                process_file "$file" >> "$temp_results"
            done < "$file_list"
        fi

        rm "$file_list"
    done

    # Parse results
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

    # Summary
    local freed_mb=$((total_freed / 1024 / 1024))
    log "----------------------------------------"
    log "Cleanup complete!"
    log "Files processed: $files_processed"
    log "Files deleted: $files_deleted"
    log "Space freed: ${freed_mb} MB"
}

# Run cleanup
rotate_logs
log "========================================"
log "Starting hardlink cleanup"
log "Dry run mode: $DRY_RUN"
log "Minimum file age: $MIN_AGE_MINUTES minutes"
log "Parallel jobs: $PARALLEL_JOBS (0 = auto)"
cleanup_hardlinks
log "========================================"
