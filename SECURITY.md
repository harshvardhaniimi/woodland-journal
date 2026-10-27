# Security

Woodland Journal runs on your Kobo inside KOReader, and its installer runs on your computer with your user's permissions.
This page says what each part touches, what it defends against, and what it does not.
It was last reviewed for version 0.2.1; the review is in `docs/security-audit-2026-10.md`.

## Reporting a problem

Please report security problems privately through GitHub's **Report a vulnerability** button on this repository's Security tab, not in a public issue.
Say which version you used, on which device, and how to reproduce the problem.
Woodland Journal is a preview maintained by one person in their spare time, so expect a reply in days rather than hours.

## The plugin, on the Kobo

**What it reads.** KOReader's reading statistics (opened read-only), reading history, book metadata and covers, and its own settings.

**What it writes.** Its settings in KOReader's settings file (keys starting `simpleui_woodland_`), its Goodreads snapshot and covers in `settings/simpleui/woodland-goodreads/`, and, when you accept during setup or use its menu, the placement of its own two pages in SimpleUI's home-screen layout.
It changes no other module's place in that layout, and it leaves a layout of a shape it does not recognise untouched.
It never runs programs, never loads code from data, and never writes outside these places.

**The network.** Nothing leaves the Kobo unless you add a public Goodreads profile and tap Refresh.
The refresh then:

- fetches only your shelf's RSS feed from `www.goodreads.com` and cover images from Goodreads' image hosts (`i.gr-assets.com`, `s.gr-assets.com`, `images.gr-assets.com`), checking every address in full before it is requested;
- uses HTTPS, checks the certificate chain against KOReader's certificate bundle, and also checks that the certificate names the host, which KOReader's TLS library does not do by itself;
- follows a redirect only to another allowed address, at most three times, and does not run through a proxy (a proxy would see the request and stand in for Goodreads' certificate);
- sends KOReader's standard User-Agent (its version, device model and system), the profile number in the feed address, and nothing else: no account, password or cookie;
- runs in a separate process that you can cancel, and stops any download that exceeds its size limit or about 30 seconds.

**What the feed can do.** The feed and covers are treated as hostile input.
A feed page is limited to 4 MiB and 100,000 tags, documents with entity declarations or more than one top-level element are refused, and at most 200 books a page and 2,000 a shelf are kept.
Titles and authors are cut to 300 bytes and descriptions and reviews to 6,000; HTML is reduced to plain text and is never rendered or run.
Covers must be JPEG or PNG, at most 4 MiB each and 300 MiB per refresh, and a refresh stops downloading covers once less than 200 MiB is free on the Kobo.
An image whose header claims more than 6,000 pixels a side or 12 megapixels is never decoded, because decoding it could exhaust the Kobo's memory; large covers, and normal-sized files over 1 MiB, are re-encoded small.
Cover files are named only by Goodreads' numeric book id.

## The installer, on your computer

**What it touches.** It reads the Kobo, writes a backup to `~/KoboBackups/<date-time>/`, and writes only Woodland's own files on the Kobo: `.adds/koreader/plugins/woodland.koplugin/`, the Alegreya fonts in `.adds/koreader/fonts/woodland/` when they are missing and you agree, and a bundled dictionary only when you choose one that is not already there.
It never changes books, Kobo's own database or Kobo's settings, and it never deletes from the Kobo outright: whatever it takes off is first copied to the backup folder and checked.
It uses no network and runs no shell; the only programs it starts are `diskutil` or `findmnt`, to name the disk check for you.

**What it defends against.**

- **No backup, no install.** The backup of every file and folder comes first, with checksums, and it cannot be put on the Kobo itself. Skipping it must be confirmed by a person at the prompt; `--yes` never does.
- **Disk check before any write.** Installing and uninstalling both wait for you to confirm a read-only disk check. That answer is never assumed, because writing to a damaged FAT filesystem can destroy files.
- **`INSTALL.json` is untrusted.** The installer's record on the Kobo could be damaged or edited, so every path in it is checked before use.
  - Files to move off must lie inside the plugin folder.
  - Extras must be Woodland's own fonts or a dictionary folder.
  - The files of Woodland Journal 0.1 to restore must be its known file names.
  - The backup to restore from must be named by its folder in `~/KoboBackups`.
  - Anything else is ignored with a note.
  - Before any file is moved, the installer checks that it is inside the Kobo, that its destination is inside the backup folder, and that it is not a link.
- **Device text is printed safely.** Version strings and names read from the Kobo are reduced to plain letters, digits and a few punctuation marks, and shortened, before printing. Escape codes or long text planted on a Kobo cannot reach your terminal or a coding agent reading the output.
- **No private details stored.** It never reads the device's serial number (the first field of `.kobo/version`). The record it leaves on the Kobo names the backup folder, not its path, so your computer's user name is not stored there.
- **Safe writes.** Each file is written to a temporary name, flushed, read back and checked, and only then put in place.

## Known limits

- **Read-back checks.** After writing, the installer reads files back, but the computer may answer from its memory cache rather than from the Kobo. The read-only disk check after installing is the real test of the Kobo's storage, so run it.
- **XML parsing.** The bundled LuaXML parser has been hardened against the slow inputs found so far, but a crafted feed might still make a refresh slow. It would come from a host whose certificate names Goodreads, it runs in a separate process, and you can cancel it.
- **Image decoding.** Covers are decoded by KOReader's own image libraries. Woodland limits what reaches them, but cannot vouch for those libraries.
- **What Woodland relies on.** It relies on KOReader, SimpleUI and, for the sleep screen, SimpleUI Extra. Their security is their own; Woodland has been tested with the versions in the README.
- **What the installer trusts.** It trusts the computer it runs on and the copy of this repository you run it from. Download it from the repository's own page or releases.
- **Developer tools.** The desktop harness (`harness/`) is for development only: it runs a downloaded KOReader build against copies of a backup, and refuses to write into folders that `setup_sandbox.sh` did not create.
