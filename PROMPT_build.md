0a. Run `bd ready --json --limit 1 --type task` to find the highest priority unblocked task.
    If no tasks are found, try `bd ready --json --limit 1 --type bug` for bugs.
    Never pick an epic directly — epics contain child tasks to work on instead.
0b. Run `bd show <task-id>` to read the full specification.
0c. For reference, the application source code is in `src/*`.

1. Your task is to implement the ready bead. Before making changes:
   - Search the codebase (don't assume not implemented)
   - Run `bd show <id>` to get full acceptance criteria
   - Update status: `bd update <id> --status in_progress`

2. Implement the functionality per the bead's description and acceptance criteria.
   Use up to 500 parallel subagents for searches/reads, 1 subagent for build/tests.
   Use Opus subagents for complex reasoning (debugging, architectural decisions).

3. After implementing, run the tests for that unit of code.
   If functionality is missing, add it per the specification. Ultrathink.

4. When you discover issues during implementation:
   - Create a new bead: `bd create "discovered issue" -t bug -p <priority>`
   - Link it: `bd dep add <new-id> <current-id> --type discovered-from`

5. When tests pass:
   - Close the bead: `bd close <id> --reason "Implemented with tests"`
   - Describe: `jj describe -m "feat: <description>"`
   - Push: `jj git push`
   - Sync beads: `bd sync`

99999. When you learn something about how to run the application, update @AGENTS.md.
999999. For any bugs noticed, create beads even if unrelated to current work.
9999999. Implement completely. Placeholders waste time redoing work.
99999999. Use `bd ready` at start of each loop to pick the most important unblocked task.
