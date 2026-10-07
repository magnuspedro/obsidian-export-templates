--[==[
compact-print.lua — filter that goes with the compact-print.tex template.

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

-- usable table width in "characters" at \small (A4, 12 mm margins)
local LINE_CHARS = 128
-- formulas take more room than the same number of letters
local MATH_FACTOR = 1.3

----------------------------------------------------------------- comments

-- removes text between %% ... %% (may span several paragraphs)
local function strip_comments_inlines(inlines, hidden)
  local out = pandoc.Inlines{}
  for _, el in ipairs(inlines) do
    if el.t == "Str" and el.text:find("%%%%", 1) then
      local kept, pos, text = {}, 1, el.text
      while true do
        local s, e = text:find("%%%%", pos)
        local piece = text:sub(pos, s and s - 1 or -1)
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
  for _, b in ipairs(blocks) do
    if b.t == "Para" or b.t == "Plain" then
      local cleaned
      cleaned, hidden = strip_comments_inlines(b.content, hidden)
      if stringify(cleaned):find("%S") or #cleaned:filter(function(x)
            return x.t ~= "Space" and x.t ~= "SoftBreak" and x.t ~= "LineBreak" end) > 0 then
        b.content = cleaned
        out:insert(b)
      end
    elseif not hidden then
      out:insert(b)
    end
  end
  return out
end

------------------------------------------------------------------- callouts

-- default label when the callout has no title, per document language
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
local labels = CALLOUT_LABELS.pt

local function callout(bq)
  local first = bq.content[1]
  if not first or (first.t ~= "Para" and first.t ~= "Plain") then return nil end
  local head = first.content[1]
  if not head or head.t ~= "Str" then return nil end
  local kind = head.text:match("^%[!([%w%-]+)%][%+%-]?$")
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
  while #title > 0 and title[1].t == "Space" do title:remove(1) end

  local label = #title > 0 and pandoc.write(pandoc.Pandoc{pandoc.Plain(title)}, "latex")
    or (labels[kind:lower()] or (kind:sub(1, 1):upper() .. kind:sub(2)))
  label = label:gsub("%s+$", "")

  local body = pandoc.Blocks{}
  if #rest > 0 then body:insert(pandoc.Para(rest)) end
  for i = 2, #bq.content do body:insert(bq.content[i]) end

  local out = pandoc.Blocks{pandoc.RawBlock("latex", "\\begin{callout}{" .. label .. "}")}
  out:extend(body)
  out:insert(pandoc.RawBlock("latex", "\\end{callout}"))
  return out
end

--------------------------------------------------------------------- tables

-- approximate visible length of a text (formula TeX shortened)
local function visible_len(s)
  return utf8.len(s) or #s
end

local function inline_len(inlines)
  local n = 0
  for _, el in ipairs(inlines) do
    if el.t == "Math" then
      local t = el.text
        :gsub("\\[lr]vert", "|")
        :gsub("\\[a-zA-Z]+", "x")    -- \Delta, \overline ... ~ 1 character
        :gsub("[{}%^_ ]", "")
      n = n + math.ceil(visible_len(t) * MATH_FACTOR)
    elseif el.t == "Space" or el.t == "SoftBreak" then
      n = n + 1
    elseif el.content and type(el.content) ~= "string" then
      n = n + inline_len(el.content)
    else
      n = n + visible_len(stringify(el))
    end
  end
  return n
end

local function cell_metrics(cell)
  local total, longest_word = 0, 0
  pandoc.Div(cell.contents):walk{
    Plain = function(b) total = total + inline_len(b.content) end,
    Para = function(b) total = total + inline_len(b.content) end,
    Str = function(s)
      local w = visible_len(s.text)
      if w > longest_word then longest_word = w end
    end,
    Math = function(m)
      local w = inline_len({m})
      if w > longest_word then longest_word = w end
    end,
  }
  return total, longest_word
end

-- Picks column widths that minimise the estimated table height: every column
-- gets at least the width of its longest word/formula, and the remaining
-- width goes where it saves the most lines.
local function smart_widths(tbl)
  local ncol = #tbl.colspecs
  if ncol < 2 then return end
  local rows, maxlen, minw = {}, {}, {}
  for j = 1, ncol do maxlen[j], minw[j] = 0, 1 end

  local function scan(trows, factor)
    for _, row in ipairs(trows) do
      local lens, j, simple = {}, 1, true
      for _, cell in ipairs(row.cells) do
        if cell.col_span ~= 1 then simple = false end
        if j <= ncol then
          local len, word = cell_metrics(cell)
          len, word = len * factor, word * factor
          if word > minw[j] then minw[j] = word end
          if len > maxlen[j] then maxlen[j] = len end
          lens[j] = len
        end
        j = j + cell.col_span
      end
      if simple then rows[#rows + 1] = lens end
    end
  end
  scan(tbl.head.rows, 1.1)                       -- bold is wider
  for _, body in ipairs(tbl.bodies) do scan(body.body, 1) end
  if #rows == 0 then return end

  local FILL = 0.92                               -- word wrapping wastes some space
  local function height(w)
    local h = 0
    for _, lens in ipairs(rows) do
      local m = 1
      for j = 1, ncol do
        local l = lens[j] or 0
        if l > 0 then
          local lines = math.ceil(l / (w[j] * FILL))
          if lines > m then m = lines end
        end
      end
      h = h + m
    end
    return h
  end

  local lo, hi, sum_lo, sum_gap = {}, {}, 0, 0
  for j = 1, ncol do
    hi[j] = math.max(maxlen[j], minw[j]) / FILL + 1   -- everything on one line
    lo[j] = math.min(minw[j] + 1, hi[j])              -- longest word unbroken
    sum_lo, sum_gap = sum_lo + lo[j], sum_gap + (hi[j] - lo[j])
  end

  local w = {}
  if sum_lo >= LINE_CHARS or sum_gap == 0 then
    for j = 1, ncol do w[j] = lo[j] end
  else
    local spare = LINE_CHARS - sum_lo
    for j = 1, ncol do
      w[j] = lo[j] + math.min(spare, sum_gap) * (hi[j] - lo[j]) / sum_gap
    end
    -- hill climbing: move width between columns while the height drops
    local best, passes = height(w), 0
    local improved = true
    while improved and passes < 200 do
      improved, passes = false, passes + 1
      for _, step in ipairs{16, 8, 4, 2, 1} do
        for a = 1, ncol do
          for b = 1, ncol do
            if a ~= b and w[a] - step >= lo[a] then
              w[a], w[b] = w[a] - step, w[b] + step
              local h = height(w)
              if h < best then
                best, improved = h, true
              else
                w[a], w[b] = w[a] + step, w[b] - step
              end
            end
          end
        end
      end
    end
    -- width beyond what is needed goes back to columns that still wrap
    local surplus, needy = 0, 0
    for j = 1, ncol do
      if w[j] > hi[j] then surplus, w[j] = surplus + w[j] - hi[j], hi[j]
      elseif w[j] < hi[j] then needy = needy + (hi[j] - w[j]) end
    end
    if surplus > 0 and needy > 0 then
      for j = 1, ncol do
        if w[j] < hi[j] then w[j] = w[j] + surplus * (hi[j] - w[j]) / needy end
      end
    end
  end

  local total = 0
  for j = 1, ncol do total = total + w[j] end
  for j = 1, ncol do
    tbl.colspecs[j] = {tbl.colspecs[j][1], w[j] / total}
  end
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

------------------------------------------------------------------- images

-- ![[img.png|200]] and ![caption|200x100](img.png): the number is the width in px
local function parse_size(alt)
  local rest, w = alt:match("^(.-)|?%s*(%d+)x?%d*%s*$")
  if not w or (rest ~= "" and not alt:find("|", 1, true)) then return nil end
  return w, rest
end

local function sized_image(img)
  local w, rest = parse_size(stringify(img.caption))
  if not w then return nil end
  img.attributes.width = w .. "px"
  img.caption = pandoc.Inlines(rest)
  return img
end

local function figure(fig)
  local w, rest = parse_size(stringify(fig.caption))
  if not w then return nil end
  fig = fig:walk{Image = function(img)
    img.attributes.width = w .. "px"
    img.caption = pandoc.Inlines(rest)
    return img
  end}
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

-------------------------------------------------------- lone formula

-- paragraph containing only $$...$$: TeX would open an empty line before the
-- formula; \cpdisplay centres it without that space
local function lone_display(para)
  local math_el
  for _, el in ipairs(para.content) do
    if el.t == "Math" and el.mathtype == "DisplayMath" and not math_el then
      math_el = el
    elseif el.t ~= "Space" and el.t ~= "SoftBreak" then
      return nil
    end
  end
  if not math_el or math_el.text:find("^%s*\\begin") then return nil end
  return pandoc.RawBlock("latex", "\\cpdisplay{" .. math_el.text .. "}")
end

----------------------------------------------------------------- document

local function file_title()
  local f = PANDOC_STATE.input_files and PANDOC_STATE.input_files[1]
  if not f or f == "-" then return nil end
  local name = f:match("([^/\\]+)$") or f
  return nfc((name:gsub("%.[^.]+$", "")))
end

local function main(doc)
  local meta, blocks = doc.meta, strip_comment_blocks(doc.blocks)

  -- title
  if meta.title == nil then
    local h1 = 0
    for _, b in ipairs(blocks) do
      if b.t == "Header" and b.level == 1 then h1 = h1 + 1 end
    end
    if h1 == 1 and blocks[1] and blocks[1].t == "Header" and blocks[1].level == 1 then
      meta.title = pandoc.MetaInlines(blocks[1].content)
      blocks:remove(1)
    else
      local t = file_title()
      if t then meta.title = pandoc.MetaInlines(pandoc.Inlines(t)) end
    end
  end

  -- the lowest heading level becomes a section
  local minlevel = 99
  for _, b in ipairs(blocks) do
    if b.t == "Header" and b.level < minlevel then minlevel = b.level end
  end
  local shift = (minlevel < 99) and (minlevel - 1) or 0

  -- defaults
  if meta.lang == nil then meta.lang = pandoc.MetaString("pt-BR") end
  labels = stringify(meta.lang):lower():match("^pt") and CALLOUT_LABELS.pt
    or CALLOUT_LABELS.en
  if meta.zebra == nil then meta.zebra = true end
  if meta.footer == nil then meta.footer = true end

  blocks = blocks:walk{
    Header = function(h)
      if shift > 0 then h.level = h.level - shift end
      return h
    end,
    BlockQuote = function(bq) return callout(bq) end,
    Para = function(p) return lone_display(p) end,
    Figure = figure,
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

  doc.meta, doc.blocks = meta, blocks
  return doc
end

-- pass 1: normalise accents in all text; pass 2: everything else
local function fix_text(el) el.text = nfc(el.text); return el end
return {
  {Str = fix_text, Code = fix_text, CodeBlock = fix_text, Math = fix_text},
  {Pandoc = main},
}
