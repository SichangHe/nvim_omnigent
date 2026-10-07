--- The session list: owns the sidebar buffer, the sessions, and their `amh` tasks.
local api = require("omnigent.api")
local config = require("omnigent.config")

--- Session label the web GUI sets when pinning; its value orders the pinned section.
local PIN_LABEL = "omnigent.pinned"

local M = {
    buf = nil,
    timer = nil,
    --- Sessions as the server lists them.
    sessions = {},
    --- Projects as the server lists them.
    projects = {},
    --- Session id to `{ name, status }` of its `amh` task.
    tasks = {},
    --- Sidebar line number to the session shown there.
    rows = {},
}

local function window()
    if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
        return nil
    end
    local win = vim.fn.bufwinid(M.buf)
    return win ~= -1 and win or nil
end

--- The session on the cursor line of the sidebar, or `nil`.
function M.session_at_cursor()
    local win = window()
    return win and M.rows[vim.api.nvim_win_get_cursor(win)[1]]
end

-- 🧑 "sessions sorted by status in toggleable sidebar" ... "see exactly what they have instead of guessing"
--- The sections of the web GUI: `Pinned` in pin order, one per project, then `Sessions`;
--- newest `updated_at` first inside each; archived sessions hidden.
local function sections()
    local pinned, by_project, rest = {}, {}, {}
    for _, session in ipairs(M.sessions) do
        local labels = session.labels or {}
        local project = vim.iter(M.projects):find(function(candidate)
            return session.project_id == candidate.id or labels.omni_project == candidate.name
        end)
        if session.archived then
        elseif tonumber(labels[PIN_LABEL]) then
            pinned[#pinned + 1] = session
        elseif project then
            by_project[project.name] = by_project[project.name] or {}
            table.insert(by_project[project.name], session)
        else
            rest[#rest + 1] = session
        end
    end
    local function newest_first(list)
        table.sort(list, function(a, b)
            return a.updated_at > b.updated_at
        end)
        return list
    end
    table.sort(pinned, function(a, b)
        return tonumber(a.labels[PIN_LABEL]) < tonumber(b.labels[PIN_LABEL])
    end)
    local out = { { title = "Pinned", sessions = pinned } }
    for _, project in ipairs(M.projects) do
        out[#out + 1] = { title = project.name, sessions = newest_first(by_project[project.name] or {}) }
    end
    out[#out + 1] = { title = "Sessions", sessions = newest_first(rest) }
    return out
end

local function render()
    local win = window()
    if not win then
        return
    end
    local at_cursor = M.session_at_cursor()
    local lines, rows, cursor_line = {}, {}, nil
    for _, section in ipairs(sections()) do
        if #section.sessions > 0 then
            lines[#lines + 1] = ("%s (%d)"):format(section.title, #section.sessions)
            for _, session in ipairs(section.sessions) do
                local task = M.tasks[session.id]
                lines[#lines + 1] = (session.viewer_unread and " ● " or "   ")
                    .. (session.title or session.id)
                    .. " [" .. (session.status or "?") .. (task and ", " .. task.status or "") .. "]"
                rows[#lines] = session
                if at_cursor and at_cursor.id == session.id then
                    cursor_line = #lines
                end
            end
        end
    end
    M.rows = rows
    vim.bo[M.buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    vim.bo[M.buf].modifiable = false
    if cursor_line then
        vim.api.nvim_win_set_cursor(win, { cursor_line, 0 })
    end
end

--- Fetch sessions and tasks again, then redraw. Stops the timer once the sidebar is gone.
function M.refresh()
    if not window() then
        return M.timer:stop()
    end
    api.request(config.server, "GET", "/v1/sessions?limit=1000&sort_by=updated_at&order=desc&kind=default&visibility=all&include_archived=false", nil, function(err, reply)
        if err then
            return vim.notify("omnigent: " .. err, vim.log.levels.ERROR)
        end
        M.sessions = reply.data
        render()
    end)
    api.request(config.server, "GET", "/v1/projects", nil, function(err, reply)
        if not err then
            M.projects = reply.data
            render()
        end
    end)
    api.amh(config.amh, { "agent", "list" }, nil, function(err, stdout)
        if not err then
            M.tasks = api.parse_tasks(stdout)
            render()
        end
    end)
end

local function create_buffer()
    local session = require("omnigent.session")
    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].filetype = "omnigent"
    vim.bo[M.buf].modifiable = false
    vim.api.nvim_buf_call(M.buf, function()
        vim.cmd([[syntax match Title /^\S.*$/]])
    end)
    local function map(lhs, action, desc)
        vim.keymap.set("n", lhs, function()
            local at_cursor = M.session_at_cursor()
            if at_cursor then
                action(at_cursor)
            end
        end, { buffer = M.buf, desc = desc })
    end
    map("<CR>", session.open, "Open the agent's terminal")
    map("m", function(at_cursor)
        session.compose({ session = at_cursor })
    end, "Write a message to the agent")
    map("D", session.close, "Close the agent")
    vim.keymap.set("n", "n", session.spawn, { buffer = M.buf, desc = "Start a new agent" })
    vim.keymap.set("n", "r", M.refresh, { buffer = M.buf, desc = "Refresh" })
    vim.keymap.set("n", "q", M.toggle, { buffer = M.buf, desc = "Hide the sidebar" })
end

--- Show the sidebar, or hide it when shown.
function M.toggle()
    local win = window()
    if win then
        M.timer:stop()
        if #vim.api.nvim_tabpage_list_wins(0) == 1 then
            vim.cmd("vertical new")
        end
        return vim.api.nvim_win_close(win, false)
    end
    if not (M.buf and vim.api.nvim_buf_is_valid(M.buf)) then
        create_buffer()
    end
    vim.cmd(("topleft vertical %dsplit"):format(config.sidebar_width))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, M.buf)
    for option, value in pairs({ winfixwidth = true, number = false, relativenumber = false, cursorline = true, wrap = false }) do
        vim.wo[win][0][option] = value
    end
    M.timer = M.timer or vim.uv.new_timer()
    M.timer:start(0, config.refresh_ms, vim.schedule_wrap(M.refresh))
end

return M
