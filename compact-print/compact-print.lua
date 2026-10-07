--[==[
compact-print.lua — pandoc filter that goes with compact-print.tex.

  * title: YAML `title`; else a single H1 at the top; else the file name
  * heading levels: the lowest level becomes a section (notes starting at ## work)
  * tables: column widths from the content (short columns don't waste space,
    long text gets more width) and a bold header row
  * Obsidian callouts (> [!note] Title) become a labelled block
  * Obsidian %%comments%% are not printed
  * --- (horizontal rule) becomes a thin rule with no extra space
  * ![[img.png|200]]: 200 px wide, without becoming a "Figure 1: 200" float
  * decomposed accents (NFD, common in macOS file names) become NFC
  * defaults: lang = pt-BR, zebra = true, footer = true

Never writes to stderr: Enhancing Export treats any output there as an error.
]==]

local stringify = pandoc.utils.stringify
local script_dir = (PANDOC_SCRIPT_FILE or ""):match("^(.*)[/\\]") or "."
local nfc = dofile(script_dir .. "/nfc.lua")

-- Usable table width in "characters" at \small (A4, 12 mm margins).
local LINE_CHARS = 128
-- Formulas take more room than the same number of letters.
local MATH_FACTOR = 1.3
-- Bold header text is wider than body text.
local BOLD_FACTOR = 1.1
-- Word wrapping never fills a line completely.
local FILL = 0.92
-- Safety cap for the column-width search.
local MAX_PASSES = 200

local function is_blank(el)
  return el.t == "Space" or el.t == "SoftBreak" or el.t == "LineBreak"
end

------------------------------------------------------------------- comments

--- Removes text between %% ... %%; `hidden` carries the state across
--- paragraphs, since a comment may span several of them.
local function strip_comments_inlines(inlines, hidden)
  local out = pandoc.Inlines{}
  for _, el in ipairs(inlines) do
    if el.t == "Str" and el.text:find("%%", 1, true) then
      local kept, pos = {}, 1
      while true do
        local s, e = el.text:find("%%", pos, true)
        local piece = el.text:sub(pos, s and s - 1 or -1)
        if not hidden and piece ~= "" then kept[#kept + 1] = piece end
        if not s then break end
        hidden, pos = not hidden, e + 1
      end
      if #kept > 0 then out:insert(pandoc.Str(table.concat(kept))) end
    elseif not hidden then
      out:insert(el)
    end
  end
  return out, hidden
end

local function strip_comment_blocks(blocks)
  local out, hidden = pandoc.Blocks{}, false
  for _, block in ipairs(blocks) do
    if block.t == "Para" or block.t == "Plain" then
      local cleaned
      cleaned, hidden = strip_comments_inlines(block.content, hidden)
      if cleaned:find_if(function(el) return not is_blank(el) end) then
        block.content = cleaned
        out:insert(block)
      end
    elseif not hidden then
      out:insert(block)
    end
  end
  return out
end

------------------------------------------------------------------- callouts

-- Label used when a callout has no title, per document language.
local CALLOUT_LABELS = {
  pt = {
    note = "Nota", info = "Info", tip = "Dica", hint = "Dica",
    important = "Importante", warning = "Atenção", caution = "Atenção",
    attention = "Atenção", danger = "Perigo", error = "Erro", bug = "Bug",
    example = "Exemplo", quote = "Citação", cite = "Citação",
    abstract = "Resumo", summary = "Resumo", tldr = "Resumo",
    todo = "A fazer", question = "Pergunta", help = "Pergunta", faq = "Pergunta",
    success = "OK", check = "OK", done = "OK", failure = "Falha",
    fail = "Falha", missing = "Falta",
  },
  en = {
    note = "Note", info = "Info", tip = "Tip", hint = "Hint",
    important = "Important", warning = "Warning", caution = "Caution",
    attention = "Attention", danger = "Danger", error = "Error", bug = "Bug",
    example = "Example", quote = "Quote", cite = "Quote",
    abstract = "Abstract", summary = "Summary", tldr = "TL;DR",
    todo = "To do", question = "Question", help = "Help", faq = "FAQ",
    success = "Success", check = "Done", done = "Done", failure = "Failure",
    fail = "Failure", missing = "Missing",
  },
}

local function latex(inlines)
  local out = pandoc.write(pandoc.Pandoc{pandoc.Plain(inlines)}, "latex")
  return (out:gsub("%s+$", ""))
end

--- Turns `> [!kind] Title` into a `callout` environment; nil if not a callout.
local function callout(blockquote, labels)
  local first = blockquote.content[1]
  if not first or (first.t ~= "Para" and first.t ~= "Plain") then return nil end
  local head = first.content[1]
  local kind = head and head.t == "Str" and head.text:match("^%[!([%w%-]+)%][%+%-]?$")
  if not kind then return nil end

  -- title = rest of the first line; what follows the line break is content
  local title, rest, in_title = pandoc.Inlines{}, pandoc.Inlines{}, true
  for i = 2, #first.content do
    local el = first.content[i]
    if in_title and (el.t == "SoftBreak" or el.t == "LineBreak") then
      in_title = false
    elseif in_title then
      title:insert(el)
    else
      rest:insert(el)
    end
  end
  while title[1] and title[1].t == "Space" do title:remove(1) end

  local label = #title > 0 and latex(title)
    or labels[kind:lower()]
    or (kind:sub(1, 1):upper() .. kind:sub(2))

  local out = pandoc.Blocks{pandoc.RawBlock("latex", "\\begin{callout}{" .. label .. "}")}
  if #rest > 0 then out:insert(pandoc.Para(rest)) end
  for i = 2, #blockquote.content do out:insert(blockquote.content[i]) end
  out:insert(pandoc.RawBlock("latex", "\\end{callout}"))
  return out
end

--------------------------------------------------------------------- tables

local function text_len(s)
  return utf8.len(s) or #s
end

--- Approximate printed width of the inlines, in characters.
local function inline_len(inlines)
  local n = 0
  for _, el in ipairs(inlines) do
    if el.t == "Math" then
      local tex = el.text
        :gsub("\\[lr]vert", "|")
        :gsub("\\[a-zA-Z]+", "x") -- \Delta, \overline ... ~ 1 character
        :gsub("[{}%^_ ]", "")
      n = n + math.ceil(text_len(tex) * MATH_FACTOR)
    elseif is_blank(el) then
      n = n + 1
    elseif type(el.content) == "table" or type(el.content) == "userdata" then
      n = n + inline_len(el.content)
    else
      n = n + text_len(stringify(el))
    end
  end
  return n
end

--- Total text length of a cell and its longest unbreakable piece.
local function cell_metrics(cell)
  local total, longest = 0, 0
  local function piece(width)
    if width > longest then longest = width end
  end
  pandoc.Div(cell.contents):walk{
    Plain = function(b) total = total + inline_len(b.content) end,
    Para = function(b) total = total + inline_len(b.content) end,
    Str = function(s) piece(text_len(s.text)) end,
    Code = function(c) piece(text_len(c.text)) end,
    Math = function(m) piece(inline_len{m}) end,
  }
  return total, longest
end

--- Estimated number of printed lines for the table at widths `w`.
local function table_height(rows, w)
  local height = 0
  for _, lens in ipairs(rows) do
    local row_lines = 1
    for j, len in pairs(lens) do
      if len > 0 then
        row_lines = math.max(row_lines, math.ceil(len / (w[j] * FILL)))
      end
    end
    height = height + row_lines
  end
  return height
end

--- Moves width between columns while the estimated height keeps dropping.
local function hill_climb(rows, w, lo)
  local best = table_height(rows, w)
  for _ = 1, MAX_PASSES do
    local improved = false
    for _, step in ipairs{16, 8, 4, 2, 1} do
      for from = 1, #w do
        for to = 1, #w do
          if from ~= to and w[from] - step >= lo[from] then
            w[from], w[to] = w[from] - step, w[to] + step
            local height = table_height(rows, w)
            if height < best then
              best, improved = height, true
            else
              w[from], w[to] = w[from] + step, w[to] - step
            end
          end
        end
      end
    end
    if not improved then break end
  end
end

--- Picks column widths that minimise the estimated table height: every column
--- gets at least the width of its longest word/formula, and the remaining
--- width goes where it saves the most lines.
local function smart_widths(tbl)
  local ncol = #tbl.colspecs
  if ncol < 2 then return end
  local rows, maxlen, minw = {}, {}, {}
  for j = 1, ncol do maxlen[j], minw[j] = 0, 1 end

  local function scan(table_rows, factor)
    for _, row in ipairs(table_rows) do
      local lens, j = {}, 1
      for _, cell in ipairs(row.cells) do
        -- a merged cell says nothing about the width of a single column
        if cell.col_span == 1 and j <= ncol then
          local len, longest = cell_metrics(cell)
          lens[j] = len * factor
          minw[j] = math.max(minw[j], longest * factor)
          maxlen[j] = math.max(maxlen[j], lens[j])
        end
        j = j + cell.col_span
      end
      rows[#rows + 1] = lens
    end
  end
  scan(tbl.head.rows, BOLD_FACTOR)
  for _, body in ipairs(tbl.bodies) do scan(body.body, 1) end

  local lo, hi, sum_lo, sum_gap = {}, {}, 0, 0
  for j = 1, ncol do
    hi[j] = math.max(maxlen[j], minw[j]) / FILL + 1 -- everything on one line
    lo[j] = math.min(minw[j] + 1, hi[j])            -- longest word unbroken
    sum_lo, sum_gap = sum_lo + lo[j], sum_gap + (hi[j] - lo[j])
  end

  local w = {}
  if sum_lo >= LINE_CHARS or sum_gap == 0 then
    for j = 1, ncol do w[j] = lo[j] end
  else
    local spare = math.min(LINE_CHARS - sum_lo, sum_gap)
    for j = 1, ncol do w[j] = lo[j] + spare * (hi[j] - lo[j]) / sum_gap end
    hill_climb(rows, w, lo)
    -- width beyond what is needed goes back to columns that still wrap
    local surplus, needed = 0, 0
    for j = 1, ncol do
      if w[j] > hi[j] then
        surplus, w[j] = surplus + w[j] - hi[j], hi[j]
      else
        needed = needed + (hi[j] - w[j])
      end
    end
    if surplus > 0 and needed > 0 then
      for j = 1, ncol do w[j] = w[j] + surplus * (hi[j] - w[j]) / needed end
    end
  end

  local total = 0
  for j = 1, ncol do total = total + w[j] end
  for j = 1, ncol do tbl.colspecs[j] = {tbl.colspecs[j][1], w[j] / total} end
end

local function bold_header(tbl)
  for _, row in ipairs(tbl.head.rows) do
    for _, cell in ipairs(row.cells) do
      cell.contents = cell.contents:walk{
        Plain = function(b) return pandoc.Plain{pandoc.Strong(b.content)} end,
        Para = function(b) return pandoc.Para{pandoc.Strong(b.content)} end,
      }
    end
  end
end

--------------------------------------------------------------------- images

--- Obsidian size syntax: "200", "200x100", "caption|200"; returns width, rest.
local function parse_size(alt)
  local rest, width = alt:match("^(.-)|?%s*(%d+)x?%d*%s*$")
  if not width or (rest ~= "" and not alt:find("|", 1, true)) then return nil end
  return width, (rest:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function resize(img, width, rest)
  img.attributes.width = width .. "px"
  img.caption = pandoc.Inlines(rest)
  return img
end

local function sized_image(img)
  local width, rest = parse_size(stringify(img.caption))
  if width then return resize(img, width, rest) end
end

local function sized_figure(fig)
  local width, rest = parse_size(stringify(fig.caption))
  if not width then return nil end
  fig = fig:walk{Image = function(img) return resize(img, width, rest) end}
  if rest ~= "" then
    fig.caption = pandoc.Caption(pandoc.Blocks{pandoc.Plain(pandoc.Inlines(rest))})
    return fig
  end
  -- no real caption: centred image in the text flow, not floating
  local out = pandoc.Blocks{pandoc.RawBlock("latex", "{\\centering")}
  out:extend(fig.content)
  out:insert(pandoc.RawBlock("latex", "\\par}"))
  return out
end

--------------------------------------------------------------- lone formula

--- A paragraph holding only $$...$$ would make TeX open an empty line before
--- the formula; \cpdisplay (defined in the template) centres it without it.
local function lone_display(para)
  local formula
  for _, el in ipairs(para.content) do
    if el.t == "Math" and el.mathtype == "DisplayMath" and not formula then
      formula = el
    elseif el.t ~= "Space" and el.t ~= "SoftBreak" then
      return nil
    end
  end
  if not formula or formula.text:find("^%s*\\begin") then return nil end
  return pandoc.RawBlock("latex", "\\cpdisplay{" .. formula.text .. "}")
end

------------------------------------------------------------------- document

local function file_title()
  local path = PANDOC_STATE.input_files[1]
  if not path or path == "-" then return nil end
  local name = path:match("([^/\\]+)$") or path
  return nfc((name:gsub("%.[^.]+$", "")))
end

--- Sets the title (YAML, single H1 or file name) and removes a used H1.
local function set_title(meta, blocks)
  if meta.title ~= nil then return end
  local h1_count = 0
  for _, block in ipairs(blocks) do
    if block.t == "Header" and block.level == 1 then h1_count = h1_count + 1 end
  end
  local first = blocks[1]
  if h1_count == 1 and first and first.t == "Header" and first.level == 1 then
    meta.title = pandoc.MetaInlines(first.content)
    blocks:remove(1)
  else
    local title = file_title()
    if title then meta.title = pandoc.MetaInlines(pandoc.Inlines(title)) end
  end
end

local function heading_shift(blocks)
  local lowest
  for _, block in ipairs(blocks) do
    if block.t == "Header" then lowest = math.min(lowest or block.level, block.level) end
  end
  return lowest and lowest - 1 or 0
end

local function main(doc)
  local meta = doc.meta
  local blocks = strip_comment_blocks(doc.blocks)
  set_title(meta, blocks)
  local shift = heading_shift(blocks)

  if meta.lang == nil then meta.lang = pandoc.MetaString("pt-BR") end
  if meta.zebra == nil then meta.zebra = true end
  if meta.footer == nil then meta.footer = true end
  local lang = stringify(meta.lang):lower()
  local labels = lang:match("^pt") and CALLOUT_LABELS.pt or CALLOUT_LABELS.en

  doc.blocks = blocks:walk{
    Header = function(h)
      h.level = h.level - shift
      return h
    end,
    BlockQuote = function(bq) return callout(bq, labels) end,
    Para = lone_display,
    Figure = sized_figure,
    Image = sized_image,
    HorizontalRule = function()
      return pandoc.RawBlock("latex",
        "\\par\\vspace{2pt}{\\color{rulegray}\\hrule height 0.3pt}\\vspace{2pt}")
    end,
    Table = function(tbl)
      smart_widths(tbl)
      bold_header(tbl)
      return tbl
    end,
  }
  return doc
end

-- pass 1 normalises accents in all text; pass 2 does everything else
local function to_nfc(el)
  el.text = nfc(el.text)
  return el
end

return {
  {Str = to_nfc, Code = to_nfc, CodeBlock = to_nfc, Math = to_nfc},
  {Pandoc = main},
}
