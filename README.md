# Obsidian LaTeX Templates

**English** · [Português](README.pt-BR.md)

Pandoc/LaTeX templates for exporting Obsidian notes to PDF with the
[Obsidian Enhancing Export](https://github.com/mokeyish/obsidian-enhancing-export) plugin.
The folder layout follows
[obsidian-pandoc-templates](https://github.com/DrLeucine/obsidian-pandoc-templates).

| Template | Purpose |
|---|---|
| [compact-print](compact-print/) | Paper-saving print: A4, tight margins, all black, automatic table column widths |

## Compatibility

| Component | Tested version |
|---|---|
| Obsidian Enhancing Export | **1.11.3** (`id: obsidian-enhancing-export`) |
| pandoc | 3.12 |
| TeX | BasicTeX 2026 (`pdflatex`), no extra packages |
| macOS | 26 (Darwin 25.3), vault on iCloud |

`install.py` edits the plugin's `main.js` by looking for two exact snippets from version **1.11.3**: the `Latex Template` menu and the `--template` argument of the PDF and Latex export types.

- **Other plugin versions:** the script warns. If the snippets don't match, it changes nothing and reports an "unexpected format" in `main.js`. The links are still created, so the separate export type (see each template's README) keeps working.
- **pandoc other than 3.x:** the template may need tweaks (e.g. `\pandocbounded`, introduced in pandoc 3.2).

## Installation

```
python3 install.py
```

Then reload the plugin in Obsidian (turn it off and on under Community plugins).

For each template, the script:

1. creates the link `<vault>/.obsidian/plugins/obsidian-enhancing-export/textemplate/<name>` → `<repo>/<name>`;
2. adds the template to the plugin's **PDF → Latex Template** menu;
3. makes the plugin run the `<name>.lua` filter when that template is selected.

The plugin's menu is hard-coded in `main.js`, so the script edits that file. The original is saved as `main.js.orig`, and `python3 install.py --revert` restores it.

**Updating the plugin removes the patch**: run `install.py` again after every update. The script is idempotent.

The script finds the vault in iCloud on its own. Options: `--plugin <vault>/.obsidian/plugins/obsidian-enhancing-export` when the vault is elsewhere or there are several; `--revert` to undo.

## Creating a new template

```
template-name/
├─ template-name.tex   # pandoc template (required; same name as the folder)
├─ template-name.lua   # pandoc filter (required; use `return {}` if not needed)
├─ README.md           # first line "# Name Template" becomes the menu name
├─ README.pt-BR.md     # Portuguese version
└─ LICENSE
```

After creating the folder, run `python3 install.py` and reload the plugin.

Plugin caveats:
- Any pandoc output on stderr, even a warning, is treated as a failed export.
- The plugin runs pandoc from the note's folder, so paths used by a template or filter must be absolute, or relative to the filter file (`PANDOC_SCRIPT_FILE`).
