#!/usr/bin/env python3
"""Installs this repository's templates into Obsidian Enhancing Export.

For every folder <name>/ containing <name>.tex:
  1. creates the link  <plugin>/textemplate/<name> -> <repo>/<name>
  2. adds "<Name>" to the plugin's "Latex Template" menu (hard-coded in
     main.js) and makes the PDF/Latex command run <name>/<name>.lua when it
     is selected.

Idempotent: run it whenever you add a template or the plugin updates
(updates overwrite main.js).

Usage:  python3 install.py               apply
        python3 install.py --revert      restore main.js.orig
        python3 install.py --plugin DIR  vault not in iCloud, or several vaults
Then reload the plugin in Obsidian (turn it off and on).
"""
import pathlib
import re
import shutil
import sys

PLUGIN_SUBDIR = ".obsidian/plugins/obsidian-enhancing-export"
# Obsidian vaults stored in iCloud (macOS)
ICLOUD_VAULTS = pathlib.Path.home() / "Library/Mobile Documents/iCloud~md~obsidian"
REPO = pathlib.Path(__file__).resolve().parent
TESTED_PLUGIN_VERSION = "1.11.3"

MENU_ANCHOR = '{name:"Academic Paper",value:"neurips.tex"}'
# menu entries from this repo: value "<folder>/<file>.tex"
OUR_ENTRY = re.compile(r',\{name:"[^"]*",value:"[\w.-]+/[\w.-]+\.tex"\}')

ARGS_OLD = ('${ options.textemplate ? `--resource-path="${pluginDir}/textemplate" '
            '--template="${options.textemplate}"` : ` ` }')
# a template in a subfolder ("x/x.tex") runs the sibling filter "x/x.lua"
ARGS_NEW = ('${ options.textemplate ? `--resource-path="${pluginDir}/textemplate" '
            '--template="${options.textemplate}"'
            '${ options.textemplate.includes("/") ? '
            '` -f ${fromFormat}+mark --lua-filter="${pluginDir}/textemplate/'
            '${options.textemplate.slice(0, -4)}.lua"`'
            ' : `` }` : ` ` }')
# present in any main.js already patched by this script
PATCH_MARK = '-f ${fromFormat}+mark --lua-filter'


def templates() -> list[pathlib.Path]:
    return sorted(d for d in REPO.iterdir()
                  if d.is_dir() and (d / f"{d.name}.tex").exists())


def menu_name(tpl: pathlib.Path) -> str:
    readme = tpl / "README.md"
    if readme.exists():
        first = readme.read_text(encoding="utf-8").splitlines()[0]
        if first.startswith("# "):
            return first[2:].removesuffix(" Template").strip()
    return tpl.name.replace("-", " ").title()


def link(plugin: pathlib.Path, tpl: pathlib.Path) -> None:
    dst = plugin / "textemplate" / tpl.name
    if dst.is_symlink() and dst.resolve() == tpl:
        return
    if dst.is_symlink():
        dst.unlink()
    elif dst.exists():
        print(f"  {dst} exists and is not a link; skipped")
        return
    dst.symlink_to(tpl, target_is_directory=True)
    print(f"  link: textemplate/{tpl.name} -> {tpl}")


def patch(plugin: pathlib.Path, tpls: list[pathlib.Path]) -> int:
    main, backup = plugin / "main.js", plugin / "main.js.orig"
    src = main.read_text(encoding="utf-8")
    if PATCH_MARK in src and backup.exists():
        src = backup.read_text(encoding="utf-8")   # re-patch from the original
    if MENU_ANCHOR not in src:
        print("unexpected main.js format (new plugin version?); nothing changed")
        return 1
    if ARGS_OLD in src:
        if src.count(ARGS_OLD) != 2:
            print("unexpected main.js format; nothing changed")
            return 1
        backup.write_text(src, encoding="utf-8")
        src = src.replace(ARGS_OLD, ARGS_NEW)
    src = OUR_ENTRY.sub("", src)
    entries = "".join(
        f',{{name:"{menu_name(t)}",value:"{t.name}/{t.name}.tex"}}' for t in tpls)
    src = src.replace(MENU_ANCHOR, MENU_ANCHOR + entries, 1)
    main.write_text(src, encoding="utf-8")
    print("menu:", ", ".join(menu_name(t) for t in tpls))
    return 0


def main() -> int:
    if "--plugin" in sys.argv:
        plugin = pathlib.Path(sys.argv[sys.argv.index("--plugin") + 1]).expanduser()
    else:
        found = sorted(ICLOUD_VAULTS.glob(f"*/{PLUGIN_SUBDIR}"))
        if len(found) != 1:
            print(f"found {len(found)} vaults with Enhancing Export in {ICLOUD_VAULTS}; "
                  "pass --plugin <vault>/" + PLUGIN_SUBDIR)
            return 1
        plugin = found[0]
    if not (plugin / "main.js").exists():
        print(f"plugin not found at {plugin}")
        return 1
    if "--revert" in sys.argv:
        backup = plugin / "main.js.orig"
        if not backup.exists():
            print("no main.js.orig to restore")
            return 1
        shutil.copy2(backup, plugin / "main.js")
        print("main.js restored")
        return 0
    manifest = plugin / "manifest.json"
    if manifest.exists():
        import json
        version = json.loads(manifest.read_text(encoding="utf-8")).get("version")
        if version != TESTED_PLUGIN_VERSION:
            print(f"warning: plugin {version}; script tested with {TESTED_PLUGIN_VERSION}")
    tpls = templates()
    for t in tpls:
        link(plugin, t)
    rc = patch(plugin, tpls)
    if rc == 0:
        print("Reload the plugin in Obsidian.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
