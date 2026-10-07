# Compact Print Template

**English** · [Português](README.pt-BR.md)

## Description

Template for **printing Obsidian notes on as little paper as possible** without hurting readability. Builds the PDF with pandoc + pdflatex and compiles on a plain BasicTeX install, with no extra packages.

On a table-heavy test note, the default Enhancing Export PDF took 12 Letter pages; with this template it fits on 3 A4 pages.

What changes compared with the default PDF:

- A4 with 10–13 mm margins, Times 10 pt and microtype. A one-line footer holds the title and "page / total"; there is no header.
- No title page: the title becomes a single line at the top, taken from the YAML `title`, from a single `# H1` at the start of the note, or from the file name.
- Headings, lists, paragraphs and formulas use tight spacing. A `$$…$$` formula alone in its paragraph does not open an empty line above it.
- **Tables:**
  - The Lua filter picks the column widths that minimise the total table height, so short columns (numbers, IDs) don't waste space.
  - The header is bold and repeats on every page, and rows are striped.
  - The font is `\small`.
- An image `![[img.png|200]]` keeps the Obsidian width and stays in the text flow instead of becoming "Figure 1: 200". Other images are capped at 45 % of the page height.
- **Obsidian features:**
  - callouts `> [!note] Title` become a labelled block;
  - `%%comments%%` are not printed;
  - `==highlight==` and `~~strikethrough~~` work even without the `soul` package;
  - `---` becomes a thin rule.
- Everything is black, including headings, links, footer and code (syntax highlighting keeps only bold and italics). Only the table stripes are grey (turn them off with `zebra: false`). To add colour, change `accent` in `compact-print.tex`.
- The default language is pt-BR (hyphenation, "Sumário"); use `lang: en` for English notes.
- Accented file names coming from macOS/iCloud (decomposed Unicode, NFD) are recomposed (`nfc.lua`); without this pdflatex fails with "Unicode character ̧ (U+0327)".

## Installation (Obsidian Enhancing Export)

Run `python3 install.py` at the repository root (see the [main README](../README.md)) and reload the plugin. The template shows up under **PDF → Latex Template → Compact Print**.

You can also create a separate export type that does not depend on the menu (it survives plugin updates):

1. Open **Settings → Enhancing Export → Edit command template → +**.
2. Pick the **PDF** template and give it a name.
3. Use these **Arguments**:

   ```
   -f ${fromFormat}+mark --resource-path="${currentDir}" --resource-path="${attachmentFolderPath}" --lua-filter="${luaDir}/pdf.lua" --lua-filter="${pluginDir}/textemplate/compact-print/compact-print.lua" --template="${pluginDir}/textemplate/compact-print/compact-print.tex" -o "${outputPath}" -t pdf
   ```

If you install extra packages, the template picks them up automatically:

- `sudo tlmgr install newtx` → newtx font instead of mathptmx;
- `sudo tlmgr install soul` → native highlighting.

Plain pandoc from the terminal:

```
pandoc note.md -f markdown+wikilinks_title_after_pipe+mark \
  --lua-filter=compact-print.lua --template=compact-print.tex \
  --pdf-engine=pdflatex -o note.pdf
```

## Optional YAML

Every field is optional. Without YAML, the title comes from the file name.

```
---
title: Title shown at the top and in the footer
author: Your Name
date: 2026-10-07
lang: en               # default pt-BR
fontsize: 10pt         # 11pt or 12pt for more comfort
papersize: a4          # or letter
geometry: [top=10mm, bottom=13mm, left=12mm, right=12mm, footskip=6mm]
table-fontsize: \small # \footnotesize is tighter
zebra: false           # no table stripes (saves ink)
image-max-height: 0.3  # maximum image height (fraction of the page)
toc: true              # compact two-column table of contents
numbersections: true
footer: false          # no footer
---
```

## Limitations

- Built for `pdflatex`; xelatex/lualatex were not tested.
- A missing image makes pandoc warn on stderr, and Enhancing Export treats that as a failed export (the default PDF behaves the same).
- Column widths are estimated from character counts, so a very narrow cell may occasionally wrap one extra line.
