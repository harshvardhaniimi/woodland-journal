# Security audit, October 2026 (versions 0.2.0 → 0.2.1)

## Scope and method

This audit covered everything in the repository before its first public release:
- the KOReader plugin (`woodland.koplugin/`, including the bundled LuaXML parser);
- the installer (`install.py`);
- the instructions coding agents follow (`AGENTS.md`, `README.md`);
- the developer harness (`harness/`).

Version 0.2.0 had been installed on one device only, the author's, and was never published.

**Independent reviews.** Two reviewers read all the code independently. They were given the threat model but none of the maintainer's conclusions, so their reading was not anchored on it:
- one reviewed the plugin;
- the other reviewed the installer, the agent instructions and the harness.

**The maintainer's own check.** Alongside them, the maintainer checked how Woodland's dependencies actually behave in the KOReader build it runs on (KOReader v2026.07.1, LuaSec 1.3.2, LuaSocket), rather than how they are documented.

**Confirming findings.**
- The installer findings were reproduced against fake Kobo folders.
- The plugin findings were traced in the code, and the network ones were also tested in KOReader's desktop build against Goodreads' public servers.
- Every fix has a regression test.
- The installer tests were also run against the 0.2.0 installer, where they fail, which shows they catch the original problems.

Severity reflects what an attacker needs and what they gain:
- a hostile network position, or a tampered Goodreads response, for the plugin;
- a tampered or damaged file on the Kobo, for the installer.

## Findings

### Installer

| # | Severity | Finding | Status |
|---|---|---|---|
| I1 | Critical | Paths listed in the `INSTALL.json` left on the Kobo were used without checks. On a reinstall, entries such as `../../../../.kobo/KoboReader.sqlite` moved books, Kobo's database, or files on the computer. A crafted entry could also make a file its own copy target, emptying it before removal. | Fixed: entries must be plain relative paths inside the plugin folder, and every move checks its source is on the Kobo, its destination is in the backup folder, and neither is a link. |
| I2 | High | Uninstall with `--remove-extras` moved whatever the manifest's `extra_files` named, including an empty entry that meant the whole Kobo. | Fixed: only Woodland's own font files and dictionary folders are accepted. |
| I3 | High | `--restore-legacy` took both the backup path and the file names from the manifest. A tampered Kobo could overwrite any file on the computer, for example a shell startup file, which leads to running code there. | Fixed: file names must be Woodland 0.1's known ones. The backup is found by its folder name in `~/KoboBackups` or named by the user. It must be a real backup, not on the Kobo, and of the same model. Nothing moves until all of this is checked. |
| I4 | Medium | `INSTALL.json` on the Kobo stored the backup's full path, including the computer's user name. | Fixed: only the folder name is stored. |
| I5 | Medium | The README, `AGENTS.md` and the installer's own message advised restoring by copying the whole backup back. That includes Kobo's database, and an old copy triggers the destructive factory setup this project's rules warn about. | Fixed: the instructions now say to recover single files and never to copy `kobo/.kobo/` back. |
| I6 | Medium | `AGENTS.md` allowed an agent to start the `sudo` disk check itself, and put `--fsck-ok` in the command to run. It also mixed hand-copying rules into the install guide, linked SimpleUI's latest release rather than the tested version, and did not cover KOReader's own install writing to `.kobo/`. | Fixed: the reader runs all privileged commands. `--fsck-ok` is passed only after the reader reports a clean check. The contributor rules are separated, the tested SimpleUI version is named, and agents are told to treat installer output as data. |
| I7 | Medium | Uninstall moved and restored files without the read-only disk check that install requires. | Fixed: uninstall needs it too. |
| I8 | Low | `--no-backup --yes` skipped the backup without a person confirming. | Fixed: skipping the backup is accepted only at an interactive prompt. |
| I9 | Low | `--dictionary` overwrote a dictionary of the same name already on the Kobo and recorded it as Woodland's, so a later uninstall could take it off. | Fixed: an existing dictionary is left alone and not recorded. |
| I10 | Low | Version strings and names read from the Kobo were printed as found, so escape codes or planted text could reach the terminal or an agent reading the output. | Fixed: they are reduced to plain characters and shortened. |
| I11 | Low | Robustness problems. | Fixed apart from one limit, below. |
| I12 | Low | The backup skipped empty folders, and skipped folders named like system folders at any depth, not only at the top. | Fixed. |
| I13 | Low | The macOS `._` file beside each new folder was left on the Kobo. | Fixed: it is moved off with the others. |
| I14 | Low | The printed eject command did not quote the volume path. | Fixed. |

The robustness problems in I11 were:
- a manifest that was not a JSON object crashed the installer after writing;
- several errors ended in tracebacks;
- files were overwritten in place rather than through a temporary file;
- a reused backup's log was overwritten;
- a backup of another model was accepted;
- after an upgrade, the record pointed a later restore at the newest backup, which no longer held Woodland Journal 0.1, so the restore refused unless given the earlier backup;
- two backups started in the same second collided.

The one that remains is in the known limits: the read-back check may be answered from the computer's cache.

### Plugin

| # | Severity | Finding | Status |
|---|---|---|---|
| P1 | High | KOReader's TLS library (LuaSec 1.3.2) checks a certificate's chain but not that it names the host. Anyone holding any publicly trusted certificate, for example on hostile Wi-Fi, could stand in for Goodreads. Requesting Goodreads' image server by IP address showed this: LuaSec accepted the session. | Fixed: after the handshake, Woodland checks the certificate's DNS names against the host and refuses the connection otherwise. The same IP-address request is now refused. |
| P2 | Medium | LuaSocket followed HTTPS redirects to any host, bypassing Woodland's address allow-list. | Fixed: at most three redirects are followed, by hand, each checked against the allow-list. |
| P3 | Medium | A small image whose header claims enormous dimensions was decoded in full, in KOReader's main process, each time the Goodreads page was drawn. It could exhaust memory and crash KOReader repeatedly. | Fixed: images over 6,000 px a side or 12 megapixels are never saved or decoded. |
| P4 | Medium | Feed fields other than descriptions had no length limit, and pages had no item limit. Every visit to the page could freeze KOReader's main process, until the snapshot was replaced. | Fixed: fields, items per page, page size and tag count are limited. |
| P5 | Medium-low | Covers could fill the Kobo's storage. Failed writes could leave truncated covers that were never fetched again. A cancelled refresh left temporary files behind. | Fixed: per-cover and per-refresh limits, a free-space floor, checked writes, cleanup of temporary files, and re-encoding of oversized files. |
| P6 | Low | With KOReader's proxy setting on, the certificate check would have run against the proxy. | Fixed: the refresh refuses to run through a proxy. |
| P7 | Low | Addresses were checked only at the start, so line breaks later in a cover address could reach the HTTP request line. | Fixed: addresses are matched in full. |
| P8 | Low | A very long book id aborted the whole refresh. | Fixed: ids are limited to 12 digits. |
| P9 | Low | Documents with many top-level elements made the XML handler re-reduce its whole tree on each one, which takes quadratic time. 8,000 elements took 0.55 s, and more would take minutes on a Kobo. | Fixed: a second top-level element is refused immediately. |
| P10 | Low | When a cover was shrunk, the full-size bitmap was left for the garbage collector to free. | Fixed: it is freed at once. |
| P11 | Low | A home-screen layout of an unexpected shape could make a layout change half-write and then fail inside a dialog. | Fixed: such a layout is left untouched, and the calls are guarded. |
| P12 | Low | The download had a size limit but no overall time limit, so a slow server could keep it open. | Fixed: about 30 seconds per address, including redirects. |
| P13 | Low | Page counts were compared without converting them to numbers. | Fixed. |

One reported concern was checked and not reproduced: whitespace trimming in the XML parser stayed linear on 100,000-character runs.
Another was accepted, and is listed under known limits: the parser's attribute patterns might be slow on very long crafted tags.

### Developer harness

`setup_sandbox.sh` had five problems:
- it pasted the sandbox path into `sed` and SQL, so `&`, `#`, `\` or `'` in the path broke the command;
- it mangled file names with leading spaces;
- it could write into the backup if pointed at it;
- it expected the Kobo root rather than an installer backup;
- the desktop runs defaulted to a fixed time zone.

`run.sh` ran `rsync --delete` without checking that its target was a sandbox.
`matrix.sh` carried on after a failed sandbox setup.

All are fixed:
- paths are passed to the scripts as data;
- sandboxes carry a marker file, and `run.sh` writes only into marked folders;
- an installer backup is accepted directly;
- the time zone comes from `TZ`.

## Checked and found sound

**Installer.**
- Never reads the device serial number.
- Imports no network modules and runs no shell; its only subprocesses are `diskutil` and `findmnt`, with argument lists and timeouts.
- Never defaults the disk-check answer.
- Finishes the backup before anything is written to the Kobo, and refuses to overwrite an existing backup.
- Moves Woodland 0.1 only by its fixed file names.
- Neither `os.walk` nor the folder removal follows links.

**Plugin.**
- Uses no `os.execute`, `io.popen`, `load` or `loadstring`; `dofile` only on its own `_meta.lua`.
- Stores the snapshot as JSON and passes data between processes as plain values.
- Reads the statistics database read-only, with only integers in its queries.
- Names cover files only by validated numeric ids.
- Writes settings only under `simpleui_woodland_*`, and in SimpleUI's layout only its own module ids.
- Refuses XML entity declarations.
- Logs no personal data.
- Uses the network only for the refresh the reader starts.

## Verification

- **Unit and installer tests:** 111 core checks, 11 colour-refresh checks and 27 installer tests pass. Thirteen of the installer tests are new, and each of them fails against the 0.2.0 installer.
- **TLS against live servers, in KOReader's macOS build:**
  - the real feed and a real cover download through the new checked connection;
  - a request to Goodreads' image server by IP address is refused.
- **Offline refresh:** a refresh runs end to end inside KOReader with the network replaced by the test feed and a local image. It made exactly four requests, removed a stale temporary file, saved three covers, and re-encoded a cover carrying 2 MB of extra data down to 29 KB.
- **Full sandbox:** a sandbox built from a full device backup, at a path containing a space, `'`, `&` and `#`, renders the dashboard and all 23 pages of a 137-book Goodreads shelf with no errors. Covers over 1 MB are re-encoded on first view.

## Known limits

- **Read-back checks.** They may be answered from the computer's cache; the read-only disk check after installing remains the real test of the Kobo's storage.
- **XML parsing.** A crafted feed from a host whose certificate names Goodreads might still make the cancellable refresh slow.
- **Image decoding.** Covers are decoded by KOReader's own image libraries, which Woodland cannot vouch for.
- **What Woodland relies on.** KOReader, SimpleUI and SimpleUI Extra are outside this audit.

## Installed

Version 0.2.1 replaced 0.2.0 on the author's Kobo Libra Colour on 27 October 2026, through `install.py`.
- **Before:** a clean read-only disk check, then a fresh full backup.
- **During:** eight plugin files and the install record were rewritten, and the stray macOS metadata file was moved off.
- **After:** a diff of the whole Kobo against the backup showed nothing else had changed, and the read-only disk check was clean again.
