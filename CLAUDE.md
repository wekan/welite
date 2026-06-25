# welite — project rules

## DOS 8.3 filename rule (MUST follow)

This repo targets DOS, classic Amiga, and other retro filesystems, so the **entire tree must
stay DOS 8.3-safe**. When creating or renaming any file or directory:

- Every path component (directory name and file base name) is **at most 8 characters**.
- Every file extension is **at most 3 characters** (e.g. `.pas`, `.lpr`, `.sql`, `.jsn`, `.md`).
- Use only safe characters: letters, digits, `-`, `_`. No spaces; one dot (the extension dot).
- This applies to source, docs, data, and generated/build output alike.

Exceptions (host tooling only, never shipped to a retro target): VCS/editor dotfiles such as
`.gitignore`, `.tx/`, `.claude/`, `CLAUDE.md`, `README.md`, `CHANGES.md`.

To audit the tracked tree for violations:

```sh
git ls-files | tr '/' '\n' | sort -u | while IFS= read -r c; do
  case "$c" in .*) continue;; esac
  if printf '%s' "$c" | grep -q '\.'; then
    b=${c%.*}; e=${c##*.}; [ ${#b} -gt 8 ] || [ ${#e} -gt 3 ] && echo "BAD: $c"
  else
    [ ${#c} -gt 8 ] && echo "BAD: $c"
  fi
done
```

## Build output layout

`build.sh` / `build.bat` / `build.ami` all produce the same DOS 8.3-safe tree:

- **Per-platform build dir:** each target builds into `build/arch/<code>/`, which holds the
  executable plus its `.o` / `.ppu` / link intermediates (`fpc -FU -FE -o`). `<code>` is a
  **≤7-char** platform name (e.g. `linx64`, `dos`, `ami68k`, `aros68k`).
- **Collected binaries:** after a successful build the executable is copied to
  `build/bin/w<code>.exe` — a leading `w` (for *welite*) plus the code, e.g. `wami68k.exe`,
  `wdos.exe`, `wlinx64.exe`. The `w`+code base stays ≤8 chars (hence code ≤7). All `.exe`, so the
  binaries are unique and coexist in `build/bin/`. "Build current platform" → `build/bin/wcurrent.exe`.

When adding a platform, pick a new ≤7-char `<code>`, add it to all three build scripts, and (for
`build.ami`) add the matching `MakeDir build/arch/<code>` to the preamble.
