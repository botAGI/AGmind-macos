#!/bin/bash
# lib/wizard.sh -- AGMind interactive configuration wizard
# Sourced by install.sh for Phase 2 (Wizard)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Interactive and non-interactive configuration
# Exports: run_wizard (sets WIZARD_* variables)
# Depends on: lib/common.sh (log_info, die), lib/detect.sh (DETECTED_RAM_GB)

set -eEuo pipefail

# =============================================================================
# LLM Model Data (pipe-delimited: "tag|required_ram_gb")
# =============================================================================
# Pipe delimiter avoids conflict with Ollama model tag colons (e.g., qwen2.5:14b)
# Order matters: grouped by RAM tier, first entry per tier is the recommendation.

_LLM_MODELS=(
    "gemma3:4b|8"
    "qwen2.5:3b|8"
    "qwen2.5:7b|16"
    "llama3.1:8b|16"
    "qwen2.5:14b|32"
    "phi-4:14b|32"
    "gemma3:27b|64"
    "qwen2.5:32b|64"
    "qwen2.5:72b|96"
    "llama3.1:70b|96"
)

# =============================================================================
# Embed Model List
# =============================================================================

_EMBED_MODELS=("nomic-embed-text" "bge-m3" "mxbai-embed-large")

# =============================================================================
# _get_recommended_model -- Returns the recommended LLM model tag for given RAM
# =============================================================================
# Usage: _get_recommended_model <ram_gb>
# Returns: Model tag string via echo (e.g., "qwen2.5:14b")
#
# Algorithm: Walk the model array, find the highest RAM tier that fits within
# the system's RAM. Return the first model at that tier.

_get_recommended_model() {
    local ram="$1"
    local best_tag=""
    local best_tier=0
    local i=0

    while [ $i -lt ${#_LLM_MODELS[@]} ]; do
        local entry="${_LLM_MODELS[$i]}"
        local tag="${entry%%|*}"
        local req="${entry##*|}"

        if [ "$ram" -ge "$req" ] && [ "$req" -gt "$best_tier" ]; then
            best_tier="$req"
            best_tag="$tag"
        fi
        i=$((i + 1))
    done

    # Fallback: if nothing matched (shouldn't happen with 8GB minimum), use first model
    if [ -z "$best_tag" ]; then
        local first="${_LLM_MODELS[0]}"
        best_tag="${first%%|*}"
    fi

    echo "$best_tag"
}

# =============================================================================
# _validate_choice -- Validate a value against a list of valid options
# =============================================================================
# Usage: _validate_choice <name> <value> <option1> [option2] ...
# Returns 0 on valid match, calls die() on no match.

_validate_choice() {
    local name="$1"
    local value="$2"
    shift 2
    local v
    for v in "$@"; do
        if [ "$value" = "$v" ]; then
            return 0
        fi
    done
    die "Invalid ${name}: '${value}'" "Valid options: $*"
}

# =============================================================================
# _wizard_ask -- Generic numbered menu prompt
# =============================================================================
# Usage: _wizard_ask <prompt> <default_num> <option1> [option2] ...
# Reads numbered input from stdin, returns selected option value via echo.
# Empty input selects default. Invalid input re-prompts.

_wizard_ask() {
    local prompt="$1"
    local default_num="$2"
    shift 2
    local options=("$@")
    local count=${#options[@]}
    local choice=""

    while true; do
        printf "\n%s\n" "$prompt"
        local i=0
        while [ $i -lt $count ]; do
            local num=$((i + 1))
            local marker=""
            if [ "$num" -eq "$default_num" ]; then
                marker=" (default)"
            fi
            printf "  [%d] %s%s\n" "$num" "${options[$i]}" "$marker"
            i=$((i + 1))
        done
        printf "Choice [%d]: " "$default_num"
        read -r choice
        if [ -z "$choice" ]; then
            choice="$default_num"
        fi
        # Validate: must be integer 1..count
        case "$choice" in
            [0-9]*)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ]; then
                    echo "${options[$((choice - 1))]}"
                    return 0
                fi
                ;;
        esac
        printf "Invalid choice. Please enter 1-%d:\n" "$count"
    done
}

# =============================================================================
# Interactive Ask Functions (7 questions)
# =============================================================================

# Question 1: Deploy profile
_wizard_ask_profile() {
    local result
    result=$(_wizard_ask \
        "Deploy profile:
  lan     -- Local network access, no TLS
  offline -- Air-gapped, no internet required" \
        1 "lan" "offline")
    echo "$result"
}

# Question 2: LLM model (special menu with RAM annotations)
_wizard_ask_llm_model() {
    local ram="${DETECTED_RAM_GB:-32}"
    local recommended
    recommended=$(_get_recommended_model "$ram")

    local count=${#_LLM_MODELS[@]}
    local recommended_num=1
    local choice=""

    # Find the 1-indexed number of the recommended model
    local i=0
    while [ $i -lt $count ]; do
        local entry="${_LLM_MODELS[$i]}"
        local tag="${entry%%|*}"
        if [ "$tag" = "$recommended" ]; then
            recommended_num=$((i + 1))
            break
        fi
        i=$((i + 1))
    done

    while true; do
        printf "\nLLM model (your system has %dGB unified memory):\n" "$ram"
        i=0
        while [ $i -lt $count ]; do
            local entry="${_LLM_MODELS[$i]}"
            local tag="${entry%%|*}"
            local req="${entry##*|}"
            local num=$((i + 1))
            local annotation=""

            if [ "$tag" = "$recommended" ]; then
                annotation=" * (recommended for your ${ram}GB)"
            elif [ "$req" -gt "$ram" ]; then
                annotation=" (requires ${req}GB+, you have ${ram}GB)"
            fi

            printf "  [%d] %s%s\n" "$num" "$tag" "$annotation"
            i=$((i + 1))
        done
        printf "Choice [%d]: " "$recommended_num"
        read -r choice
        if [ -z "$choice" ]; then
            choice="$recommended_num"
        fi
        # Validate: must be integer 1..count
        case "$choice" in
            [0-9]*)
                if [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$count" ]; then
                    local selected="${_LLM_MODELS[$((choice - 1))]}"
                    echo "${selected%%|*}"
                    return 0
                fi
                ;;
        esac
        printf "Invalid choice. Please enter 1-%d:\n" "$count"
    done
}

# Question 3: Embed model
_wizard_ask_embed_model() {
    local result
    result=$(_wizard_ask \
        "Embedding model:
  nomic-embed-text  -- General purpose, good quality/speed balance
  bge-m3            -- Multilingual, strong retrieval performance
  mxbai-embed-large -- High quality, larger model size" \
        1 "nomic-embed-text" "bge-m3" "mxbai-embed-large")
    echo "$result"
}

# Question 4: Vector database
_wizard_ask_vector_db() {
    local result
    result=$(_wizard_ask \
        "Vector database:
  weaviate -- Full-featured, built-in hybrid search
  qdrant   -- Lightweight, fast, simple API" \
        1 "weaviate" "qdrant")
    echo "$result"
}

# Question 5: ETL mode
_wizard_ask_etl_mode() {
    local result
    result=$(_wizard_ask \
        "ETL mode:
  standard -- Core document types (PDF, DOCX, TXT, CSV)
  extended -- Additional parsers for code, HTML, markdown, images" \
        1 "standard" "extended")
    echo "$result"
}

# Question 6: Monitoring
_wizard_ask_monitoring() {
    local result
    result=$(_wizard_ask \
        "Monitoring:
  none  -- No monitoring stack (saves resources)
  local -- Grafana + Prometheus + Portainer dashboards" \
        1 "none" "local")
    echo "$result"
}

# Question 7: Backup mode
_wizard_ask_backup() {
    local result
    result=$(_wizard_ask \
        "Backup mode:
  local  -- Backups stored on this machine
  remote -- Backups synced to remote destination" \
        1 "local" "remote")
    echo "$result"
}

# =============================================================================
# _wizard_non_interactive -- Read all choices from env vars with defaults
# =============================================================================
# Called when NON_INTERACTIVE=1. Validates all choices, dies on invalid values.

_wizard_non_interactive() {
    WIZARD_DEPLOY_PROFILE="${DEPLOY_PROFILE:-lan}"
    _validate_choice "DEPLOY_PROFILE" "$WIZARD_DEPLOY_PROFILE" "lan" "offline"
    log_info "Deploy profile: ${WIZARD_DEPLOY_PROFILE}"

    WIZARD_LLM_MODEL="${LLM_MODEL:-$(_get_recommended_model "${DETECTED_RAM_GB:-32}")}"
    # LLM model: any string accepted (user may specify custom tag)
    log_info "LLM model: ${WIZARD_LLM_MODEL}"

    WIZARD_EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"
    _validate_choice "EMBED_MODEL" "$WIZARD_EMBED_MODEL" \
        "nomic-embed-text" "bge-m3" "mxbai-embed-large"
    log_info "Embed model: ${WIZARD_EMBED_MODEL}"

    WIZARD_VECTOR_DB="${VECTOR_DB:-weaviate}"
    _validate_choice "VECTOR_DB" "$WIZARD_VECTOR_DB" "weaviate" "qdrant"
    log_info "Vector DB: ${WIZARD_VECTOR_DB}"

    WIZARD_ETL_MODE="${ETL_MODE:-standard}"
    _validate_choice "ETL_MODE" "$WIZARD_ETL_MODE" "standard" "extended"
    log_info "ETL mode: ${WIZARD_ETL_MODE}"

    WIZARD_MONITORING_MODE="${MONITORING_MODE:-none}"
    _validate_choice "MONITORING_MODE" "$WIZARD_MONITORING_MODE" "none" "local"
    log_info "Monitoring: ${WIZARD_MONITORING_MODE}"

    WIZARD_BACKUP_MODE="${BACKUP_MODE:-local}"
    _validate_choice "BACKUP_MODE" "$WIZARD_BACKUP_MODE" "local" "remote"
    log_info "Backup mode: ${WIZARD_BACKUP_MODE}"

    export WIZARD_DEPLOY_PROFILE WIZARD_LLM_MODEL WIZARD_EMBED_MODEL
    export WIZARD_VECTOR_DB WIZARD_ETL_MODE WIZARD_MONITORING_MODE WIZARD_BACKUP_MODE
}

# =============================================================================
# run_wizard -- Main entry point
# =============================================================================
# If NON_INTERACTIVE=1: reads from env vars with sensible defaults
# Otherwise: presents 7 interactive menus in fixed order

run_wizard() {
    if [ "${NON_INTERACTIVE:-0}" = "1" ]; then
        log_info "Non-interactive mode: reading configuration from environment"
        _wizard_non_interactive
    else
        log_info "Starting interactive configuration wizard..."

        WIZARD_DEPLOY_PROFILE=$(_wizard_ask_profile)
        log_info "Deploy profile: ${WIZARD_DEPLOY_PROFILE}"

        WIZARD_LLM_MODEL=$(_wizard_ask_llm_model)
        log_info "LLM model: ${WIZARD_LLM_MODEL}"

        WIZARD_EMBED_MODEL=$(_wizard_ask_embed_model)
        log_info "Embed model: ${WIZARD_EMBED_MODEL}"

        WIZARD_VECTOR_DB=$(_wizard_ask_vector_db)
        log_info "Vector DB: ${WIZARD_VECTOR_DB}"

        WIZARD_ETL_MODE=$(_wizard_ask_etl_mode)
        log_info "ETL mode: ${WIZARD_ETL_MODE}"

        WIZARD_MONITORING_MODE=$(_wizard_ask_monitoring)
        log_info "Monitoring: ${WIZARD_MONITORING_MODE}"

        WIZARD_BACKUP_MODE=$(_wizard_ask_backup)
        log_info "Backup mode: ${WIZARD_BACKUP_MODE}"

        export WIZARD_DEPLOY_PROFILE WIZARD_LLM_MODEL WIZARD_EMBED_MODEL
        export WIZARD_VECTOR_DB WIZARD_ETL_MODE WIZARD_MONITORING_MODE WIZARD_BACKUP_MODE
    fi

    # Log summary
    log_info "Configuration summary:"
    log_info "  Profile:    ${WIZARD_DEPLOY_PROFILE}"
    log_info "  LLM:        ${WIZARD_LLM_MODEL}"
    log_info "  Embedding:  ${WIZARD_EMBED_MODEL}"
    log_info "  Vector DB:  ${WIZARD_VECTOR_DB}"
    log_info "  ETL:        ${WIZARD_ETL_MODE}"
    log_info "  Monitoring: ${WIZARD_MONITORING_MODE}"
    log_info "  Backup:     ${WIZARD_BACKUP_MODE}"
}
