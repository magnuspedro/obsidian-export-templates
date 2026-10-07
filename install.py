#!/usr/bin/env python3
"""Install this repository's templates into Obsidian Enhancing Export.

For every folder ``<name>/`` containing ``<name>.tex``:

1. create the link ``<plugin>/textemplate/<name> -> <repo>/<name>``;
2. add ``<Name>`` to the plugin's "Latex Template" menu (hard-coded in
   ``main.js``) and make the PDF/Latex command run ``<name>/<name>.lua``
   when that template is selected.

The script is idempotent: run it whenever a template is added or the plugin
is updated (updates overwrite ``main.js``). Reload the plugin in Obsidian
afterwards.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

PLUGIN_SUBDIR = ".obsidian/plugins/obsidian-enhancing-export"
ICLOUD_VAULTS = Path.home() / "Library/Mobile Documents/iCloud~md~obsidian"
REPO = Path(__file__).resolve().parent
TESTED_PLUGIN_VERSION = "1.11.3"

MENU_ANCHOR = '{name:"Academic Paper",value:"neurips.tex"}'
# Menu entries added by this script: value "<folder>/<file>.tex".
OUR_ENTRY = re.compile(r',\{name:"(?:[^"\\]|\\.)*",value:"[\w.-]+/[\w.-]+\.tex"\}')

ARGS_OLD = (
    '${ options.textemplate ? `--resource-path="${pluginDir}/textemplate" '
    '--template="${options.textemplate}"` : ` ` }'
)
# A template in a subfolder ("x/x.tex") also runs the sibling filter "x/x.lua".
ARGS_NEW = (
    '${ options.textemplate ? `--resource-path="${pluginDir}/textemplate" '
    '--template="${options.textemplate}"'
    '${ options.textemplate.includes("/") ? '
    '` -f ${fromFormat}+mark --lua-filter="${pluginDir}/textemplate/'
    '${options.textemplate.slice(0, -4)}.lua"`'
    " : `` }` : ` ` }"
)
# Present in any main.js already patched by this script.
PATCH_MARK = "-f ${fromFormat}+mark --lua-filter"


class InstallError(Exception):
    """A problem that stops the installation; the message is shown to the user."""


def find_plugin(explicit: Path | None) -> Path:
    """Return the plugin folder, given explicitly or found among iCloud vaults."""
    if explicit is not None:
        plugin = explicit.expanduser()
    else:
        found = sorted(ICLOUD_VAULTS.glob(f"*/{PLUGIN_SUBDIR}"))
        if len(found) != 1:
            msg = (
                f"found {len(found)} vaults with Enhancing Export in {ICLOUD_VAULTS}; "
                f"pass --plugin <vault>/{PLUGIN_SUBDIR}"
            )
            raise InstallError(msg)
        plugin = found[0]
    if not (plugin / "main.js").is_file():
        msg = f"plugin not found at {plugin}"
        raise InstallError(msg)
    return plugin


def check_version(plugin: Path) -> None:
    """Warn when the plugin version differs from the tested one."""
    manifest = plugin / "manifest.json"
    if not manifest.is_file():
        return
    version = json.loads(manifest.read_text(encoding="utf-8")).get("version")
    if version != TESTED_PLUGIN_VERSION:
        print(
            f"warning: plugin {version}; script tested with {TESTED_PLUGIN_VERSION}",
            file=sys.stderr,
        )


def templates() -> list[Path]:
    """Return the template folders of this repository."""
    return sorted(
        d for d in REPO.iterdir() if d.is_dir() and (d / f"{d.name}.tex").is_file()
    )


def menu_name(tpl: Path) -> str:
    """Return the menu label: README title without " Template", or the folder name."""
    readme = tpl / "README.md"
    if readme.is_file():
        lines = readme.read_text(encoding="utf-8").splitlines()
        if lines and lines[0].startswith("# "):
            return lines[0][2:].removesuffix(" Template").strip()
    return tpl.name.replace("-", " ").title()


def link(plugin: Path, tpl: Path) -> None:
    """Point ``<plugin>/textemplate/<name>`` at the template folder."""
    dst = plugin / "textemplate" / tpl.name
    if dst.is_symlink():
        if dst.resolve() == tpl:
            return
        dst.unlink()
    elif dst.exists():
        print(f"  {dst} exists and is not a link; skipped", file=sys.stderr)
        return
    dst.symlink_to(tpl, target_is_directory=True)
    print(f"  link: textemplate/{tpl.name} -> {tpl}")


def unlink_all(plugin: Path) -> None:
    """Remove the links that point into this repository."""
    for dst in (plugin / "textemplate").iterdir():
        if dst.is_symlink() and dst.resolve().is_relative_to(REPO):
            dst.unlink()
            print(f"  removed link: textemplate/{dst.name}")


def write_atomic(path: Path, text: str) -> None:
    """Write ``text`` to ``path`` without leaving a half-written file."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def patch(plugin: Path, tpls: list[Path]) -> None:
    """Add the templates to the menu, keeping a pristine ``main.js.orig``."""
    main_js, backup = plugin / "main.js", plugin / "main.js.orig"
    src = main_js.read_text(encoding="utf-8")
    if PATCH_MARK in src and backup.is_file():
        src = backup.read_text(encoding="utf-8")  # re-patch from the original
    if MENU_ANCHOR not in src:
        msg = "unexpected main.js format (new plugin version?); nothing changed"
        raise InstallError(msg)
    if ARGS_OLD in src:
        if src.count(ARGS_OLD) != 2:  # noqa: PLR2004 - PDF and Latex export types
            msg = "unexpected main.js format; nothing changed"
            raise InstallError(msg)
        write_atomic(backup, src)
        src = src.replace(ARGS_OLD, ARGS_NEW)
    src = OUR_ENTRY.sub("", src)
    entries = "".join(
        # json.dumps yields a valid JS string literal, quotes escaped
        f",{{name:{json.dumps(menu_name(t), ensure_ascii=False)},"
        f'value:"{t.name}/{t.name}.tex"}}'
        for t in tpls
    )
    write_atomic(main_js, src.replace(MENU_ANCHOR, MENU_ANCHOR + entries, 1))
    print("menu:", ", ".join(menu_name(t) for t in tpls))


def revert(plugin: Path) -> None:
    """Restore the original ``main.js`` and remove this repository's links."""
    backup = plugin / "main.js.orig"
    if not backup.is_file():
        msg = "no main.js.orig to restore"
        raise InstallError(msg)
    shutil.copy2(backup, plugin / "main.js")
    unlink_all(plugin)
    print("main.js restored")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse the command line."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--plugin",
        type=Path,
        metavar="DIR",
        help=f"plugin folder (<vault>/{PLUGIN_SUBDIR}); default: find it in iCloud",
    )
    parser.add_argument(
        "--revert",
        action="store_true",
        help="restore main.js.orig and remove the links",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Run the installer; return the process exit code."""
    args = parse_args(argv)
    try:
        plugin = find_plugin(args.plugin)
        if args.revert:
            revert(plugin)
        else:
            check_version(plugin)
            tpls = templates()
            for tpl in tpls:
                link(plugin, tpl)
            patch(plugin, tpls)
    except (InstallError, OSError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
    print("Reload the plugin in Obsidian.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
