#!/usr/bin/env python3
"""Annotate every glyph declaration in fontdef.txt with a `; char NAME` comment.

Each `+xxxx` line gets the UTF-8 character and its Unicode name appended after
anything already on the line (e.g. the `\t"o"` transliteration):

    +00e9	"e" ; é LATIN SMALL LETTER E WITH ACUTE
    +25e6 ; ◦ WHITE BULLET

The annotation sits *after* the transliteration, so the mkfont.c parser never
needs to read it: it stops at the closing quote, or treats a leading `;` as
"no transliteration".  mkfont.c reads lines into a 64-byte buffer, so the
script refuses to write any annotated line that would not fit (max is 63
bytes including the newline).

Bytes: the file gains no BOM and is written back UTF-8; its syntax-level
content stays pure ASCII, which is exactly what the C parser scans.

Idempotent: re-running leaves lines that already carry the annotation alone.
"""
import argparse, os, re, sys, tempfile, unicodedata

MAXLINE = 63  # mkfont.c reads lines with fgets(buf, 64, stdin)

def annotation_for(cp):
    """Return the text to append (leading space included), or None unmappable."""
    try:
        name = unicodedata.name(chr(cp))
    except ValueError:
        return None
    if not chr(cp).isprintable():
        return f" ; U+{cp:04X}"
    return f" ; {chr(cp)} {name}"


def update_fontdef(fontdef, check=False):
    """Append the annotation to every `+xxxx` line.  Returns (changed, skipped)."""
    with open(fontdef, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raise SystemExit(f"{fontdef}: leading UTF-8 BOM breaks mkfont.c's "
                         "+%x scan (it stops the U+0000 line from parsing); "
                         "strip it before annotating")

    text = raw.decode("utf-8")  # non-UTF-8 bytes would be a real C hazard
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.split("\n")

    changed = skipped = missing = bad = 0
    for n, line in enumerate(lines):
        body = line[:-1] if line.endswith("\r") else line
        m = re.match(r"^\+([0-9a-fA-F]+)", body)
        if not m:
            continue
        annot = annotation_for(int(m.group(1), 16))
        if annot is None:
            missing += 1
            continue
        if body.endswith(annot):
            skipped += 1
            continue
        new = body + annot
        size = len((new + newline).encode("utf-8"))
        if size > MAXLINE:
            bad += 1
            print(f"error: {body} + annotation is {size} bytes, "
                  f"over mkfont.c's {MAXLINE}-byte fgets limit", file=sys.stderr)
            continue
        lines[n] = new
        changed += 1

    if bad:
        raise SystemExit(f"{fontdef}: {bad} line(s) would not fit; "
                         "shorten the mapping or grow buf in mkfont.c")

    if changed and not check:
        d = os.path.dirname(os.path.abspath(fontdef))
        fd, tmp = tempfile.mkstemp(dir=d)
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(newline.join(lines))
        os.replace(tmp, fontdef)

    return changed, skipped, missing


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("-f", "--fontdef", default="fontdef.txt",
                    help="font definition file to annotate (default: fontdef.txt)")
    ap.add_argument("-c", "--check", action="store_true",
                    help="verify only: report what would change, write nothing")
    args = ap.parse_args()

    changed, skipped, missing = update_fontdef(args.fontdef, args.check)
    print(f"{args.fontdef}: {changed} line(s) annotated, {skipped} already done, "
          f"{missing} skipped" + (" [check only, no changes]" if args.check else ""))


if __name__ == "__main__":
    main()