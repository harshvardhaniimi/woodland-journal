"""install.py against fake Kobo folders: what it writes, what it moves, and
that it changes nothing else. Usage: python3 tests/test_install.py"""
import contextlib
import hashlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("woodland_install", REPO / "install.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

SERIAL = "N4280A1B2C3D4"


def snapshot(root):
    """Relative path -> sha256 for every file under root."""
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(root.rglob("*")) if p.is_file()}


def write(path, text="x"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_kobo(root, simpleui=True, extra=True, legacy=False, fonts_in_root=False):
    write(root / ".kobo" / "version", f"{SERIAL},4.1.15,4.45.23792,4.1.15,4.1.15,00000000-0000-0000-0000-000000000390")
    write(root / ".kobo" / "KoboReader.sqlite", "nickel database")
    write(root / ".kobo" / "Kobo" / "Kobo eReader.conf", "[Reading]\n")
    write(root / ".kobo" / "dropbox" / "Walden.epub", "book")
    write(root / ".Spotlight-V100" / "index", "macOS index")
    k = root / ".adds" / "koreader"
    write(k / "git-rev", "v2026.07.1\n")
    write(k / "settings.reader.lua", "return {}\n")
    write(k / "fonts" / "noto" / "NotoSerif-Regular.ttf", "font")
    if simpleui:
        write(k / "plugins" / "simpleui.koplugin" / "_meta.lua", 'return { version = "2.7.5" }\n')
        write(k / "plugins" / "simpleui.koplugin" / "main.lua", "-- simpleui\n")
    if extra:
        e = k / "plugins" / "simpleui_ext.koplugin"
        write(e / "_meta.lua", 'return { version     = "1.15.0" }\n')
        write(e / "modules" / "module_hero_currently.lua", "-- extra module\n")
        if legacy:
            write(e / "modules" / "module_woodland_journal.lua", "-- woodland 0.1\n")
            write(e / "modules" / "module_woodland_goodreads.lua", "-- woodland 0.1 goodreads\n")
            write(e / "woodland" / "scene.lua", "-- woodland 0.1 scene\n")
            write(e / "woodland" / "assets" / "robin.png", "png")
    if fonts_in_root:
        write(root / "fonts" / "Alegreya-Bold.ttf", "font")
        write(root / "fonts" / "Alegreya-Italic.ttf", "font")
    return root


class InstallerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.kobo = self.root / "KOBOeReader"
        installer.BACKUP_ROOT = self.root / "KoboBackups"
        installer.log.lines, installer.log.path = [], None

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = installer.main(list(argv) + ["--kobo", str(self.kobo)])
        return code, out.getvalue()

    def backups(self):
        return sorted(p for p in installer.BACKUP_ROOT.iterdir()) if installer.BACKUP_ROOT.exists() else []

    def test_check_needs_koreader_and_simpleui(self):
        make_kobo(self.kobo, simpleui=False)
        code, out = self.run_cli("check")
        self.assertEqual(code, 2)
        self.assertIn("SimpleUI is not installed", out)
        self.assertNotIn(SERIAL, out)

    def test_check_reads_versions_without_serial(self):
        make_kobo(self.kobo, legacy=True)
        code, out = self.run_cli("check")
        self.assertEqual(code, 0)
        self.assertIn("4.45.23792", out)
        self.assertIn("v2026.07.1", out)
        self.assertIn("2.7.5", out)
        self.assertIn("0.1 inside SimpleUI Extra", out)
        self.assertNotIn(SERIAL, out)

    def test_not_a_kobo(self):
        self.kobo.mkdir()
        code, out = self.run_cli("check")
        self.assertEqual(code, 1)
        self.assertIn("does not look like a Kobo", out)

    def test_backup_is_complete_and_checked(self):
        make_kobo(self.kobo, legacy=True)
        before = snapshot(self.kobo)
        code, _ = self.run_cli("backup")
        self.assertEqual(code, 0)
        [backup] = self.backups()
        copied = snapshot(backup / "kobo")
        expected = {k: v for k, v in before.items() if not k.startswith(".Spotlight-V100/")}
        self.assertEqual(copied, expected)
        self.assertEqual(snapshot(self.kobo), before, "a backup must not change the Kobo")
        sums = (backup / "SHA256SUMS").read_text().splitlines()
        self.assertEqual(len(sums), len(expected))
        record = json.loads((backup / "backup.json").read_text())
        self.assertEqual(record["files"], len(expected))
        self.assertNotIn(SERIAL, (backup / "backup.json").read_text())

    def test_install_stops_without_filesystem_check(self):
        make_kobo(self.kobo)
        before = snapshot(self.kobo)
        code, out = self.run_cli("install", "--yes")
        self.assertEqual(code, 1)
        self.assertIn("Need an answer", out)
        self.assertEqual(snapshot(self.kobo), before)
        self.assertEqual(self.backups(), [], "no backup before the check is confirmed")

    def test_install_stops_without_simpleui(self):
        make_kobo(self.kobo, simpleui=False)
        before = snapshot(self.kobo)
        code, out = self.run_cli("install", "--yes", "--fsck-ok")
        self.assertEqual(code, 1)
        self.assertIn("SimpleUI is not installed", out)
        self.assertEqual(snapshot(self.kobo), before)

    def test_fresh_install_writes_only_its_own_files(self):
        make_kobo(self.kobo)
        before = snapshot(self.kobo)
        code, out = self.run_cli("install", "--yes", "--fsck-ok")
        self.assertEqual(code, 0, out)
        after = snapshot(self.kobo)
        changed = {k for k in set(before) | set(after) if before.get(k) != after.get(k)}
        allowed = (".adds/koreader/plugins/woodland.koplugin/", ".adds/koreader/fonts/woodland/")
        self.assertTrue(changed and all(k.startswith(allowed) for k in changed), sorted(changed))
        plugin = self.kobo / installer.PLUGIN_DEST
        for rel in installer.source_files(installer.PLUGIN_SRC):
            self.assertEqual((plugin / rel).read_bytes(), (installer.PLUGIN_SRC / rel).read_bytes(), rel)
        for name in installer.FONT_FILES:
            self.assertTrue((self.kobo / installer.FONTS_DEST / name).is_file(), name)
        manifest = json.loads((plugin / installer.MANIFEST).read_text())
        self.assertEqual(manifest["version"], installer.meta_version(installer.PLUGIN_SRC))
        self.assertEqual(sorted(manifest["extra_files"]), sorted(f".adds/koreader/fonts/woodland/{n}" for n in installer.FONT_FILES))
        [backup] = self.backups()
        self.assertEqual(snapshot(backup / "kobo"), {k: v for k, v in before.items() if not k.startswith(".Spotlight")})
        self.assertTrue((backup / "install-run" / "install-log.txt").is_file())

    def test_fonts_already_present_are_not_added(self):
        make_kobo(self.kobo, fonts_in_root=True)
        code, out = self.run_cli("install", "--yes", "--fsck-ok")
        self.assertEqual(code, 0, out)
        self.assertFalse((self.kobo / installer.FONTS_DEST).exists())

    def test_no_fonts_flag(self):
        make_kobo(self.kobo)
        code, out = self.run_cli("install", "--yes", "--fsck-ok", "--no-fonts")
        self.assertEqual(code, 0, out)
        self.assertFalse((self.kobo / installer.FONTS_DEST).exists())

    def test_migration_moves_woodland_01_and_keeps_it(self):
        make_kobo(self.kobo, legacy=True)
        extra = self.kobo / ".adds/koreader/plugins/simpleui_ext.koplugin"
        legacy_before = snapshot(extra)
        code, out = self.run_cli("install", "--yes", "--fsck-ok")
        self.assertEqual(code, 0, out)
        self.assertEqual(sorted(snapshot(extra)), ["_meta.lua", "modules/module_hero_currently.lua"])
        [backup] = self.backups()
        kept = snapshot(backup / "install-run" / "removed-from-kobo" / ".adds/koreader/plugins/simpleui_ext.koplugin")
        self.assertEqual(kept, {k: v for k, v in legacy_before.items() if k not in ("_meta.lua", "modules/module_hero_currently.lua")})

    def test_no_migrate_leaves_woodland_01(self):
        make_kobo(self.kobo, legacy=True)
        code, out = self.run_cli("install", "--yes", "--fsck-ok", "--no-migrate")
        self.assertEqual(code, 0, out)
        self.assertTrue((self.kobo / ".adds/koreader/plugins/simpleui_ext.koplugin/woodland/scene.lua").is_file())

    def test_upgrade_moves_dropped_files_and_sweeps_appledouble(self):
        make_kobo(self.kobo)
        self.assertEqual(self.run_cli("install", "--yes", "--fsck-ok")[0], 0)
        plugin = self.kobo / installer.PLUGIN_DEST
        manifest = json.loads((plugin / installer.MANIFEST).read_text())
        manifest["plugin_files"].append("woodland_journal/retired.lua")
        (plugin / installer.MANIFEST).write_text(json.dumps(manifest))
        write(plugin / "woodland_journal" / "retired.lua", "-- dropped in a later version\n")
        write(plugin / "notes-by-the-reader.txt", "mine\n")
        write(plugin / "woodland_journal" / "._scene.lua", "appledouble")
        code, out = self.run_cli("install", "--yes", "--fsck-ok", "--backup", str(self.backups()[0]))
        self.assertEqual(code, 0, out)
        self.assertFalse((plugin / "woodland_journal" / "retired.lua").exists())
        self.assertFalse((plugin / "woodland_journal" / "._scene.lua").exists())
        self.assertTrue((plugin / "notes-by-the-reader.txt").is_file(), "unknown files are left alone")
        run = self.backups()[0] / "install-run"
        self.assertTrue((run / "removed-from-kobo" / installer.PLUGIN_DEST / "woodland_journal" / "retired.lua").is_file())
        self.assertTrue((run / "appledouble" / installer.PLUGIN_DEST / "woodland_journal" / "._scene.lua").is_file())

    def test_uninstall_moves_plugin_and_keeps_extras_by_default(self):
        make_kobo(self.kobo, legacy=True)
        self.assertEqual(self.run_cli("install", "--yes", "--fsck-ok")[0], 0)
        code, out = self.run_cli("uninstall", "--yes")
        self.assertEqual(code, 0, out)
        self.assertFalse((self.kobo / installer.PLUGIN_DEST).exists())
        self.assertTrue((self.kobo / installer.FONTS_DEST / "Alegreya-Bold.ttf").is_file())
        kept = [p for p in self.backups() if p.name.endswith("-uninstall")]
        self.assertEqual(len(kept), 1)
        self.assertTrue((kept[0] / installer.PLUGIN_DEST / "main.lua").is_file())

    def test_uninstall_restores_woodland_01_and_extras(self):
        make_kobo(self.kobo, legacy=True)
        extra = self.kobo / ".adds/koreader/plugins/simpleui_ext.koplugin"
        legacy_before = snapshot(extra)
        self.assertEqual(self.run_cli("install", "--yes", "--fsck-ok")[0], 0)
        code, out = self.run_cli("uninstall", "--yes", "--remove-extras", "--restore-legacy")
        self.assertEqual(code, 0, out)
        self.assertEqual(snapshot(extra), legacy_before)
        self.assertFalse((self.kobo / installer.FONTS_DEST / "Alegreya-Bold.ttf").exists())


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0], "-v"], exit=False).result
    sys.exit(0 if result.wasSuccessful() else 1)
