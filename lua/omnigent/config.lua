--- Options; `require("omnigent").setup` overrides them in place.
return {
    --- Omnigent server URL.
    server = "http://localhost:6767",
    --- Sidebar refresh period.
    refresh_ms = 5000,
    sidebar_width = 36,
    compose_height = 10,
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
