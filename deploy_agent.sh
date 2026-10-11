#!/bin/bash

# ============================================================
# ALU Deploy Agent
# Features:
# 1. Deploy application
# 2. Run application
# 3. Archive logs
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

PROJECT_DIR=""
PROJECT_NAME=""
DEPLOYING=0
STUDENT_COUNT=0

# Sample students used for a fresh roster
NAMES=(
    "Alice Johnson"
    "Bob Smith"
    "Charlie Davis"
    "Diana Prince"
    "Evan Williams"
    "Fiona Brown"
    "George Miller"
    "Hannah Wilson"
    "Ian Moore"
    "Julia Taylor"
)

EMAILS=(
    "alice@example.com"
    "bob@example.com"
    "charlie@example.com"
    "diana@example.com"
    "evan@example.com"
    "fiona@example.com"
    "george@example.com"
    "hannah@example.com"
    "ian@example.com"
    "julia@example.com"
)

# ------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------

preflight_checks() {
    echo
    echo "=== Preflight checks ==="

    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is not installed or not available in PATH."
        return 1
    fi

    if ! command -v zip >/dev/null 2>&1; then
        echo "ERROR: zip is not installed or not available in PATH."
        return 1
    fi

    echo "Python: $(python3 --version 2>&1)"
    echo "zip: available"

    for template in attendance_checker.py assets.csv config.json
    do
        if [ ! -f "$TEMPLATE_DIR/$template" ]; then
            echo "ERROR: Missing template: $TEMPLATE_DIR/$template"
            return 1
        fi
    done

    echo "All required templates are available."
    echo "Preflight checks passed."
    return 0
}

# ------------------------------------------------------------
# Deployment signal handler
# ------------------------------------------------------------

handle_deploy_interrupt() {
    echo
    echo "============================================================"
    echo "Deployment interrupted by Ctrl+C or Ctrl+Z."
    echo "============================================================"

    DEPLOYING=0
    trap - SIGINT SIGTSTP

    if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
        local archive_path="$SCRIPT_DIR/${PROJECT_NAME}_archive.zip"

        echo "Archiving the incomplete project..."
        rm -f -- "$archive_path"

        if (
            cd "$SCRIPT_DIR" &&
            zip -rq "$archive_path" "$PROJECT_NAME"
        ); then
            echo "Incomplete project archived successfully:"
            echo "$archive_path"

            echo "Removing incomplete project directory..."
            rm -rf -- "$PROJECT_DIR"

            echo "Incomplete project directory removed."
            echo "Deployment closed cleanly."
        else
            echo "ERROR: Could not create the ZIP archive."
            echo "The incomplete project was kept at:"
            echo "$PROJECT_DIR"
            exit 1
        fi
    else
        echo "No incomplete project directory was found."
        echo "Deployment closed cleanly."
    fi

    exit 130
}

# ------------------------------------------------------------
# Read and validate project name
# ------------------------------------------------------------

get_project_name() {
    local input

    read -r -p "Enter the project name (for example: v1): " input

    if [ -z "$input" ]; then
        echo "ERROR: Project name cannot be empty."
        return 1
    fi

    if [[ ! "$input" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "ERROR: Use only letters, numbers, hyphens, and underscores."
        return 1
    fi

    PROJECT_NAME="attendance_tracker_${input}"
    PROJECT_DIR="$SCRIPT_DIR/$PROJECT_NAME"

    return 0
}

# ------------------------------------------------------------
# Read number of students
# ------------------------------------------------------------

read_student_count() {
    local maximum="$1"
    local count

    while true
    do
        read -r -p "How many students? (1-$maximum): " count

        if [[ "$count" =~ ^[0-9]+$ ]] &&
           [ "$count" -ge 1 ] &&
           [ "$count" -le "$maximum" ]; then
            STUDENT_COUNT="$count"
            return 0
        fi

        echo "Invalid number. Please enter a number from 1 to $maximum."
    done
}

# ------------------------------------------------------------
# Update thresholds
# ------------------------------------------------------------

update_thresholds() {
    local config_file="$PROJECT_DIR/Helpers/config.json"
    local answer
    local warning
    local failure

    echo
    read -r -p "Do you want to update the attendance thresholds? [y/n]: " answer

    case "${answer,,}" in
        y|yes)
            while true
            do
                read -r -p "Warning threshold [75]: " warning

                if [ -z "$warning" ]; then
                    warning=75
                fi

                if [[ "$warning" =~ ^[0-9]+$ ]] &&
                   [ "$warning" -le 100 ]; then
                    break
                fi

                echo "Invalid warning threshold. Enter a number from 0 to 100."
            done

            while true
            do
                read -r -p "Failure threshold [50]: " failure

                if [ -z "$failure" ]; then
                    failure=50
                fi

                if [[ "$failure" =~ ^[0-9]+$ ]] &&
                   [ "$failure" -le 100 ]; then
                    break
                fi

                echo "Invalid failure threshold. Enter a number from 0 to 100."
            done

            sed -i -E \
                "s/^([[:space:]]*\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+(,?[[:space:]]*)$/\1${warning}\2/" \
                "$config_file"

            sed -i -E \
                "s/^([[:space:]]*\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+(,?[[:space:]]*)$/\1${failure}\2/" \
                "$config_file"

            echo "Thresholds updated successfully."
            echo "Warning threshold: $warning"
            echo "Failure threshold: $failure"
            ;;

        n|no|"")
            echo "Keeping the default thresholds."
            ;;

        *)
            echo "Invalid choice. Keeping the default thresholds."
            ;;
    esac
}

# ------------------------------------------------------------
# Run application
# ------------------------------------------------------------

run_application() {
    local target_dir="$1"
    local status

    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 is not available."
        return 1
    fi

    if [ ! -d "$target_dir" ]; then
        echo "ERROR: Project directory does not exist:"
        echo "$target_dir"
        return 1
    fi

    if [ ! -f "$target_dir/attendance_checker.py" ]; then
        echo "ERROR: attendance_checker.py is missing."
        return 1
    fi

    if [ ! -d "$target_dir/Helpers" ]; then
        echo "ERROR: Helpers directory is missing."
        return 1
    fi

    if [ ! -f "$target_dir/Helpers/assets.csv" ]; then
        echo "ERROR: Helpers/assets.csv is missing."
        return 1
    fi

    if [ ! -f "$target_dir/Helpers/config.json" ]; then
        echo "ERROR: Helpers/config.json is missing."
        return 1
    fi

    if [ ! -d "$target_dir/reports" ]; then
        echo "ERROR: reports directory is missing."
        return 1
    fi

    echo
    echo "============================================================"
    echo "Starting attendance application..."
    echo "Project: $(basename "$target_dir")"
    echo "============================================================"
    echo "Mark the students as present or absent when prompted."
    echo

    (
        cd "$target_dir" || exit 1
        python3 attendance_checker.py
    )

    status=$?

    echo

    if [ "$status" -eq 0 ]; then
        echo "Application finished successfully."
    else
        echo "Application exited with status: $status"
    fi

    return "$status"
}

# ------------------------------------------------------------
# Feature 1: Deploy application
# ------------------------------------------------------------

deploy_application() {
    local roster_option
    local template_students
    local lines_to_copy
    local config_file
    local assets_file

    echo
    echo "============================================================"
    echo "FEATURE 1: DEPLOY APPLICATION"
    echo "============================================================"

    if ! preflight_checks; then
        return 1
    fi

    if ! get_project_name; then
        return 1
    fi

    # Protect an existing project
    if [ -e "$PROJECT_DIR" ]; then

        if [ ! -d "$PROJECT_DIR" ]; then
            echo "ERROR: $PROJECT_DIR exists but is not a directory."
            return 1
        fi

        echo
        echo "WARNING: The project already exists:"
        echo "$PROJECT_DIR"

        local overwrite
        read -r -p "Do you want to overwrite it? [y/n]: " overwrite

        case "${overwrite,,}" in
            y|yes)
                echo "Removing the existing project..."
                rm -rf -- "$PROJECT_DIR"
                ;;

            n|no|"")
                echo "Deployment aborted. Existing project was not changed."
                return 1
                ;;

            *)
                echo "Invalid choice. Deployment aborted."
                return 1
                ;;
        esac
    fi

    # Signals are handled only during deployment.
    DEPLOYING=1
    trap handle_deploy_interrupt SIGINT SIGTSTP

    echo
    echo "Creating deployment directory..."

    if ! mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports"; then
        echo "ERROR: Could not create deployment directories."
        DEPLOYING=0
        trap - SIGINT SIGTSTP
        return 1
    fi

    config_file="$PROJECT_DIR/Helpers/config.json"
    assets_file="$PROJECT_DIR/Helpers/assets.csv"

    # Copy the application and configuration from templates.
    if ! cp "$TEMPLATE_DIR/attendance_checker.py" \
            "$PROJECT_DIR/attendance_checker.py"; then
        echo "ERROR: Could not copy attendance_checker.py."
        DEPLOYING=0
        trap - SIGINT SIGTSTP
        return 1
    fi

    if ! cp "$TEMPLATE_DIR/config.json" "$config_file"; then
        echo "ERROR: Could not copy config.json."
        DEPLOYING=0
        trap - SIGINT SIGTSTP
        return 1
    fi

    echo "Application and configuration copied."

    # Choose roster method.
    echo
    echo "Choose how to create the student roster:"
    echo "A. Copy students from templates/assets.csv"
    echo "B. Generate a fresh roster with zero attendance"
    echo

    while true
    do
        read -r -p "Choose A or B: " roster_option

        case "${roster_option,,}" in
            a|b)
                break
                ;;
            *)
                echo "Invalid choice. Please enter A or B."
                ;;
        esac
    done

    case "${roster_option,,}" in

        a)
            template_students=$(( $(wc -l < "$TEMPLATE_DIR/assets.csv") - 1 ))

            if [ "$template_students" -lt 1 ]; then
                echo "ERROR: templates/assets.csv has no student records."
                DEPLOYING=0
                trap - SIGINT SIGTSTP
                return 1
            fi

            read_student_count "$template_students"

            lines_to_copy=$((STUDENT_COUNT + 1))

            if ! head -n "$lines_to_copy" \
                "$TEMPLATE_DIR/assets.csv" > "$assets_file"; then
                echo "ERROR: Could not create the deployed roster."
                DEPLOYING=0
                trap - SIGINT SIGTSTP
                return 1
            fi

            echo
            echo "Roster created from template."
            echo "Students included: $STUDENT_COUNT"
            echo "Total sessions: 5"
            ;;

        b)
            read_student_count "${#NAMES[@]}"

            {
                echo "Email,Names,Attendance Count,Absence Count"

                for ((i=0; i<STUDENT_COUNT; i++))
                do
                    printf '%s,%s,0,0\n' \
                        "${EMAILS[$i]}" \
                        "${NAMES[$i]}"
                done
            } > "$assets_file"

            # Fresh roster starts with zero previous sessions.
            sed -i 's/"total_sessions": 5/"total_sessions": 1/' \
                "$config_file"

            echo
            echo "Fresh roster created."
            echo "Students included: $STUDENT_COUNT"
            echo "Total sessions: 1"
            ;;

    esac

    # Permissions
    echo
    echo "Setting required permissions..."

    if ! chmod +x "$PROJECT_DIR/attendance_checker.py"; then
        echo "ERROR: Could not make attendance_checker.py executable."
        DEPLOYING=0
        trap - SIGINT SIGTSTP
        return 1
    fi

    if ! chmod 600 "$config_file"; then
        echo "ERROR: Could not set config.json permissions."
        DEPLOYING=0
        trap - SIGINT SIGTSTP
        return 1
    fi

    echo "Permissions set:"
    echo "  attendance_checker.py -> executable"
    echo "  Helpers/config.json -> 600"

    # Optional threshold update
    update_thresholds

    # Verify the deployed structure before running the application.
    echo
    echo "Verifying deployed structure..."

    if [ ! -f "$PROJECT_DIR/attendance_checker.py" ] ||
       [ ! -f "$config_file" ] ||
       [ ! -f "$assets_file" ] ||
       [ ! -d "$PROJECT_DIR/reports" ]; then

        echo "ERROR: Deployment verification failed."
        DEPLOYING=0
        trap - SIGINT SIGTSTP
        return 1
    fi

    echo "Deployment structure verified successfully."

    # Deployment is complete. Disable deployment-only signal traps
    # before starting the Python application.
    DEPLOYING=0
    trap - SIGINT SIGTSTP

    echo
    echo "Deployment completed."
    echo "Now verifying the deployment by running Feature 2..."
    echo

    run_application "$PROJECT_DIR"

    local run_status=$?

    if [ "$run_status" -eq 0 ]; then
        echo
        echo "Deployment verification completed successfully."
    else
        echo
        echo "Deployment was created, but the application did not finish successfully."
    fi

    return "$run_status"
}

# ------------------------------------------------------------
# Feature 2: Run application
# ------------------------------------------------------------

run_feature() {
    echo
    echo "============================================================"
    echo "FEATURE 2: RUN APPLICATION"
    echo "============================================================"

    if ! get_project_name; then
        return 1
    fi

    run_application "$PROJECT_DIR"
}

# ------------------------------------------------------------
# Feature 3: Archive logs
# ------------------------------------------------------------

archive_logs() {
    local attendance_log
    local absent_log
    local attendance_archive_dir
    local absent_archive_dir
    local timestamp
    local attendance_destination
    local absent_destination
    local archived_any=0

    echo
    echo "============================================================"
    echo "FEATURE 3: ARCHIVE LOGS"
    echo "============================================================"

    if ! get_project_name; then
        return 1
    fi

    if [ ! -d "$PROJECT_DIR" ]; then
        echo "ERROR: Project directory does not exist:"
        echo "$PROJECT_DIR"
        return 1
    fi

    if [ ! -d "$PROJECT_DIR/reports" ]; then
        echo "No reports directory found. Nothing to archive."
        return 0
    fi

    attendance_log="$PROJECT_DIR/reports/attendance.log"
    absent_log="$PROJECT_DIR/reports/absent.log"

    # Archive attendance.log if it exists.
    if [ -f "$attendance_log" ]; then
        attendance_archive_dir="$PROJECT_DIR/archives/attendance"
        mkdir -p "$attendance_archive_dir"

        timestamp=$(date +"%Y%m%d_%H%M%S")
        attendance_destination="$attendance_archive_dir/attendance_${timestamp}.log"

        while [ -e "$attendance_destination" ]
        do
            sleep 1
            timestamp=$(date +"%Y%m%d_%H%M%S")
            attendance_destination="$attendance_archive_dir/attendance_${timestamp}.log"
        done

        if cp "$attendance_log" "$attendance_destination"; then
            echo "Attendance log archived:"
            echo "$attendance_destination"
            archived_any=1
        else
            echo "ERROR: Could not archive attendance.log."
        fi
    else
        echo "attendance.log not found. Skipping attendance archive."
    fi

    # Archive absent.log if it exists.
    if [ -f "$absent_log" ]; then
        absent_archive_dir="$PROJECT_DIR/archives/absent"
        mkdir -p "$absent_archive_dir"

        timestamp=$(date +"%Y%m%d_%H%M%S")
        absent_destination="$absent_archive_dir/absent_${timestamp}.log"

        while [ -e "$absent_destination" ]
        do
            sleep 1
            timestamp=$(date +"%Y%m%d_%H%M%S")
            absent_destination="$absent_archive_dir/absent_${timestamp}.log"
        done

        if cp "$absent_log" "$absent_destination"; then
            echo "Absent log archived:"
            echo "$absent_destination"
            archived_any=1
        else
            echo "ERROR: Could not archive absent.log."
        fi
    else
        echo "absent.log not found. Skipping absent archive."
    fi

    if [ "$archived_any" -eq 1 ]; then
        echo
        echo "Log archiving completed."
    else
        echo
        echo "No logs were available to archive."
    fi
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

echo
echo "============================================================"
echo "        ALU DEPLOY AGENT - ATTENDANCE TRACKER"
echo "============================================================"
echo

while true
do
    echo
    echo "Choose a feature:"
    echo "1. Deploy application"
    echo "2. Run application"
    echo "3. Archive logs"
    echo "4. Exit"
    echo

    read -r -p "Enter your choice [1-4]: " choice

    case "$choice" in
        1)
            deploy_application
            ;;

        2)
            run_feature
            ;;

        3)
            archive_logs
            ;;

        4)
            echo "Exiting Deploy Agent. Goodbye!"
            exit 0
            ;;

        *)
            echo "Invalid choice. Please select 1, 2, 3, or 4."
            ;;
    
    
    esac


done
