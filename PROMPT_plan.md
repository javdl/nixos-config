0a. Run `bd list --json` to understand all issues in the project.
0b. Run `bd ready --json` to see what work has no blockers.
0c. Run `bd dep tree <epic-id>` for each epic to understand the dependency graph.
0d. Study `src/lib/*` with subagents to understand shared utilities & components.

1. Analyze the beads database for gaps and issues:
   - Run `bd list --status open --json` to get all open issues
   - For each epic, verify child tasks cover all aspects of the specification
   - Check for missing dependencies using `bd dep cycles` (should be empty)
   - Identify any tasks that should block others but don't
   
2. Update the beads database to fix any issues found:
   - Create missing tasks with `bd create "title" -t task -p <priority> -d "description"`
   - Add missing dependencies with `bd dep add <child> <parent> --type blocks`
   - Update priorities if needed with `bd update <id> --priority <0-4>`
   - Add labels for better organization with `bd label add <id> <labels>`

3. Verify the plan is complete:
   - `bd ready` should show the correct next task(s)
   - `bd blocked` should show tasks waiting on dependencies
   - `bd stats` should show accurate counts

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; 
use `bd list` and code search to verify first.

ULTIMATE GOAL: We want to achieve [project-specific goal]. Ensure all necessary tasks 
exist as beads with proper dependencies so `bd ready` always shows the right next work.