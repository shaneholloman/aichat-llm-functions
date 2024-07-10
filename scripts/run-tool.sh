#!/usr/bin/env bash
set -e

main() {
    root_dir="$(cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd)"
    self_name=run-tool.sh
    parse_argv "$@"
    setup_env
    tool_path="$root_dir/tools/$tool_name.sh"
    run 
}

parse_argv() {
    if [[ "$0" == *"$self_name" ]]; then
        tool_name="$1"
        tool_data="$2"
    else
        tool_name="$(basename "$0")"
        tool_data="$1"
    fi
    if [[ "$tool_name" == *.sh ]]; then
        tool_name="${tool_name:0:$((${#tool_name}-3))}"
    fi
}

setup_env() {
    load_env "$root_dir/.env" 
    export LLM_ROOT_DIR="$root_dir"
    export LLM_TOOL_NAME="$tool_name"
    export LLM_TOOL_CACHE_DIR="$LLM_ROOT_DIR/cache/$tool_name"
}

load_env() {
    local env_file="$1" env_vars
    if [[ -f "$env_file" ]]; then
        while IFS='=' read -r key value; do
            if [[ "$key" == $'#'* ]] || [[ -z "$key" ]]; then
                continue
            fi
            if [[ -z "${!key+x}" ]]; then
                env_vars="$env_vars $key=$value"
            fi
        done < "$env_file"
        if [[ -n "$env_vars" ]]; then
            eval "export $env_vars"
        fi
    fi
}

run() {
    if [[ -z "$tool_data" ]]; then
        die "No JSON data"
    fi

    if [[ "$OS" == "Windows_NT" ]]; then
        set -o igncr
        tool_path="$(cygpath -w "$tool_path")"
    fi

    data="$(
        echo "$tool_data" | \
        jq -r '
        to_entries | .[] | 
        (.key | split("_") | join("-")) as $key |
        if .value | type == "array" then
            .value | .[] | "--\($key)\n\(. | @json)"
        elif .value | type == "boolean" then
            if .value then "--\($key)" else "" end
        else
            "--\($key)\n\(.value | @json)"
        end'
    )" || {
        die "Invalid JSON data"
    }
    while IFS= read -r line; do
        if [[ "$line" == '--'* ]]; then
            args+=("$line")
        else
            args+=("$(echo "$line" | jq -r '.')")
        fi
    done <<< "$data"
    no_llm_output=0
    if [[ -z "$LLM_OUTPUT" ]]; then
        no_llm_output=1
        export LLM_OUTPUT="$(mktemp)"
    fi
    "$tool_path" "${args[@]}"
    if [[ "$no_llm_output" -eq 1 ]]; then
        cat "$LLM_OUTPUT"
    fi
}

die() {
    echo "$*" >&2
    exit 1
}

main "$@"
