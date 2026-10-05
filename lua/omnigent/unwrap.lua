--- Pure text functions that undo terminal line wrapping.
local M = {}

-- 🧑 "select agent output and “reply” to it which turns it into a quoted block without the added line breaks nvim terminal injects"

--- Bytes ignored when matching terminal text against the transcript:
--- whitespace the terminal adds, and Markdown marks the harness renders away.
local IGNORED = "[%s%*`#_>|-]"

--- Drop ignored bytes and harness bullets from `text`.
--- Returns the kept bytes, and for each kept byte its index in `text`.
local function squeeze(text)
    local kept, index = {}, {}
    for i = 1, #text do
        local byte = text:sub(i, i)
        if not byte:match(IGNORED) then
            kept[#kept + 1] = byte
            index[#index + 1] = i
        end
    end
    return table.concat(kept), index
end

--- Find the transcript passage that `selection` is a wrapped rendering of.
--- `sources` are transcript texts, newest first.
--- Returns the passage as written by the agent, or `nil` when none matches.
function M.locate(selection, sources)
    local needle = squeeze(selection:gsub("[⏺●•]", ""))
    if needle == "" then
        return nil
    end
    for _, source in ipairs(sources) do
        local hay, index = squeeze(source)
        local first, last = hay:find(needle, 1, true)
        if first then
            local from, to = index[first], index[last]
            -- Widen to whole lines only where that adds nothing but marks.
            while from > 1 and source:sub(from - 1, from - 1):match("[%*`_]") do
                from = from - 1
            end
            while to < #source and source:sub(to + 1, to + 1):match("[%*`_]") do
                to = to + 1
            end
            return source:sub(from, to)
        end
    end
    return nil
end

--- Join `lines` that a word wrap split, without knowing the original text.
--- A line continues the previous one when its first word would not have fit there.
--- The wrap width is taken as the longest line.
function M.join(lines)
    local indent, width = math.huge, 0
    for _, line in ipairs(lines) do
        if line:match("%S") then
            indent = math.min(indent, #line:match("^%s*"))
            width = math.max(width, vim.fn.strdisplaywidth((line:gsub("%s+$", ""))))
        end
    end
    local out, prev_width = {}, 0
    for _, raw in ipairs(lines) do
        local line = raw:gsub("%s+$", "")
        local text = line:sub(indent + 1):gsub("^%s+", "")
        local word = text:match("^%S+") or ""
        local starts_item = text:match("^[-*+•●⏺]%s") or text:match("^%d+[.)]%s")
        local continues = #out > 0
            and out[#out] ~= ""
            and text ~= ""
            and not starts_item
            and prev_width + 1 + vim.fn.strdisplaywidth(word) > width
        if continues then
            out[#out] = out[#out] .. " " .. text
        else
            out[#out + 1] = line:sub(indent + 1)
        end
        prev_width = vim.fn.strdisplaywidth(line)
    end
    return out
end

--- Turn `lines` into a Markdown quote followed by a blank line.
function M.quote(lines)
    local out = {}
    for _, line in ipairs(lines) do
        out[#out + 1] = line == "" and ">" or "> " .. line
    end
    out[#out + 1] = ""
    return out
end

return M
