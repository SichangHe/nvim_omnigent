--- Entry point: options, the `:Omnigent` command, and global mappings.
local config = require("omnigent.config")

local M = {}

--- What `:Omnigent NAME` and `config.keys.NAME` run.
local function actions()
    local session, sidebar = require("omnigent.session"), require("omnigent.sidebar")
    return {
        toggle = sidebar.toggle,
        new = session.spawn,
        compose = function()
            session.compose()
        end,
        reply = session.reply,
        close = function()
            session.close()
        end,
    }
end

--- Merge `opts` into the options, then define the command and mappings.
function M.setup(opts)
    for key, value in pairs(vim.tbl_deep_extend("force", config, opts or {})) do
        config[key] = value
    end
    local run = actions()
    vim.api.nvim_create_user_command("Omnigent", function(command)
        local action = run[command.args ~= "" and command.args or "toggle"]
        if not action then
            return vim.notify("omnigent: no such action: " .. command.args, vim.log.levels.ERROR)
        end
        action()
    end, {
        nargs = "?",
        range = true,
        complete = function()
            return vim.tbl_keys(run)
        end,
    })
    local modes = { reply = "x" }
    for name, lhs in pairs(config.keys) do
        if lhs then
            vim.keymap.set(modes[name] or "n", lhs, run[name], { desc = "Omnigent: " .. name })
        end
    end
end

return M
