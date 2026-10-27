# Woodland Journal

A reading dashboard for **KOReader on Kobo**, built as an add-on for the [SimpleUI](https://github.com/doctorhetfield-cmd/simpleui.koplugin) home screen.
Tree rings grow with the book you are reading, a week of reading minutes sits against your daily goal, the books you have in progress are a tap away, and an optional second page keeps an offline copy of your Goodreads shelves.

> **Status: preview, not yet released.**
> Woodland Journal has been used daily on exactly one e-reader.
> It is checked on other screen sizes only in KOReader's desktop build, never on those devices.
> Back up your Kobo before installing it, and expect rough edges anywhere else.

| Tested on | |
|---|---|
| Device | Kobo Libra Colour (the author's own) |
| Kobo firmware | 4.45.23792 |
| KOReader | v2026.07.1 |
| SimpleUI | 2.7.5 |
| SimpleUI Extra (optional, for the sleep screen) | 1.15.0 |
| Desktop layout checks | KOReader macOS nightly v2026.07.2-275, emulating the screens of the Libra Colour, Libra 2, Clara Colour, Clara BW, Sage, Elipsa 2E and Nia in portrait: no layout findings. Not checked on the devices themselves. |

## What it does

- **Current book.** Cover, title, author, pages and time left, a Continue reading button, and ten irregular tree rings that fill as you read.
- **Finished book.** When you mark a book finished, or read to its last page, the dashboard says so, shows the finish date and offers your library.
- **Your week.** Today's minutes against your goal, your reading streak, books finished this year, and seven days of reading with the minutes under every day.
- **Also reading.** Up to two other books in progress, each opening where you left off.
- **Goodreads, if you want it.** A second home page with your public Goodreads shelves, saved for offline reading, and a page for each book with its description and your review. Without a Goodreads profile, the page does not exist and the dashboard says "Goodreads not available".
- **A quiet quote** from a public-domain book each day.
- **Colour or monochrome.** Colour on Kobo colour screens, greys on black-and-white ones, chosen automatically.
- **Portrait.** The dashboard is designed for portrait. In landscape SimpleUI shows it in a narrow column, where its buttons are smaller than KOReader's own.

Nothing is sent anywhere unless you add a Goodreads profile and tap Refresh on Wi-Fi.

## What you need

1. A Kobo with **KOReader** installed. If you do not have it yet, follow KOReader's own [installation guide for Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) first.
2. **SimpleUI** installed in KOReader ([releases](https://github.com/doctorhetfield-cmd/simpleui.koplugin/releases/latest)).
3. A computer with Python 3.8 or later for the installer.
4. Optionally, **SimpleUI Extra** ([repository](https://github.com/omer-faruq/simpleui_ext.koplugin)) to show the dashboard as your sleep screen.

## Installing

Connect your Kobo by USB and tap **Connect** on it.
The installer needs Python 3.8 or later (built into macOS and most Linux; on Windows, from python.org).

### With a coding agent

If you use Claude Code, Codex or a similar agent, open it in a copy of this repository and paste:

```text
Install Woodland Journal on my Kobo by following AGENTS.md in this repository.
Back up my Kobo first, explain each step, and ask me before anything optional.
```

The agent runs the installer, asks you to run one read-only disk check (it needs your password), asks about the optional parts, and tells you when it is safe to unplug.

If KOReader is not on your Kobo yet, install it first with KOReader's [guide for Kobo](https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices), or ask your agent:

```text
Help me install KOReader on my Kobo using only KOReader's official guide
(https://github.com/koreader/koreader/wiki/Installation-on-Kobo-devices) and its official release.
Back up my Kobo first and ask me before every step.
```

### By yourself

```sh
python3 install.py check      # what is on your Kobo and what would change; changes nothing
python3 install.py install    # backs up the whole Kobo, asks a few questions, installs
```

`check` prints a read-only disk check for your computer (on a Mac, `sudo fsck_msdos -n /dev/rdiskN`); run it before installing and again afterwards.
The installer:

- copies everything on the Kobo to `~/KoboBackups/<date-time>/` first and checks every file it copied;
- adds only `woodland.koplugin` to KOReader's plugins, plus the Alegreya fonts if they are missing and you agree;
- asks before adding the optional English–Hindi dictionary, when a download includes it; your current dictionaries stay as they are;
- moves Woodland Journal 0.1 out of SimpleUI Extra if you have it (the new plugin needs that), keeping it in the backup folder;
- never changes your books, Kobo's own database or Kobo settings.

Eject the Kobo before unplugging it.
To undo, use **Tools → Woodland Journal → Remove from home screen** on the Kobo, then `python3 install.py uninstall`.
To go back completely, copy the backup's `kobo/` folder back onto the Kobo.

### First start

Woodland asks for the name to greet you with (optional), suggests a daily goal from your recent reading, asks whether to add your Goodreads profile, and offers to place the dashboard on your home screen.
You can run it again from **Tools → Woodland Journal → Set up Woodland Journal**.

## Privacy and network

Woodland Journal reads KOReader's own reading statistics, history and book metadata on the device.
It writes only its settings (in KOReader's settings, under `simpleui_woodland_*`), its Goodreads snapshot (`settings/simpleui/woodland-goodreads/`) and, when you accept during setup, the placement of its own pages in SimpleUI's home-screen layout.
The only network access is the Goodreads refresh you start yourself: it fetches your shelf's public RSS feed from `www.goodreads.com` and cover images from Goodreads' image hosts, over verified HTTPS, with size limits.
No password or account is involved, and your profile must be public.

## Development

- `woodland.koplugin/` is the plugin; `woodland_journal/` holds its code and artwork.
- `tests/run.sh` runs the unit tests with LuaJIT (`luajit`, or TeX Live's `luajittex`).
- `harness/` drives KOReader's macOS desktop build headlessly against a sandbox made from a Kobo backup; see `AGENTS.md`.

## Credits and licences

Woodland Journal is free software under the GNU Affero General Public License v3 or later (`LICENSE`).
It builds on [SimpleUI](https://github.com/doctorhetfield-cmd/simpleui.koplugin) by Doctor Hetfield and began as a module for [SimpleUI Extra](https://github.com/omer-faruq/simpleui_ext.koplugin).
The XML parser is LuaXML, © 2016 Manoel Campos da Silva Filho, under the MIT licence (`woodland_journal/LICENSE_LuaXML`).
Alegreya is © 2011 The Alegreya Project Authors, under the SIL Open Font License 1.1 (`fonts/alegreya/OFL.txt`).
The robin and woodland illustrations were generated for this project with OpenAI image models.
The daily quotes are from public-domain works by Emily Dickinson, Henry David Thoreau, Francis Bacon and Louisa May Alcott.
