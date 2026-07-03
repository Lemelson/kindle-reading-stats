# Kindle Reading Stats — Passive Reading Statistics Logger (KUAL Extension)

**Track your Kindle reading time, pages turned, and reading sessions on a jailbroken Kindle — without KOReader and without patching the native reader.**

Reading Stats is a lightweight [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)
extension for **jailbroken Kindle e-readers**. It passively watches the Kindle
operating system's own log files and records selected reading metrics
(page turns, book open/close events, active reading duration) as simple,
append-only `JSONL` files that you can later copy off the device and analyze
however you like.

It is intentionally minimal, dependency-free (pure POSIX shell), and does
**not** modify Amazon's reader application, firmware, or system configuration.

> ⚠️ **For educational and personal-use purposes only.** See the
> [Disclaimer](#disclaimer--educational-use-only) section below.

---

## Keywords

`kindle reading statistics` · `kindle reading time tracker` · `kindle reading
stats` · `kindle KUAL extension` · `jailbroken kindle` · `kindle pages read` ·
`kindle reading log` · `kindle reader analytics` · `kindle without KOReader` ·
`kindle self-hosted reading data` · `kindle metrics logger`

---

## Why this exists

Amazon's native Kindle reader does not expose your raw reading data. If you
want detailed personal reading statistics you normally have to install
[KOReader](https://github.com/koreader/koreader), which replaces the reading
experience entirely.

This project takes a different approach: it **leaves the stock Amazon reader
untouched** and simply *observes* the metrics the Kindle already writes to its
own system logs (`/var/log/metrics_*`, `/var/log/messages`, `/var/log/cvm`).
Those logs already contain events such as page turns, book opens/closes, and
active reading duration. Reading Stats filters the relevant lines and saves
them in a clean, portable format under your control.

Your reading data never leaves the device unless **you** copy it off.

---

## How it works

1. When you start the logger from KUAL, a small background shell process is
   launched (`readingstats.sh collect`).
2. It records the current byte offset of each Kindle log file, then polls those
   files every ~2 seconds for newly appended lines (a tail-by-offset approach —
   no external tools required).
3. New lines are matched against a set of reader-related patterns
   (`ereader_*`, `mar_book_read_stats`, `reader.activeDuration`,
   `book_page_turn`, `open_book`, `close_book`, etc.).
4. Matching lines are parsed into structured records and appended to:

   ```text
   /mnt/us/extensions/readingstats/data/events-YYYY-MM.jsonl
   ```

Each record is one JSON object per line (JSONL), for example:

```json
{"captured_at":"2026-07-03T09:15:42Z","source":"/var/log/metrics_generic","schema":"ereader.book_page_turn","start_position":1024,"end_position":1088,"raw":"..."}
```

No re-flashing, no reader patching, no `syslog-ng.conf` changes.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **A jailbroken Kindle** | The device must be jailbroken so that KUAL and shell extensions can run. See [Jailbreak & firmware notes](#jailbreak--firmware-notes). |
| **KUAL** | The [Kindle Unified Application Launcher](https://www.mobileread.com/forums/showthread.php?t=203326) must be installed. |
| **Shell access to the Kindle filesystem** | You install the extension by copying files to `/mnt/us/extensions/`. USB Mass Storage is sufficient. |
| **`eips`** (optional) | Used to print status on the e-ink screen. Present on all standard Kindle firmware; the extension degrades gracefully if missing. |

The extension itself is **firmware-version-independent** — it relies only on
standard Kindle OS logging, which has been stable across many firmware
generations. What *does* depend on firmware is whether your device can be
jailbroken in the first place (see below).

---

## Jailbreak & firmware notes

This repository does **not** contain, distribute, or implement any jailbreak,
exploit, or firmware modification. Reading Stats is an *application-layer*
extension that assumes your device is **already** jailbroken.

Jailbreaking a Kindle is done with community tools that are **firmware-specific**
— an exploit that works on one firmware version may be patched in the next.
Because Amazon ships firmware updates frequently, the correct jailbreak for
*your* device depends on its exact firmware version (Settings → Device Options →
Device Info). Rather than repeat version numbers that go stale, please consult
the authoritative, actively maintained community sources:

- **MobileRead Kindle Developer's Corner** — <https://www.mobileread.com/forums/forumdisplay.php?f=150>
- **Kindle jailbreak / hacking wiki & threads on MobileRead** — the canonical,
  up-to-date compatibility tables for each firmware version.

General guidance:

- If you plan to jailbreak, **turn off automatic firmware updates and disable
  Wi‑Fi** until you have confirmed a working method for your firmware, so an
  update does not close the window.
- Older firmware is generally easier to jailbreak than the newest release.
- Always follow the specific, current instructions from the community for your
  device model and firmware — do not improvise.

---

## Installation

1. Jailbreak your Kindle and install KUAL (see notes above). **This is a
   prerequisite handled outside this project.**
2. Connect the Kindle to your computer via USB (it appears as a USB drive).
3. Copy this project's folder into the Kindle `extensions` directory so the
   layout is:

   ```text
   /mnt/us/extensions/readingstats/
   ├── config.xml
   ├── menu.json
   ├── README.md
   └── bin/
       └── readingstats.sh
   ```

4. Safely eject the Kindle.
5. Open **KUAL** on the device — a **Reading Stats** menu will appear.

> The `data/` and `state/` directories are created automatically on first run.
> They are intentionally excluded from version control (see `.gitignore`).

---

## Usage

Open KUAL → **Reading Stats**:

| Menu item | Action |
|-----------|--------|
| **Start Logger** | Starts background collection. |
| **Stop Logger** | Stops background collection. |
| **Logger Status** | Prints running state and total event count on screen. |
| **Export Snapshot Now** | Parses currently available `/var/log` files (and rotated `logbackup/*.gz`) once, into a timestamped snapshot. |
| **Show Today Summary** | Shows a rough same-day count of page turns, opens, and closes. |

**Note:** the current version is deliberately conservative — it does **not**
edit `/etc/syslog-ng/syslog-ng.conf`, so the collector does **not** auto-restart
after a Kindle reboot. Simply start it again from KUAL after a reboot.

---

## Data format & privacy

- Data is stored **only on your device** under
  `/mnt/us/extensions/readingstats/data/` as append-only JSONL.
- Nothing is uploaded anywhere. There is no network code in this project.
- To analyze your data, copy the `data/` folder off the Kindle over USB and
  process the JSONL with any tool you like (jq, Python, a spreadsheet, etc.).
- Because the records are derived from the Kindle's own logs, they may contain
  book identifiers/positions. Treat the exported files as personal data and do
  not commit them to any public location. (`data/` and `state/` are gitignored
  for exactly this reason.)

---

## Project layout

```text
readingstats/
├── config.xml            # KUAL extension manifest
├── menu.json             # KUAL menu definition
├── bin/readingstats.sh   # All logic (POSIX shell)
├── README.md             # This file
├── LICENSE               # MIT
└── .gitignore            # Excludes runtime data & OS cruft
```

---

## Disclaimer — educational use only

This project is published **strictly for educational and personal-use
purposes**.

- It is an independent, unofficial project. It is **not** affiliated with,
  endorsed by, or associated with Amazon in any way. "Kindle" is a trademark of
  Amazon; it is used here only descriptively to identify the compatible
  hardware.
- The software only **reads** log data that the device already generates, on
  hardware **you own**, for **your own** personal use. It does not bypass DRM,
  does not access or redistribute copyrighted book content, and does not
  transmit any data off the device.
- This repository does **not** provide a jailbreak, exploit, or firmware
  modification. Jailbreaking is discussed only at a high level with pointers to
  well-established public community resources.
- Modifying your device may void its warranty and can, if done incorrectly,
  render it unusable ("brick" it). **You proceed entirely at your own risk.**
- The authors accept **no liability** for any damage, data loss, warranty loss,
  or terms-of-service consequences arising from use of this software. See the
  [MIT License](LICENSE).

If you are a rights holder or platform representative and have a concern about
this repository, please open an issue and it will be addressed promptly.

---

## Contributing

Issues and pull requests are welcome — bug reports, additional log schemas,
better parsers, or analysis scripts for the exported JSONL.

## License

Released under the [MIT License](LICENSE).
