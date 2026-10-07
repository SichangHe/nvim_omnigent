--- Acting on one agent: its terminal, the compose buffer, starting and closing.
local api = require("omnigent.api")
local config = require("omnigent.config")
local sidebar = require("omnigent.sidebar")
local unwrap = require("omnigent.unwrap")

local M = {
    --- Session id to its terminal buffer.
    terminals = {},
    --- Target key to its compose buffer.
    composers = {},
}

local BIN = vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "../../bin")
local APPEND = vim.fs.joinpath(BIN, "omnigent-append")
local ATTACH = vim.fs.joinpath(BIN, "omnigent-attach")

local function fail(err)
    vim.notify("omnigent: " .. err, vim.log.levels.ERROR)
end

--- The target of the current buffer: `{ session = ... }` for an existing agent,
--- `{ spawn = { name, dir, tool } }` for one about to start, or `nil`.
local function current_target()
    if vim.b.omnigent_target then
        return vim.b.omnigent_target
    end
    local at_cursor = vim.bo.filetype == "omnigent" and sidebar.session_at_cursor()
    return at_cursor and { session = at_cursor } or nil
end

--- A window showing neither the sidebar nor a compose buffer; made when missing.
local function main_window()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].filetype ~= "omnigent" and vim.bo[buf].buftype ~= "acwrite" then
            return win
        end
    end
    vim.cmd("botright vertical split")
    return vim.api.nvim_get_current_win()
end

-- 🧑 "main window be the underlying harness"
--- Show the agent's own terminal by attaching to its tmux session.
function M.open(session)
    local buf = M.terminals[session.id]
    if buf and vim.api.nvim_buf_is_valid(buf) then
        local win = main_window()
        vim.api.nvim_win_set_buf(win, buf)
        return vim.api.nvim_set_current_win(win)
    end
    api.request(config.server, "GET", "/v1/sessions/" .. session.id .. "/resources/terminals", nil, function(err, reply)
        if err then
            return fail(err)
        end
        local terminal = vim.iter(reply.data):find(function(resource)
            return resource.metadata.running
        end)
        if not terminal then
            return vim.notify(("omnigent: %s has no running terminal; send it a message to wake it"):format(session.title), vim.log.levels.WARN)
        end
        buf = vim.api.nvim_create_buf(true, false)
        local win = main_window()
        vim.api.nvim_win_set_buf(win, buf)
        vim.api.nvim_set_current_win(win)
        -- 🧑 "Make both work": tmux when its socket is on this machine, else the server's websocket
        local socket = terminal.metadata.tmux_socket
        local cmd
        if config.attach == "tmux" or config.attach == "auto" and socket and vim.uv.fs_stat(socket) then
            cmd = { "env", "-u", "TMUX", "tmux", "-S", socket, "attach", "-t", terminal.metadata.tmux_target }
        else
            local ws = config.server:gsub("^http", "ws") .. "/v1/sessions/" .. session.id .. "/resources/terminals/" .. terminal.id .. "/attach"
            cmd = { config.python, ATTACH, ws }
        end
        vim.fn.jobstart(cmd, {
            term = true,
            on_exit = function()
                M.terminals[session.id] = nil
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_delete(buf, { force = true })
                end
            end,
        })
        M.terminals[session.id] = buf
        vim.b[buf].omnigent_target = { session = session }
        vim.keymap.set("n", "<CR>", M.compose, { buffer = buf, desc = "Write a message to the agent" })
        vim.keymap.set("x", "<CR>", M.reply, { buffer = buf, desc = "Quote the selection in a message" })
    end)
end

local function target_title(target)
    return target.session and (target.session.title or target.session.id) or target.spawn.name
end

-- 🧑 "Should have a normal mode for editing what to send to agents"
--- Open the compose buffer of `target` (default: the current buffer's agent),
--- appending `lines` to it. Writing the buffer sends it.
function M.compose(target, lines)
    target = target or current_target()
    if not target then
        return fail("no agent here; pick one in the sidebar")
    end
    local key = target.session and target.session.id or target.spawn.name
    local buf = M.composers[key]
    if not (buf and vim.api.nvim_buf_is_valid(buf)) then
        buf = vim.api.nvim_create_buf(false, false)
        M.composers[key] = buf
        vim.api.nvim_buf_set_name(buf, "omnigent-compose://" .. target_title(target))
        vim.bo[buf].buftype = "acwrite"
        vim.bo[buf].swapfile = false
        vim.bo[buf].filetype = "markdown"
        vim.b[buf].omnigent_target = target
        vim.api.nvim_create_autocmd("BufWriteCmd", { buffer = buf, callback = M.send })
        vim.keymap.set("n", "<CR>", M.send, { buffer = buf, desc = "Send to the agent" })
    end
    local win = vim.fn.bufwinid(buf)
    if win == -1 then
        vim.api.nvim_set_current_win(main_window())
        vim.cmd(("belowright %dsplit"):format(config.compose_height))
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
    end
    vim.api.nvim_set_current_win(win)
    if lines then
        local empty = vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
        vim.api.nvim_buf_set_lines(buf, empty and 0 or -1, -1, false, lines)
    end
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
end

--- Deliver `text` to the agent of `session`.
--- An agent that has an `amh` task gets it appended to its task file; others get it from the server.
local function deliver(session, text, on_done)
    local task = sidebar.tasks[session.id]
    if not task then
        local message = { type = "message", data = { role = "user", content = { { type = "input_text", text = text } } } }
        return api.request(config.server, "POST", "/v1/sessions/" .. session.id .. "/events", message, on_done)
    end
    -- 🧑 "also support using amh: sending messages to agents by editing the task file etc."
    local message_file = vim.fn.tempname()
    vim.fn.writefile(vim.split(text, "\n"), message_file)
    api.amh(config.amh, { "task", "edit", task.name }, { EDITOR = APPEND, VISUAL = APPEND, OMNIGENT_MESSAGE = message_file }, function(err)
        vim.fn.delete(message_file)
        on_done(err)
    end)
end

-- 🧑 "ability to spawn/close agents"
local function start(spawn, text, on_done)
    local prompt_file = vim.fn.tempname()
    vim.fn.writefile(vim.split(text, "\n"), prompt_file)
    api.amh(config.amh, { "task", "start", spawn.name, "--dir", spawn.dir, "--prompt", prompt_file, "--tool", spawn.tool }, nil, function(err)
        vim.fn.delete(prompt_file)
        on_done(err)
    end)
end

--- Send the current compose buffer, then empty it.
function M.send()
    local buf = vim.api.nvim_get_current_buf()
    local target = vim.b[buf].omnigent_target
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    if text == "" then
        return fail("nothing to send")
    end
    if vim.b[buf].omnigent_sending then
        return fail("still sending")
    end
    vim.b[buf].omnigent_sending = true
    local function sent(err)
        vim.b[buf].omnigent_sending = false
        if err then
            return fail(err)
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
        vim.bo[buf].modified = false
        vim.notify("omnigent: sent to " .. target_title(target))
        if target.spawn then
            vim.api.nvim_buf_delete(buf, { force = true })
            sidebar.refresh()
        end
    end
    if target.spawn then
        start(target.spawn, text, sent)
    else
        deliver(target.session, text, sent)
    end
end

--- Quote the visual selection into the agent's compose buffer.
--- Terminal text is replaced by the transcript passage it shows, when one matches,
--- so the quote has the agent's own line breaks.
function M.reply()
    local target = current_target()
    if not target then
        return fail("no agent here; pick one in the sidebar")
    end
    local selection = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
    local from_terminal = vim.bo.buftype == "terminal"
    vim.cmd.normal({ vim.keycode("<Esc>"), bang = true })
    if not (from_terminal and target.session) then
        return M.compose(target, unwrap.quote(selection))
    end
    api.request(config.server, "GET", "/v1/sessions/" .. target.session.id .. "/items?order=desc&limit=200", nil, function(_, reply)
        local sources = {}
        for _, item in ipairs(reply and reply.data or {}) do
            for _, part in ipairs(item.type == "message" and item.content or {}) do
                sources[#sources + 1] = part.text
            end
        end
        local passage = unwrap.locate(table.concat(selection, "\n"), sources)
        M.compose(target, unwrap.quote(passage and vim.split(passage, "\n") or unwrap.join(selection)))
    end)
end

--- Ask for a task name, directory and tool, then open a compose buffer for the goal.
function M.spawn()
    vim.ui.input({ prompt = "New task name: " }, function(name)
        if not name or name == "" then
            return
        end
        name = name:gsub("%.md$", "") .. ".md"
        vim.ui.input({ prompt = "Directory: ", default = vim.fn.getcwd(), completion = "dir" }, function(dir)
            if not dir or dir == "" then
                return
            end
            vim.ui.select(config.tools, { prompt = "Tool" }, function(tool)
                if tool then
                    M.compose({ spawn = { name = name, dir = vim.fn.expand(dir), tool = tool } })
                end
            end)
        end)
    end)
end

--- Close the agent of `session` (default: the current buffer's agent) after confirmation.
function M.close(session)
    local target = session and { session = session } or current_target()
    if not (target and target.session) then
        return fail("no agent here; pick one in the sidebar")
    end
    session = target.session
    if vim.fn.confirm("Close agent " .. target_title(target) .. "?", "&Yes\n&No", 2) ~= 1 then
        return
    end
    local task = sidebar.tasks[session.id]
    local args = task and { "task", "close", task.name } or { "agent", "stop", "omnigent://" .. session.id }
    api.amh(config.amh, args, nil, function(err)
        if err then
            return fail(err)
        end
        sidebar.refresh()
    end)
end

return M
