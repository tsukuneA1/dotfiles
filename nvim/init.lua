-- Load VS Code-style Python snippets and expand them with <Tab>.
local snippet_file = vim.fn.stdpath("config") .. "/snippets/python.json"
local snippet_lines = vim.fn.readfile(snippet_file)
local vscode_snippets = vim.json.decode(table.concat(snippet_lines, "\n"))
local snippets_by_prefix = {}
for _, snippet in pairs(vscode_snippets) do
  snippets_by_prefix[snippet.prefix] = snippet
end

local function render_body(body)
  if type(body) == "table" then
    body = table.concat(body, "\n")
  end

  local rendered = ""
  local cursor_offset
  local i = 1
  while i <= #body do
    local rest = body:sub(i)
    if rest:sub(1, 2) == "$0" then
      cursor_offset = #rendered
      i = i + 2
    else
      local token = rest:match("^%${%d+:[^}]*}")
      if token then
        rendered = rendered .. token:match("^%${%d+:(.*)}$")
        i = i + #token
      else
        token = rest:match("^%${%d+}") or rest:match("^%$%d+")
        if token then
          i = i + #token
        else
          rendered = rendered .. body:sub(i, i)
          i = i + 1
        end
      end
    end
  end
  return rendered, cursor_offset or #rendered
end

local function expand_or_insert_tab()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_get_current_line()
  local prefix = line:sub(1, col):match("([%w_]+)$")
  local snippet = prefix and snippets_by_prefix[prefix]
  if not snippet then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
    return
  end

  local expanded, offset = render_body(snippet.body)
  local start_col = col - #prefix
  vim.api.nvim_buf_set_text(0, row, start_col, row, col, vim.split(expanded, "\n", { plain = true }))

  local before_cursor = expanded:sub(1, offset)
  local newline_count = select(2, before_cursor:gsub("\n", ""))
  local last_newline = before_cursor:match(".*()\n")
  local target_col = last_newline and (#before_cursor - last_newline) or #before_cursor
  if newline_count == 0 then
    target_col = start_col + target_col
  end
  vim.api.nvim_win_set_cursor(0, { row + newline_count + 1, target_col })
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function(args)
    vim.keymap.set("i", "<Tab>", expand_or_insert_tab, {
      buffer = args.buf,
      silent = true,
      desc = "Expand Python snippet",
    })
  end,
})

-- Show keyword matches automatically while typing.  Ctrl-N completion also
-- searches other loaded buffers, so names from open files appear here too.
vim.opt.completeopt = { "menuone", "noinsert" }
vim.api.nvim_create_autocmd("TextChangedI", {
  callback = function()
    if vim.fn.pumvisible() == 1 then
      return
    end

    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    local prefix = line:sub(1, cursor[2]):match("([%a_][%w_]*)$")
    if not prefix or #prefix < 2 then
      return
    end

    vim.schedule(function()
      if vim.fn.mode() ~= "i" or vim.api.nvim_get_current_buf() ~= buf then
        return
      end
      local current_cursor = vim.api.nvim_win_get_cursor(0)
      if current_cursor[1] ~= cursor[1] or current_cursor[2] ~= cursor[2] then
        return
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "n", false)
    end)
  end,
})

-- Accept the selected completion with Enter; otherwise insert a newline.
vim.keymap.set("i", "<CR>", function()
  return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true, desc = "Accept completion or insert newline" })
