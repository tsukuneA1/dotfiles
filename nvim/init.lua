vim.g.mapleader = " "
-- Draw a guide at each four-space indentation level (including Python).
vim.opt.list = true
vim.opt.listchars = { tab = "│ ", leadmultispace = "│   ", trail = "·" }
local function highlight_indent_guides()
  vim.api.nvim_set_hl(0, "Whitespace", { fg = "#8a9bb0", ctermfg = 246 })
end
highlight_indent_guides()
vim.api.nvim_create_autocmd("ColorScheme", { callback = highlight_indent_guides })
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function()
    vim.bo.expandtab = true
    vim.bo.shiftwidth = 4
    vim.bo.softtabstop = 4
    vim.bo.tabstop = 4
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function() vim.opt_local.list = false end,
})
-- Expand netrw directories in place; follow the directory of an opened file.
vim.g.netrw_keepdir = 1
vim.g.netrw_liststyle = 3
vim.api.nvim_create_autocmd("DirChanged", {
  pattern = "global",
  callback = function(args)
    local directory = args.file
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win)
            and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "netrw" then
          vim.api.nvim_win_call(win, function()
            if vim.fn.getcwd() == directory and vim.w.netrw_treetop ~= directory then
              vim.cmd("Ntree " .. vim.fn.fnameescape(directory))
            end
          end)
        end
      end
    end)
  end,
})
vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(args)
    local cwd_at_enter = vim.fn.getcwd()
    vim.schedule(function()
      if vim.fn.getcwd() ~= cwd_at_enter or not vim.api.nvim_buf_is_valid(args.buf)
          or vim.api.nvim_get_current_buf() ~= args.buf
          or vim.bo[args.buf].buftype ~= ""
          or vim.bo[args.buf].filetype == "netrw" then
        return
      end
      local name = vim.api.nvim_buf_get_name(args.buf)
      if name == "" then return end
      local directory = vim.fn.fnamemodify(name, ":p:h")
      if vim.fn.isdirectory(directory) == 1 then vim.api.nvim_set_current_dir(directory) end
    end)
  end,
})
vim.keymap.set("n", "<leader>y", "<Cmd>%y+<CR>", {
  desc = "Copy the whole file to the system clipboard",
})
vim.keymap.set("n", "-", "<Cmd>Explore<CR>", {
  desc = "Open netrw in the current window",
})

-- Open PDF pages in the local graphical viewer instead of reading binary data.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = { "*.pdf", "*.PDF" },
  callback = function(args)
    local path = vim.api.nvim_buf_get_name(args.buf)
    if vim.fn.executable("xpdf") ~= 1 then
      vim.notify("xpdf is required to view PDFs", vim.log.levels.ERROR)
      return
    end
    local job = vim.fn.jobstart({ "xpdf", path }, {
      detach = true,
      on_exit = function(_, code)
        if code ~= 0 then
          vim.schedule(function()
            vim.notify("xpdf exited with status " .. code .. ": " .. path, vim.log.levels.ERROR)
          end)
        end
      end,
    })
    if job <= 0 then
      vim.notify("Could not open PDF: " .. path, vim.log.levels.ERROR)
      return
    end
    vim.bo[args.buf].buftype = "nofile"
    vim.bo[args.buf].swapfile = false
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then return end
      local was_current = vim.api.nvim_get_current_buf() == args.buf
      vim.api.nvim_buf_delete(args.buf, { force = true })
      if was_current and vim.api.nvim_buf_get_name(0) == "" then
        vim.cmd("Explore " .. vim.fn.fnameescape(vim.fn.fnamemodify(path, ":h")))
      end
    end)
  end,
})

-- Show Git changes in file buffers and in netrw's tree listing.
vim.api.nvim_set_hl(0, "GitMarkAdd", { default = true, fg = "#7fbf7f" })
vim.api.nvim_set_hl(0, "GitMarkChange", { default = true, fg = "#e5c07b" })
vim.api.nvim_set_hl(0, "GitMarkDelete", { default = true, fg = "#e06c75" })
vim.fn.sign_define("GitMarkAdd", { text = "+", texthl = "GitMarkAdd" })
vim.fn.sign_define("GitMarkChange", { text = "~", texthl = "GitMarkChange" })
vim.fn.sign_define("GitMarkDelete", { text = "_", texthl = "GitMarkDelete" })
local netrw_git_ns = vim.api.nvim_create_namespace("netrw_git_marks")
local git_buffers = {}
local netrw_ticks = {}
local netrw_pending = {}
local home_directory = vim.fn.expand("~"):gsub("/$", "")
-- Nerd Fonts glyphs, kept local so netrw and :cd completion need no plugin at startup.
local netrw_icons = {
  Folder = { "", "#82aaff" }, File = { "", "#aab2bf" },
  Code = { "", "#a9b7c6" }, Python = { "", "#4b8bbe" },
  Lua = { "", "#51a0cf" }, Markdown = { "", "#519aba" },
  PDF = { "", "#e06c75" }, Image = { "", "#d19a66" },
  Config = { "", "#6d8086" }, Archive = { "", "#d19a66" },
  Web = { "", "#e44d26" }, Rust = { "", "#dea584" },
  Go = { "", "#519aba" }, Audio = { "", "#c678dd" },
  Video = { "", "#c678dd" },
}
local extension_icons = {
  py = "Python", lua = "Lua", md = "Markdown", markdown = "Markdown", pdf = "PDF",
  png = "Image", jpg = "Image", jpeg = "Image", gif = "Image", svg = "Image", webp = "Image",
  json = "Config", yaml = "Config", yml = "Config", toml = "Config", ini = "Config",
  zip = "Archive", tar = "Archive", gz = "Archive", xz = "Archive", tgz = "Archive",
  html = "Web", htm = "Web", css = "Web", scss = "Web",
  rs = "Rust", go = "Go", mp3 = "Audio", wav = "Audio", mp4 = "Video", webm = "Video",
  js = "Code", jsx = "Code", ts = "Code", tsx = "Code", sh = "Code", fish = "Code",
  c = "Code", h = "Code", cpp = "Code", hpp = "Code", java = "Code", rb = "Code",
}
for name, icon in pairs(netrw_icons) do
  vim.api.nvim_set_hl(0, "NetrwIcon" .. name, { default = true, fg = icon[2] })
  vim.fn.sign_define("NetrwIcon" .. name, {
    text = icon[1], texthl = "NetrwIcon" .. name,
  })
end

local function git_lines(args)
  local lines = vim.fn.systemlist(args)
  return vim.v.shell_error == 0 and lines or nil
end

local function git_root(directory)
  if directory == home_directory then return nil end
  local result = git_lines({ "git", "-C", directory, "rev-parse", "--show-toplevel" })
  local root = result and result[1] or nil
  -- The home repository contains caches and other unrelated directories.
  return root ~= home_directory and root or nil
end

local function relative_path(root, path)
  if path:sub(1, #root + 1) ~= root .. "/" then return nil end
  return path:sub(#root + 2)
end

local function update_file_marks(buf, refresh_base)
  if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf
      or vim.bo[buf].buftype ~= ""
      or vim.bo[buf].filetype == "netrw" then return end
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or vim.fn.isdirectory(path) == 1 then return end
  if vim.api.nvim_buf_line_count(buf) > 20000 or vim.fn.getfsize(path) > 1024 * 1024 then return end

  local state = git_buffers[buf]
  if refresh_base or not state or state.path ~= path then
    local root = git_root(vim.fn.fnamemodify(path, ":h"))
    local relative = root and relative_path(root, path)
    local base = relative and vim.fn.system({ "git", "-C", root, "show", "HEAD:" .. relative })
    if vim.v.shell_error ~= 0 then base = nil end
    -- A missing HEAD entry is a new file, unless Git ignores it.
    if relative and not base then
      local ignored = git_lines({ "git", "-C", root, "check-ignore", relative })
      if not ignored then base = "" end
    end
    state = { path = path, base = base }
    git_buffers[buf] = state
  end

  vim.fn.sign_unplace("GitMarks", { buffer = buf })
  if not state.base then return end
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local current_text = table.concat(current, "\n") .. (vim.bo[buf].endofline and "\n" or "")
  local ok, hunks = pcall(vim.diff, state.base, current_text,
    { result_type = "indices", algorithm = "histogram" })
  if not ok then return end
  local last_line = math.max(1, #current)
  for _, hunk in ipairs(hunks) do
    local old_count, new_start, new_count = hunk[2], hunk[3], hunk[4]
    local sign = old_count == 0 and "GitMarkAdd"
      or new_count == 0 and "GitMarkDelete" or "GitMarkChange"
    local first = new_count == 0 and math.min(math.max(1, new_start), last_line) or new_start
    local last = new_count == 0 and first or new_start + new_count - 1
    for line = first, math.min(last, last_line) do
      vim.fn.sign_place(0, "GitMarks", sign, buf, { lnum = line, priority = 8 })
    end
  end
  if vim.api.nvim_get_current_buf() == buf then vim.wo.signcolumn = "yes" end
end

local function netrw_git_status(tree_root)
  local files, directories = {}, {}
  local root = git_root(tree_root)
  if not root then return files, directories end
  local command = { "git", "-C", root, "status", "--porcelain=v1", "-z",
    "--untracked-files=all" }
  local subtree = relative_path(root, tree_root)
  if subtree then
    command[#command + 1] = "--"
    command[#command + 1] = subtree
  end
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then return files, directories end
  -- Vimscript strings represent the NUL separators from Git as Ctrl-A.
  local entries = vim.split(output, "\1", { plain = true })

  local index = 1
  while index <= #entries do
    local entry = entries[index]
    local status = entry:sub(1, 2)
    local path = entry:sub(4)
    if status:match("[RC]") then index = index + 1 end -- -z puts the old name next.
    local within_tree = relative_path(tree_root, root .. "/" .. path)
    if within_tree then
      local kind = status == "??" and "?" or status:match("[MADRCU]") or "M"
      files[within_tree] = kind
      local parent = within_tree:match("^(.*)/[^/]+$")
      while parent do
        directories[parent] = true
        parent = parent:match("^(.*)/[^/]+$")
      end
    end
    index = index + 1
  end
  return files, directories
end

local function update_netrw_marks(buf, force)
  if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf
      or vim.bo[buf].filetype ~= "netrw" then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if not force and netrw_ticks[buf] == tick then return end
  netrw_ticks[buf] = tick
  vim.api.nvim_buf_clear_namespace(buf, netrw_git_ns, 0, -1)
  vim.fn.sign_unplace("NetrwIcons", { buffer = buf })

  local tree_root = vim.w.netrw_treetop
  if not tree_root or tree_root == "" then return end
  tree_root = tree_root:gsub("/$", "")
  local files, directories = netrw_git_status(tree_root)

  local parents = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local prefix, name = line:match("^([| ]+)([^| ].*)$")
    if prefix and prefix:find("|", 1, true) then
      local depth = select(2, prefix:gsub("|", ""))
      local is_directory = name:sub(-1) == "/"
      name = name:gsub("[/@*|=]$", "")
      local parent = depth > 1 and parents[depth - 1] or nil
      local path = parent and parent .. "/" .. name or name
      if is_directory then parents[depth] = path end
      local extension = name:match("%.([^%.]+)$")
      local icon = is_directory and "Folder"
        or extension and extension_icons[extension:lower()] or "File"
      vim.fn.sign_place(0, "NetrwIcons", "NetrwIcon" .. icon, buf,
        { lnum = row, priority = 1 })
      local kind = is_directory and directories[path] and "●" or files[path]
      if kind then
        local hl = (kind == "?" or kind == "A") and "GitMarkAdd"
          or kind == "D" and "GitMarkDelete" or "GitMarkChange"
        vim.api.nvim_buf_set_extmark(buf, netrw_git_ns, row - 1, 0, {
          virt_text = { { " " .. kind, hl } }, virt_text_pos = "eol",
        })
      end
    end
  end
  vim.wo.signcolumn = "yes"
end

local function queue_netrw_marks(buf, force)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].filetype ~= "netrw" then return end
  if netrw_pending[buf] then
    netrw_pending[buf].force = netrw_pending[buf].force or force
    return
  end
  netrw_pending[buf] = { force = force }
  vim.defer_fn(function()
    local pending = netrw_pending[buf]
    netrw_pending[buf] = nil
    if pending then update_netrw_marks(buf, pending.force) end
  end, 150)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "FocusGained" }, {
  callback = function(args)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then return end
      if vim.bo[args.buf].filetype == "netrw" then
        queue_netrw_marks(args.buf, true)
      else
        update_file_marks(args.buf, true)
      end
    end)
  end,
})
vim.api.nvim_create_autocmd("FileType", {
  pattern = "netrw",
  callback = function(args)
    queue_netrw_marks(args.buf, true)
  end,
})
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  callback = function(args)
    if vim.bo[args.buf].filetype == "netrw" then
      queue_netrw_marks(args.buf, false)
    else
      local tick = vim.api.nvim_buf_get_changedtick(args.buf)
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(args.buf)
            and vim.api.nvim_buf_get_changedtick(args.buf) == tick then
          update_file_marks(args.buf, false)
        end
      end, 120)
    end
  end,
})
vim.api.nvim_create_autocmd("CursorMoved", {
  callback = function(args)
    if vim.bo[args.buf].filetype == "netrw"
        and netrw_ticks[args.buf] ~= vim.api.nvim_buf_get_changedtick(args.buf) then
      queue_netrw_marks(args.buf, false)
    end
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  callback = function(args)
    git_buffers[args.buf] = nil
    netrw_ticks[args.buf] = nil
    netrw_pending[args.buf] = nil
  end,
})

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
  local indent = line:sub(1, start_col):match("^[ \t]*")
  local replacement = vim.split(expanded, "\n", { plain = true })
  for i = 2, #replacement do
    replacement[i] = indent .. replacement[i]
  end
  vim.api.nvim_buf_set_text(0, row, start_col, row, col, replacement)

  local before_cursor = expanded:sub(1, offset)
  local newline_count = select(2, before_cursor:gsub("\n", ""))
  local last_newline = before_cursor:match(".*()\n")
  local target_col = last_newline and (#before_cursor - last_newline) or #before_cursor
  if newline_count == 0 then
    target_col = start_col + target_col
  else
    target_col = #indent + target_col
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
local accepted_completion
local function remember_accepted_completion()
  accepted_completion = {
    buf = vim.api.nvim_get_current_buf(),
    cursor = vim.api.nvim_win_get_cursor(0),
    line = vim.api.nvim_get_current_line(),
  }
end
vim.api.nvim_create_autocmd("TextChangedI", {
  callback = function()
    if accepted_completion then
      local same_text = accepted_completion.buf == vim.api.nvim_get_current_buf()
        and vim.deep_equal(accepted_completion.cursor, vim.api.nvim_win_get_cursor(0))
        and accepted_completion.line == vim.api.nvim_get_current_line()
      if same_text then return end
      accepted_completion = nil
    end
    if vim.fn.pumvisible() == 1 then
      return
    end

    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local changedtick = vim.api.nvim_buf_get_changedtick(buf)
    local line = vim.api.nvim_get_current_line()
    local prefix = line:sub(1, cursor[2]):match("([%a_][%w_]*)$")
    if not prefix or #prefix < 2 then
      return
    end

    vim.schedule(function()
      if vim.fn.mode() ~= "i" or vim.api.nvim_get_current_buf() ~= buf
          or vim.api.nvim_buf_get_changedtick(buf) ~= changedtick
          or accepted_completion then
        return
      end
      local current_cursor = vim.api.nvim_win_get_cursor(0)
      if current_cursor[1] ~= cursor[1] or current_cursor[2] ~= cursor[2] then
        return
      end
      if vim.bo[buf].filetype == "python" then
        local matches = {}
        local seen = {}
        for name, snippet in pairs(snippets_by_prefix) do
          if name:sub(1, #prefix) == prefix then
            matches[#matches + 1] = {
              word = name,
              kind = "S",
              menu = snippet.description or "snippet",
              user_data = "python_snippet",
            }
            seen[name] = true
          end
        end
        if #matches > 0 then
          table.sort(matches, function(a, b) return a.word < b.word end)
          -- Keep ordinary names available when a snippet has the same prefix.
          local line_count = math.min(vim.api.nvim_buf_line_count(buf), 2000)
          for _, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, line_count, false)) do
            for word in text:gmatch("[%a_][%w_]*") do
              if word ~= prefix and word:sub(1, #prefix) == prefix and not seen[word] then
                matches[#matches + 1] = { word = word, kind = "W" }
                seen[word] = true
                if #matches >= 100 then break end
              end
            end
            if #matches >= 100 then break end
          end
          vim.fn.complete(cursor[2] - #prefix + 1, matches)
          return
        end
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-n>", true, false, true), "n", false)
    end)
  end,
})

-- Expand a snippet after its completion item is accepted.
vim.api.nvim_create_autocmd("CompleteDone", {
  callback = function()
    local item = vim.v.completed_item
    if item.word and item.word ~= "" then remember_accepted_completion() end
    if item.user_data ~= "python_snippet" then
      return
    end
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    vim.schedule(function()
      if vim.fn.mode() == "i" and vim.api.nvim_get_current_buf() == buf
          and vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor) then
        expand_or_insert_tab()
        remember_accepted_completion()
      end
    end)
  end,
})

-- Accept the selected completion with Enter; otherwise insert a newline.
vim.keymap.set("i", "<CR>", function()
  return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
end, { expr = true, desc = "Accept completion or insert newline" })
vim.keymap.set("i", "<Down>", function()
  return vim.fn.pumvisible() == 1 and "<C-n>" or "<Down>"
end, { expr = true, desc = "Next completion or move down" })
vim.keymap.set("i", "<Up>", function()
  return vim.fn.pumvisible() == 1 and "<C-p>" or "<Up>"
end, { expr = true, desc = "Previous completion or move up" })

-- Pick a directory from :cd with fzf.  :cd hoge/<Tab> searches below hoge.
local function fzf_cd(argument)
  if vim.fn.executable("fzf") ~= 1 then
    vim.notify("fzf is required for :cd completion", vim.log.levels.WARN)
    return
  end

  local parent, query = argument:match("^(.*)/([^/]*)$")
  local root = parent or "."
  query = query or argument
  if root == "" then root = "/" end
  root = vim.fn.expand(root)
  if vim.fn.isdirectory(root) ~= 1 then
    vim.notify("Not a directory: " .. root, vim.log.levels.WARN)
    return
  end

  local output = vim.fn.tempname()
  local width = math.max(1, math.floor(vim.o.columns * 0.8))
  local height = math.max(1, math.floor(vim.o.lines * 0.6))
  local buffer = vim.api.nvim_create_buf(false, true)
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  local script = [[
find "$1" -mindepth 1 -maxdepth 6 \( -name .git -o -name node_modules -o -name .venv -o -name dist -o -name build \) -prune -o -type d -print |
  sed 's/^/ /' | fzf --nth=2.. --scheme=path --query "$3" --prompt='cd> ' > "$2"
]]
  vim.fn.termopen({ "sh", "-c", script, "sh", root, output, query }, {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
        local selection = vim.fn.filereadable(output) == 1 and vim.fn.readfile(output)[1] or nil
        local selected = selection and selection:match("^ (.*)$")
        vim.fn.delete(output)
        if selected and selected ~= "" then vim.api.nvim_set_current_dir(selected) end
      end)
    end,
  })
  vim.cmd.startinsert()
end

vim.keymap.set("c", "<Tab>", function()
  if vim.fn.getcmdtype() ~= ":" then return "<Tab>" end
  local line = vim.fn.getcmdline()
  local command, argument = line:match("^%s*(%a+)%s*(.*)$")
  if command ~= "cd" or vim.fn.getcmdpos() ~= #line + 1 then return "<Tab>" end
  vim.schedule(function() fzf_cd(argument) end)
  return "<C-c>"
end, { expr = true, desc = "Select a directory for :cd with fzf" })
