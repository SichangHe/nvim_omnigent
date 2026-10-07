# Design

(authored by agents unless marked 🧑)

modules in `lua/omnigent/`
- `config`: option table; `setup` overrides it in place
- `api`: async calls; `request` runs `curl` against the server, `amh` runs `amh`
    - `on_done(err, result)` on the main loop; errors are returned, not thrown
- `sidebar`: owns session list, task map, sidebar buffer, refresh timer
    - sessions: `GET /v1/sessions`
    - tasks: `amh agent list`, parsed by `api.parse_tasks`; maps session id to task file
        - no `amh`: map stays empty, everything goes through the server
    - sections copy the web GUI (read from its bundle, `useSidebarData` chunk): `Pinned` by the numeric label `omnigent.pinned`, one per project from `GET /v1/projects` (membership: `project_id` or label `omni_project`), then `Sessions`; newest `updated_at` first; archived hidden
        - the GUI does not group by status; status shows per row instead
    - timer runs only while the sidebar is shown
- `session`: acts on one agent
    - target: `{ session }` or `{ spawn = { name, dir, tool } }`, kept in `b:omnigent_target` of terminal and compose buffers
    - `open`: `GET .../resources/terminals` gives `tmux_socket` and `tmux_target`
        - socket exists here (or `config.attach = "tmux"`): the terminal buffer runs `tmux attach`
        - else `bin/omnigent-attach WS_URL`: stdlib-only Python websocket client; server sends output as binary frames, client sends keys as binary frames and `{"type":"resize"}` text frames on SIGWINCH; URL is `/v1/sessions/ID/resources/terminals/TID/attach` on the server
            - write attach needs the session owner; local mode has no auth
        - a parked agent has no running terminal; a message wakes it
    - `compose`: one `acwrite` buffer per target; `BufWriteCmd` sends, so `:w` works
    - `send`
        - task exists: `amh task edit NAME.md` with `EDITOR=bin/omnigent-append`, which appends the message file to the copy `amh` hands it
            - why not append `(pending)` to the task file directly: that form cannot hold blank lines
        - no task: `POST /v1/sessions/ID/events` with a user message; this route is hidden from the server's API reference
        - spawn target: `amh task start`
    - `reply`: see below
    - `close`: `amh task close NAME.md`, or `amh agent stop omnigent://ID` without a task
- `unwrap`: pure text functions

quoting without terminal line breaks
- problem: harnesses like Claude Code wrap text themselves, so no terminal emulator knows which line breaks are wraps
    - a better terminal cannot fix this; hence no `nvim_better_term`
- `unwrap.locate`: the transcript (`GET .../items`) has the text as written
    - strip whitespace and Markdown marks from selection and transcript, find the selection, map the match back to transcript offsets
    - result keeps the agent's Markdown
- `unwrap.join`: fallback when nothing matches, e.g. tool output
    - a line continues the previous one when its first word would not have fit there; width is the longest selected line
    - list items always start a new line

tests
- `tests/run.lua`: pure checks, then sidebar, terminal and reply against the live server
