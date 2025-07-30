#!/bin/bash

# Check for help flag
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: ./claude.sh [OPTIONS]"
    echo ""
    echo "Run Claude Code in a devcontainer environment."
    echo ""
    echo "Options:"
    echo "  --help, -h                    Show this help message"
    echo "  --dangerously-skip-permissions  Skip permission checks"
    echo ""
    echo "All other arguments are passed directly to the claude command."
    echo ""
    echo "Examples:"
    echo "  ./claude.sh                           # Run with default settings"
    echo "  ./claude.sh --dangerously-skip-permissions  # Skip permission checks"
    echo "  ./claude.sh -c  # Pass any args that you can use with Claude Code"
    exit 0
fi

devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . claude "$@"
