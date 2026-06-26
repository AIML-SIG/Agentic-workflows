#!/bin/bash
# Modus outer loop: spawns fresh agent instances until every task passes.
#
# Modus does not replace your agent harness -- it wraps one. The agent command
# is configurable via AGENT_CMD so the same loop drives Claude Code, Codex, or
# any CLI agent that accepts a prompt as its final argument.

# =============================================================================
# PROJECT DIRECTORY - Must contain a /data subdirectory (workspace is created)
# =============================================================================
# Usage: ./run.sh /path/to/project_directory

PROJECT_DIR="$1"

if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory required"
    echo "Usage: $0 <project_directory>"
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory does not exist: $PROJECT_DIR"
    exit 1
fi

# =============================================================================
# Settings (override via environment)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_DOCS_DIR="${SCRIPT_DIR}/ai_docs"           # prompt, task library, escalation prompt
EXAMPLES_DIR="${EXAMPLES_DIR:-${SCRIPT_DIR}/examples}"  # domain example library
MAX_ITERATIONS="${MAX_ITERATIONS:-50}"
TASK_TIMEOUT="${TASK_TIMEOUT:-3300}"          # seconds per task (default 55 min)
UNATTENDED="${UNATTENDED:-true}"              # auto-review escalations vs. halt
TASK_LIBRARY="${TASK_LIBRARY:-${AI_DOCS_DIR}/task_library.json}"

# The agent harness, as a command prefix. The prompt text is appended as the
# final argument at call time (passed directly as argv, never re-parsed by a
# shell -- so prompts may safely contain quotes, backticks, etc.).
# Default targets Claude Code; swap for codex, etc. without touching the loop.
#   Codex example: AGENT_CMD='codex exec'
#
# --dangerously-skip-permissions is required, not optional, for this loop: each
# agent runs headless (claude -p) with no human to answer permission prompts, so
# without it every file read/write outside the cwd deadlocks and the iteration
# does nothing. This is the "full filesystem access, no approval prompts" mode
# the README's safety note describes -- run the loop in a sandbox you trust.
#
# Add --bare to AGENT_CMD to skip hooks, LSP, and plugins (faster agents, no
# host config leakage). Required if using API-key auth instead of OAuth.
AGENT_CMD="${AGENT_CMD:-claude -p --verbose --output-format stream-json --dangerously-skip-permissions}"

LOG_FILE="${PROJECT_DIR}/run_$(date +%Y%m%d_%H%M%S).log"
RUNNING=true
RUN_LABEL="${RUN_LABEL:-modus_run_$(date +%Y%m%d_%H%M%S)}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Graceful shutdown handler - kill child processes too
cleanup() {
    log "Received shutdown signal, stopping gracefully..."
    RUNNING=false
    pkill -P $$ 2>/dev/null
    archive_workspace "cancelled"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Archive workspace: move logs in, rename, and commit
archive_workspace() {
    local status="$1"  # "complete", "incomplete", or "cancelled"
    local new_name="${RUN_LABEL}_workspace"
    [ "$status" != "complete" ] && new_name="${new_name}_${status}"
    log "Archiving workspace as ${new_name}"
    mv "${PROJECT_DIR}"/run_*.log "${PROJECT_DIR}/workspace/" 2>/dev/null
    mv "${PROJECT_DIR}/workspace" "${PROJECT_DIR}/${new_name}"
    (cd "$SCRIPT_DIR" && git add -A "${PROJECT_DIR}/" && git commit -m "${new_name}: ${status}") 2>/dev/null
}

# Run the configured agent with a prompt file, substituting the project dir.
# AGENT_CMD is word-split into argv; the prompt is appended as the final arg.
run_agent() {
    local prompt_file="$1"
    local prompt_text
    prompt_text=$(sed -e "s|{{PROJECT_DIR}}|$PROJECT_DIR|g" \
                      -e "s|{{EXAMPLES_DIR}}|$EXAMPLES_DIR|g" "$prompt_file")
    timeout --foreground "$TASK_TIMEOUT" $AGENT_CMD "$prompt_text" >> "$LOG_FILE" 2>&1
}

# Initialize the working copy from the full task library. The home library
# (task_library.json) is the complete, pristine set; the workspace copy
# (tasks.json) is what the scope task prunes to this study's active subset.
mkdir -p "${PROJECT_DIR}/workspace"
if [ ! -f "${PROJECT_DIR}/workspace/tasks.json" ]; then
    if [ ! -f "$TASK_LIBRARY" ]; then
        echo "ERROR: Task library not found: $TASK_LIBRARY"
        echo "Set TASK_LIBRARY=/path/to/task_library.json"
        exit 1
    fi
    cp "$TASK_LIBRARY" "${PROJECT_DIR}/workspace/tasks.json"
    log "Initialized ${PROJECT_DIR}/workspace/tasks.json from ${TASK_LIBRARY}"
fi

log "Starting Modus workflow (max $MAX_ITERATIONS iterations)"
log "Project directory: $PROJECT_DIR"
log "Task library: $TASK_LIBRARY"
log "Log file: $LOG_FILE"

for i in $(seq 1 "$MAX_ITERATIONS"); do
    if ! $RUNNING; then
        log "Stopping..."
        break
    fi

    log "=== Iteration $i/$MAX_ITERATIONS ==="

    # Spawn a fresh agent. It selects one task, executes it, and exits.
    run_agent "${AI_DOCS_DIR}/prompt.md"

    # Check for escalation (human input needed)
    if [ -f "${PROJECT_DIR}/workspace/ESCALATE.txt" ]; then
        if [ "$UNATTENDED" = "true" ]; then
            log "ESCALATION (unattended): $(cat "${PROJECT_DIR}/workspace/ESCALATE.txt")"
            log "Dispatching auto-review..."
            run_agent "${AI_DOCS_DIR}/escalation_review_prompt.md"
        else
            log "ESCALATION: Agent requests human input. See ESCALATE.txt for details."
            exit 1
        fi
    fi

    # Check completion
    if [ -f "${PROJECT_DIR}/workspace/ANALYSIS_COMPLETE.txt" ]; then
        log "All tasks complete."
        archive_workspace "complete"
        exit 0
    fi

    log "Iteration $i complete, pausing before next..."
    sleep 5
done

log "Max iterations reached. Check tasks.json for status."
archive_workspace "incomplete"
exit 1
