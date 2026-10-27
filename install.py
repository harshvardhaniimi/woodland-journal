#!/usr/bin/env python3
"""Woodland Journal installer for KOReader on a Kobo connected by USB.

Python 3.8 or later, standard library only; macOS, Linux and Windows.

  python3 install.py check       read-only: what is on the Kobo and what install would change
  python3 install.py backup      copy the whole Kobo, as it is, to ~/KoboBackups/<time>/
  python3 install.py install     back up first, then install Woodland Journal (asks before every optional step)
  python3 install.py uninstall   move Woodland Journal off the Kobo into ~/KoboBackups/<time>-uninstall/

Every question has a flag, so an agent can ask the reader and then pass the answers
(see `python3 install.py install --help`). On the Kobo, install writes only:
  .adds/koreader/plugins/woodland.koplugin/   the plugin
  .adds/koreader/fonts/woodland/              the Alegreya fonts, when they are missing
  .adds/koreader/data/dict/<name>/            a bundled dictionary, only when chosen
and, only when chosen, moves Woodland Journal 0.1's files out of SimpleUI Extra into the
backup folder on this computer. Nothing on the Kobo is deleted outright: whatever leaves
the Kobo is copied, checked and kept on this computer first.
"""

import argparse
import datetime
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

TOOL_VERSION = "0.2.0"
REPO = Path(__file__).resolve().parent
PLUGIN_SRC = REPO / "woodland.koplugin"
FONTS_SRC = REPO / "fonts" / "alegreya"
DICTIONARIES_SRC = REPO / "dictionaries"   # present only in release downloads
BACKUP_ROOT = Path.home() / "KoboBackups"

KOREADER = Path(".adds") / "koreader"
PLUGINS = KOREADER / "plugins"
PLUGIN_DEST = PLUGINS / "woodland.koplugin"
FONTS_DEST = KOREADER / "fonts" / "woodland"
DICT_DEST = KOREADER / "data" / "dict"
MANIFEST = "INSTALL.json"
# Woodland Journal 0.1 lived inside SimpleUI Extra.
LEGACY = ["modules/module_woodland_journal.lua", "modules/module_woodland_goodreads.lua", "woodland"]
# Folders the computer, not the reader, keeps on the Kobo.
SKIP_IN_BACKUP = {".Spotlight-V100", ".fseventsd", ".Trashes", ".TemporaryItems",
                  "System Volume Information", "$RECYCLE.BIN"}
FONT_FILES = ["Alegreya-Bold.ttf", "Alegreya-Italic.ttf"]
CHUNK = 1024 * 1024


class Stop(Exception):
    """A reason to stop before changing anything more."""


# ── Output ──────────────────────────────────────────────────────────────────

class Log:
    def __init__(self):
        self.lines = []
        self.path = None

    def __call__(self, *parts):
        text = " ".join(str(p) for p in parts)
        print(text, flush=True)
        self.lines.append(text)
        if self.path:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(text + "\n")

    def to_file(self, path):
        self.path = path
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(self.lines) + ("\n" if self.lines else ""))


log = Log()


def ask(question, default, answer=None, mode="prompt"):
    """A yes/no answer: the flag's value when given; otherwise, by mode, the
    default ("default", for --yes), a prompt ("prompt"), or a stop ("fail")."""
    if answer is not None:
        log(f"{question} {'yes' if answer else 'no'} (from the command line)")
        return answer
    if mode == "default":
        log(f"{question} {'yes' if default else 'no'} (default)")
        return default
    if mode != "prompt":
        raise Stop(f"Need an answer to: {question}  Pass the matching flag (see --help).")
    hint = "[Y/n]" if default else "[y/N]"
    while True:
        reply = input(f"{question} {hint} ").strip().lower()
        if not reply:
            return default
        if reply in ("y", "yes"):
            return True
        if reply in ("n", "no"):
            return False


# ── Files ───────────────────────────────────────────────────────────────────

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def copy_verified(src, dst):
    """Copy the bytes of src to dst (no metadata, so macOS adds as little as
    possible), flush them to the device, and compare checksums. Returns the hash."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256()
    with open(src, "rb") as fin, open(dst, "wb") as fout:
        for block in iter(lambda: fin.read(CHUNK), b""):
            h.update(block)
            fout.write(block)
        fout.flush()
        os.fsync(fout.fileno())
    digest = h.hexdigest()
    if sha256(dst) != digest:
        raise Stop(f"Copy check failed for {dst}: the written file differs from {src}. Stop and check the Kobo's storage.")
    return digest


def source_files(root):
    """Files to install from a source folder, as relative paths; no macOS or editor debris."""
    out = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.name.startswith("._") and path.name not in (".DS_Store", MANIFEST):
            out.append(path.relative_to(root))
    return out


def appledouble(root):
    return sorted(p for p in root.rglob("._*") if p.is_file()) if root.exists() else []


def move_off_kobo(path, kobo, keep_root):
    """Copy a file or folder from the Kobo into keep_root (same relative path),
    verify every file, then remove it from the Kobo."""
    rel = path.relative_to(kobo)
    target = keep_root / rel
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for f in files:
        copy_verified(f, target / f.relative_to(path) if path.is_dir() else target)
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()
    return target


def sync():
    if hasattr(os, "sync"):
        os.sync()


# ── The Kobo ────────────────────────────────────────────────────────────────

def candidate_mounts():
    system = platform.system()
    if system == "Darwin":
        roots = [Path("/Volumes")]
    elif system == "Windows":
        return [Path(f"{letter}:\\") for letter in "DEFGHIJKLMNOPQRSTUVWXYZ"]
    else:
        user = os.environ.get("USER", "")
        roots = [Path("/media") / user, Path("/run/media") / user, Path("/media"), Path("/mnt")]
    out = []
    for root in roots:
        try:
            out += [p for p in root.iterdir() if p.is_dir()]
        except OSError:
            pass
    return out


def find_kobo(given):
    if given:
        kobo = Path(given).expanduser()
        if not (kobo / ".kobo").is_dir():
            raise Stop(f"{kobo} does not look like a Kobo: there is no .kobo folder in it.")
        return kobo
    found = []
    for p in candidate_mounts():
        try:
            if (p / ".kobo").is_dir() and p not in found:
                found.append(p)
        except OSError:
            pass
    if not found:
        raise Stop("No Kobo found. Connect it by USB, tap Connect on the Kobo, and try again "
                   "(or pass --kobo with its folder, e.g. /Volumes/KOBOeReader or E:\\).")
    if len(found) > 1:
        raise Stop("More than one Kobo is connected: " + ", ".join(map(str, found)) + ". Pass --kobo to choose.")
    return found[0]


def meta_version(plugin_dir):
    meta = plugin_dir / "_meta.lua"
    if not meta.is_file():
        return None
    match = re.search(r'version\s*=\s*"([^"]+)"', meta.read_text(encoding="utf-8", errors="replace"))
    return match.group(1) if match else "unknown"


def read_first_line(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()[0].strip()
    except (OSError, IndexError):
        return None


def device_info(kobo):
    info = {"kobo": str(kobo)}
    # .kobo/version starts with the device's serial number: only firmware and model are read.
    fields = (read_first_line(kobo / ".kobo" / "version") or "").split(",")
    info["firmware"] = fields[2] if len(fields) > 2 else None
    info["model_code"] = fields[-1] if len(fields) > 3 else None
    info["koreader"] = read_first_line(kobo / KOREADER / "git-rev") if (kobo / KOREADER).is_dir() else None
    info["simpleui"] = meta_version(kobo / PLUGINS / "simpleui.koplugin")
    info["simpleui_extra"] = meta_version(kobo / PLUGINS / "simpleui_ext.koplugin")
    info["woodland"] = meta_version(kobo / PLUGIN_DEST)
    extra = kobo / PLUGINS / "simpleui_ext.koplugin"
    info["legacy"] = [rel for rel in LEGACY if (extra / rel).exists()]
    fonts = {}
    for name in FONT_FILES:
        for folder in (kobo / KOREADER / "fonts", kobo / "fonts"):
            hits = sorted(folder.rglob(name)) if folder.is_dir() else []
            hits = [h for h in hits if not h.name.startswith("._")]
            if hits:
                fonts[name] = str(hits[0].relative_to(kobo))
                break
    info["fonts"] = fonts
    dicts = kobo / DICT_DEST
    info["dictionaries"] = sorted(p.name for p in dicts.iterdir() if p.is_dir()) if dicts.is_dir() else []
    usage = shutil.disk_usage(kobo)
    info["free_mb"] = usage.free // (1024 * 1024)
    return info


def fsck_command(kobo):
    """The read-only filesystem check for this computer, or None when unknown."""
    system = platform.system()
    try:
        if system == "Darwin":
            out = subprocess.run(["diskutil", "info", str(kobo)], capture_output=True, text=True, timeout=20).stdout
            node = re.search(r"Device Node:\s+(/dev/disk\S+)", out)
            if node:
                return "sudo fsck_msdos -n " + node.group(1).replace("/dev/disk", "/dev/rdisk")
        elif system == "Linux":
            out = subprocess.run(["findmnt", "-n", "-o", "SOURCE", str(kobo)], capture_output=True, text=True, timeout=20).stdout.strip()
            if out:
                return f"sudo fsck.fat -n {out}"
        elif system == "Windows":
            return f"chkdsk {str(kobo)[:2]}"
    except (OSError, subprocess.SubprocessError):
        pass
    return None


def eject_hint(kobo):
    system = platform.system()
    if system == "Darwin":
        return f'diskutil eject "{kobo}"   (or drag it to the Trash in Finder)'
    if system == "Windows":
        return "Safely Remove Hardware in the taskbar, then tap Eject on the Kobo if asked"
    return f'udisksctl unmount -b "$(findmnt -n -o SOURCE "{kobo}")"   (or Eject in your file manager)'


def available_dictionaries():
    if not DICTIONARIES_SRC.is_dir():
        return []
    return sorted(p.name for p in DICTIONARIES_SRC.iterdir() if p.is_dir() and any(p.glob("*.ifo")))


# ── check ───────────────────────────────────────────────────────────────────

def report(info):
    log("Kobo:            ", info["kobo"])
    log("Firmware:        ", info["firmware"] or "unknown")
    log("KOReader:        ", info["koreader"] or "NOT INSTALLED")
    log("SimpleUI:        ", info["simpleui"] or "NOT INSTALLED")
    log("SimpleUI Extra:  ", info["simpleui_extra"] or "not installed (optional: the dashboard as sleep screen)")
    log("Woodland Journal:", info["woodland"] or "not installed",
        "(0.1 inside SimpleUI Extra: " + ", ".join(info["legacy"]) + ")" if info["legacy"] else "")
    log("Alegreya fonts:  ", ", ".join(f"{k} in {v}" for k, v in info["fonts"].items()) or "missing (headings fall back to Noto Serif)")
    log("Dictionaries:    ", ", ".join(info["dictionaries"]) or "none added")
    log("Free space:      ", f"{info['free_mb']} MB")
    log("Tested by the author on one Kobo Libra Colour (firmware 4.45.23792, KOReader v2026.07.1, SimpleUI 2.7.5).")
    log("Other devices and versions are untested: keep a backup.")


def blockers(info):
    out = []
    if not info["koreader"]:
        out.append("KOReader is not installed. Install it first: https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices")
    if not info["simpleui"]:
        out.append("SimpleUI is not installed in KOReader. Install it first: https://github.com/doctorhetfield-cmd/simpleui.koplugin/releases/latest")
    if info["free_mb"] < 20:
        out.append(f"Only {info['free_mb']} MB free on the Kobo; Woodland needs about 5 MB plus room for KOReader.")
    return out


def cmd_check(args):
    kobo = find_kobo(args.kobo)
    info = device_info(kobo)
    report(info)
    log("")
    problems = blockers(info)
    for p in problems:
        log("Cannot install yet:", p)
    if problems:
        return 2
    log("Install would:")
    log("  - back up the whole Kobo to", BACKUP_ROOT / "<date-time>", "(unless you pass --backup with an earlier one)")
    log("  -", "update" if info["woodland"] else "add", ".adds/koreader/plugins/woodland.koplugin/",
        f"({info['woodland']} -> {meta_version(PLUGIN_SRC)})" if info["woodland"] else f"(version {meta_version(PLUGIN_SRC)})")
    missing = [f for f in FONT_FILES if f not in info["fonts"]]
    if missing:
        log("  - ask to add the missing fonts", ", ".join(missing), "to .adds/koreader/fonts/woodland/")
    if info["legacy"]:
        log("  - ask to move Woodland Journal 0.1's files out of SimpleUI Extra (the new plugin stays idle while they are there)")
    if available_dictionaries():
        log("  - ask whether to add a dictionary:", ", ".join(available_dictionaries()), "(default: keep your current dictionaries)")
    command = fsck_command(kobo)
    log("")
    log("Before installing, check the Kobo's filesystem without changing it:")
    log("  ", command or "(run your system's read-only FAT check on the Kobo)")
    log("It is fine if it only says the volume is marked dirty; stop if it reports anything else.")
    return 0


# ── backup ──────────────────────────────────────────────────────────────────

def backup_files(kobo, scope):
    if scope == "koreader":
        roots = [kobo / KOREADER, kobo / ".kobo" / "Kobo" / "Kobo eReader.conf"]
    else:
        roots = [kobo]
    files = []
    for root in roots:
        if root.is_file():
            files.append(root)
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in SKIP_IN_BACKUP)
            for name in sorted(filenames):
                files.append(Path(dirpath) / name)
    return files


def cmd_backup(args, info=None):
    kobo = find_kobo(args.kobo)
    info = info or device_info(kobo)
    files = backup_files(kobo, args.scope)
    total = sum(f.stat().st_size for f in files)
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S")
    dest = Path(args.to).expanduser() if getattr(args, "to", None) else BACKUP_ROOT / stamp
    root = dest / "kobo"
    dest.parent.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(dest.parent).free
    if free < total * 1.05 + 50 * CHUNK:
        raise Stop(f"Not enough space for the backup: it needs {total // CHUNK} MB, {free // CHUNK} MB are free at {dest.parent}.")
    root.mkdir(parents=True, exist_ok=False)
    log(f"Backing up {len(files)} files ({total // CHUNK} MB) from {kobo} to {dest} …")
    sums, done = [], 0
    for i, f in enumerate(files, 1):
        rel = f.relative_to(kobo)
        sums.append(f"{copy_verified(f, root / rel)}  {rel.as_posix()}")
        done += f.stat().st_size
        if i % 200 == 0 or i == len(files):
            log(f"  {i}/{len(files)} files, {done // CHUNK} MB")
    (dest / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
    record = {"tool": "woodland-journal install.py", "tool_version": TOOL_VERSION,
              "time": datetime.datetime.now().isoformat(timespec="seconds"), "scope": args.scope,
              "files": len(files), "bytes": total,
              "device": {k: info[k] for k in ("firmware", "model_code", "koreader", "simpleui", "simpleui_extra", "woodland")}}
    (dest / "backup.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    log(f"Backup complete and checked: {dest}")
    log("To restore it, copy the contents of its kobo/ folder back onto the Kobo.")
    return dest


def existing_backup(path):
    dest = Path(path).expanduser()
    if not (dest / "backup.json").is_file() or not (dest / "kobo").is_dir():
        raise Stop(f"{dest} is not a backup made by this installer (no backup.json and kobo/ folder).")
    return dest


# ── install ─────────────────────────────────────────────────────────────────

def answer_mode(args):
    if args.yes:
        return "default"
    return "prompt" if sys.stdin.isatty() else "fail"


def cmd_install(args):
    mode = answer_mode(args)
    kobo = find_kobo(args.kobo)
    info = device_info(kobo)
    report(info)
    log("")
    problems = blockers(info)
    if problems:
        raise Stop("\n".join(problems))

    command = fsck_command(kobo)
    log("Before anything is written, check the Kobo's filesystem without changing it:")
    log("  ", command or "(run your system's read-only FAT check on the Kobo)")
    # Never defaulted: the reader must have run the check (--fsck-ok, or yes at the prompt).
    if not ask("Did that check finish with nothing worse than the volume being marked dirty?", False,
               True if args.fsck_ok else None, "fail" if mode == "default" else mode):
        raise Stop("Stopped: fix or investigate the filesystem first. Nothing was changed.")

    # The backup comes first; nothing is written to the Kobo before it is complete.
    if args.backup:
        backup = existing_backup(args.backup)
        log("Using the earlier backup", backup)
    elif args.no_backup:
        if not ask("Install without making a backup first (you have your own)?", False, True if args.yes else None, mode):
            raise Stop("Stopped before installing: make a backup first.")
        backup = BACKUP_ROOT / (datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S") + "-install")
    else:
        args.scope = args.backup_scope
        backup = cmd_backup(args, info)
    run = backup / "install-run"
    run.mkdir(parents=True, exist_ok=True)
    log.to_file(run / "install-log.txt")

    missing_fonts = [f for f in FONT_FILES if f not in info["fonts"]]
    fonts = bool(missing_fonts) and ask(f"Add the missing fonts ({', '.join(missing_fonts)}) for Woodland's headings?",
                                        True, args.fonts, mode)
    migrate = bool(info["legacy"]) and ask("Move Woodland Journal 0.1's files out of SimpleUI Extra (needed for the new plugin to run)?",
                                           True, args.migrate, mode)
    dictionaries = available_dictionaries()
    dictionary = None
    if args.dictionary:
        if args.dictionary not in dictionaries:
            raise Stop(f"No bundled dictionary named {args.dictionary}; available: {', '.join(dictionaries) or 'none'}.")
        dictionary = args.dictionary
    elif dictionaries and mode == "prompt":
        for name in dictionaries:
            if name not in info["dictionaries"] and ask(f"Add the dictionary {name}? Your current dictionaries stay as they are.", False):
                dictionary = name
                break

    log("")
    log("Changes to the Kobo:")
    log("  -", "update" if info["woodland"] else "add", PLUGIN_DEST.as_posix())
    if fonts:
        log("  - add", ", ".join(missing_fonts), "to", FONTS_DEST.as_posix())
    if dictionary:
        log("  - add the dictionary", dictionary, "to", (DICT_DEST / dictionary).as_posix())
    if migrate:
        log("  - move", ", ".join(info["legacy"]), "from SimpleUI Extra to", run / "removed-from-kobo")
    if not ask("Go ahead?", True, None, mode):
        raise Stop("Stopped before installing. The backup is kept; nothing on the Kobo was changed.")

    dest = kobo / PLUGIN_DEST
    previous = {}
    if (dest / MANIFEST).is_file():
        try:
            previous = json.loads((dest / MANIFEST).read_text(encoding="utf-8"))
        except ValueError:
            previous = {}
    written = {}
    # 1. The plugin. Files a previous install put there and this version no longer has are moved off.
    sources = source_files(PLUGIN_SRC)
    for rel in sources:
        written[(PLUGIN_DEST / rel).as_posix()] = copy_verified(PLUGIN_SRC / rel, dest / rel)
    current = {rel.as_posix() for rel in sources}
    for old in previous.get("plugin_files", []):
        if old not in current and (dest / old).is_file():
            move_off_kobo(dest / old, kobo, run / "removed-from-kobo")
            log("  moved off the Kobo (no longer part of Woodland):", old)
    log(f"  plugin: {len(sources)} files written and checked")
    extras = list(previous.get("extra_files", []))
    # 2. Fonts, only those missing.
    if fonts:
        for name in missing_fonts:
            target = (FONTS_DEST / name).as_posix()
            written[target] = copy_verified(FONTS_SRC / name, kobo / FONTS_DEST / name)
            extras.append(target)
        log(f"  fonts: {len(missing_fonts)} written and checked")
    # 3. Dictionary, only when chosen and not already there.
    if dictionary:
        src = DICTIONARIES_SRC / dictionary
        for rel in source_files(src):
            target = (DICT_DEST / dictionary / rel).as_posix()
            written[target] = copy_verified(src / rel, kobo / DICT_DEST / dictionary / rel)
        extras.append((DICT_DEST / dictionary).as_posix() + "/")
        log(f"  dictionary {dictionary}: written and checked")
    # 4. Woodland 0.1's files, copied off and checked before leaving the Kobo.
    if migrate:
        extra = kobo / PLUGINS / "simpleui_ext.koplugin"
        for rel in info["legacy"]:
            move_off_kobo(extra / rel, kobo, run / "removed-from-kobo")
        log("  Woodland Journal 0.1: moved to", run / "removed-from-kobo")
    # 5. Record what was installed.
    manifest = {"version": meta_version(PLUGIN_SRC), "installed": datetime.datetime.now().isoformat(timespec="seconds"),
                "tool_version": TOOL_VERSION, "backup": str(backup),
                "plugin_files": sorted(current), "extra_files": sorted(set(extras)),
                "legacy_moved": info["legacy"] if migrate else previous.get("legacy_moved", [])}
    (dest / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    shutil.copyfile(dest / MANIFEST, run / MANIFEST)
    # 6. macOS metadata files beside everything written (last, so none follow).
    sync()
    swept = []
    for folder in [dest, kobo / FONTS_DEST] + ([kobo / DICT_DEST / dictionary] if dictionary else []):
        for junk in appledouble(folder):
            swept.append(move_off_kobo(junk, kobo, run / "appledouble"))
    if swept:
        log(f"  moved {len(swept)} macOS '._' metadata files off the Kobo")
    # 7. Check every installed file once more.
    sync()
    bad = [rel for rel, digest in written.items() if sha256(kobo / rel) != digest]
    if bad:
        raise Stop("These files did not read back correctly: " + ", ".join(bad))
    log(f"  all {len(written)} written files read back correctly")
    log("")
    log("Installed Woodland Journal", manifest["version"], "on", kobo)
    log("Next:")
    log("  1. Check the filesystem again, read-only:", command or "(your system's read-only FAT check)")
    log("  2. Eject the Kobo:", eject_hint(kobo))
    log("  3. Open KOReader. Woodland asks a few setup questions the first time; Tools → Woodland Journal runs setup again.")
    log("Backup and log:", backup)
    return 0


# ── uninstall ───────────────────────────────────────────────────────────────

def cmd_uninstall(args):
    mode = answer_mode(args)
    kobo = find_kobo(args.kobo)
    dest = kobo / PLUGIN_DEST
    if not dest.is_dir():
        raise Stop("Woodland Journal is not installed on this Kobo.")
    manifest = {}
    if (dest / MANIFEST).is_file():
        try:
            manifest = json.loads((dest / MANIFEST).read_text(encoding="utf-8"))
        except ValueError:
            pass
    log("On the Kobo, Tools → Woodland Journal → Remove from home screen takes its pages out of SimpleUI first;")
    log("otherwise SimpleUI may show an empty page where the dashboard was.")
    if not ask("Have you done that (or do you not mind an empty page)?", True, None, mode):
        raise Stop("Stopped. Nothing was changed.")
    keep = BACKUP_ROOT / (datetime.datetime.now().strftime("%Y-%m-%d_%H%M%S") + "-uninstall")
    keep.mkdir(parents=True)
    log.to_file(keep / "uninstall-log.txt")
    move_off_kobo(dest, kobo, keep)
    log("Moved", PLUGIN_DEST.as_posix(), "to", keep)
    extras = [e for e in manifest.get("extra_files", []) if (kobo / e.rstrip("/")).exists()]
    if extras and ask("Also move the fonts and dictionary Woodland added (" + ", ".join(extras) + ")? "
                      "Keep them if you use them for reading.", False, args.remove_extras, mode):
        for e in extras:
            move_off_kobo(kobo / e.rstrip("/"), kobo, keep)
            log("Moved", e, "to", keep)
    legacy = manifest.get("legacy_moved", [])
    if legacy and args.restore_legacy:
        source = Path(manifest.get("backup", "")) / "kobo" / PLUGINS / "simpleui_ext.koplugin"
        for rel in legacy:
            src = source / rel
            files = [src] if src.is_file() else sorted(p for p in src.rglob("*") if p.is_file())
            for f in files:
                target = kobo / PLUGINS / "simpleui_ext.koplugin" / rel
                copy_verified(f, target / f.relative_to(src) if src.is_dir() else target)
        log("Put Woodland Journal 0.1 back into SimpleUI Extra from", source)
    sync()
    log("Done. Woodland's settings stay in KOReader's settings (simpleui_woodland_*) and are harmless.")
    log("Eject the Kobo:", eject_hint(kobo))
    return 0


# ── command line ────────────────────────────────────────────────────────────

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    def kobo_arg(p):
        p.add_argument("--kobo", help="the Kobo's folder when it is not found automatically")

    p = sub.add_parser("check", help="read-only report and plan")
    kobo_arg(p)
    p = sub.add_parser("backup", help="copy the Kobo to ~/KoboBackups/<time>/")
    kobo_arg(p)
    p.add_argument("--scope", choices=["all", "koreader"], default="all",
                   help="all: the whole Kobo as it is (default); koreader: .adds/koreader and Nickel's settings file")
    p.add_argument("--to", help="backup folder (default ~/KoboBackups/<date-time>)")
    p = sub.add_parser("install", help="back up, then install")
    kobo_arg(p)
    p.add_argument("--fsck-ok", action="store_true", help="the reader ran the read-only filesystem check and it was clean")
    p.add_argument("--backup", help="use this earlier backup instead of making a new one")
    p.add_argument("--backup-scope", choices=["all", "koreader"], default="all", help="what a new backup copies (default: all)")
    p.add_argument("--no-backup", action="store_true", help="skip the backup (the reader has their own)")
    p.add_argument("--fonts", dest="fonts", action="store_true", default=None, help="add missing Alegreya fonts")
    p.add_argument("--no-fonts", dest="fonts", action="store_false", help="do not add fonts")
    p.add_argument("--migrate", dest="migrate", action="store_true", default=None,
                   help="move Woodland Journal 0.1's files out of SimpleUI Extra")
    p.add_argument("--no-migrate", dest="migrate", action="store_false", help="leave Woodland Journal 0.1 in place")
    p.add_argument("--dictionary", help="add this bundled dictionary (default: none)")
    p.add_argument("--yes", action="store_true", help="answer the remaining questions with their defaults (for agents)")
    p = sub.add_parser("uninstall", help="move Woodland Journal off the Kobo")
    kobo_arg(p)
    p.add_argument("--remove-extras", dest="remove_extras", action="store_true", default=None,
                   help="also move the fonts and dictionary Woodland added")
    p.add_argument("--keep-extras", dest="remove_extras", action="store_false", help="keep them (default)")
    p.add_argument("--restore-legacy", action="store_true", help="put Woodland Journal 0.1 back into SimpleUI Extra")
    p.add_argument("--yes", action="store_true", help="do not ask (for agents)")
    args = parser.parse_args(argv)
    try:
        return {"check": cmd_check, "backup": lambda a: (cmd_backup(a), 0)[1],
                "install": cmd_install, "uninstall": cmd_uninstall}[args.command](args)
    except Stop as stop:
        log("")
        log(str(stop))
        return 1
    except KeyboardInterrupt:
        log("\nInterrupted.")
        return 130


if __name__ == "__main__":
    sys.exit(main())
