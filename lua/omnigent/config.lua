--- Options; `require("omnigent").setup` overrides them in place.
return {
    --- Omnigent server URL.
    server = "http://localhost:6767",
    --- Sidebar refresh period.
    refresh_ms = 5000,
    sidebar_width = 36,
    compose_height = 10,
    --- How to show an agent's terminal: `auto` uses tmux when its socket is on this machine,
    --- else the server's websocket; `tmux` or `websocket` forces one.
    attach = "auto",
    --- Python 3 for the websocket attach; only the standard library is used.
    python = "python3",
    --- The `amh` command.
    amh = "amh",
    --- Tools offered when starting an agent; the first is the default.
    tools = { "claude", "codex", "cursor", "antigravity" },
    --- Global mappings; set one to `false` to skip it.
    keys = {
        toggle = "<leader>oo",
        new = "<leader>on",
        compose = "<leader>om",
        reply = "<leader>or",
    },
}
