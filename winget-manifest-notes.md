# Publishing this build to winget

`winget-manifest/` contains ready-to-submit manifests for
[winget-pkgs](https://github.com/microsoft/winget-pkgs). This file is the short
version: why they look the way they do, and what to run.

Validated locally with `winget validate --manifest winget-manifest` (winget
1.29). Note the manifests must be the only files in the directory they are
validated from — `winget` reads every file there, so keep this README outside it.

## Why the identifier is `yiuf63.KOReader`, not `KOReader.KOReader`

winget's policy is that a third-party build is identified by whoever *builds*
it, not by the original author ([#180229](https://github.com/microsoft/winget-pkgs/issues/180229),
and maintainer guidance in [#11378](https://github.com/microsoft/winget-pkgs/discussions/11378),
[#262346](https://github.com/microsoft/winget-pkgs/discussions/262346)). Upstream
does not publish a Windows build, so `KOReader.KOReader` would imply it does.
The `Publisher` field follows the same rule. Precedent: `Gyan.FFmpeg`,
`BtbN.FFmpeg.GPL`, `Hibbiki.Chromium`.

No package named KOReader exists in winget today, and the `koreader` moniker is
free — verified by scanning the community index (15,548 identifiers), not by
searching. So this is a new package rather than a conflict.

## Why the version has no leading `v`

`winget` trims a leading non-digit preamble before comparing versions, so
`v2026.10-win32.2` and `2026.10-win32.2` compare equal — the `v` carries no
information. The `-win32.N` suffix scheme is fine and has precedent
(`arndawg.tmux-windows` uses `3.6a-win32.7`).

Sorting works as intended: `…-win32.2 < …-win32.10 < 2026.11-win32.1`.

## The two fields that matter most

**`RelativeFilePath: koreader\koreader.exe`** — backslashes, and relative to the
archive root. The zip's only top-level component is `koreader/`; verified by
listing its 1,176 entries rather than inferring it from the asset's filename
(which contains a different-looking path). Getting this wrong fails validation
immediately.

**`ArchiveBinariesDependOnPath: true`** — this application finds `libs/` and
`common/` relative to its working directory (51 DLLs plus the Lua sources).
winget's default for a portable app is to symlink the executable into
`WinGet\Links`, which would start it from the wrong directory and leave it
unable to load its own libraries. See
[winget-cli#2711](https://github.com/microsoft/winget-cli/issues/2711). The whole
archive is still extracted, so only the executable needs enumerating.

## Updating the manifests for a new release

1. Publish the release first, then take the **asset's** SHA256. GitHub exposes
   its own server-side digest, which is authoritative — it is what the
   validation pipeline will compute:

   ```sh
   gh api repos/yiuf63/koreader-windows/releases/tags/vX --jq '.assets[0].digest'
   ```

2. Update all three files: `PackageVersion` in each, plus `InstallerUrl`,
   `InstallerSha256` and `ReleaseDate` in the installer manifest and
   `ReleaseNotesUrl` in the locale manifest.

3. Validate and sanity-check the URL is reachable:

   ```sh
   winget validate --manifest winget-manifest
   ```

## Submitting

Manifests live at `manifests/<first-letter>/<Publisher>/<PackageName>/<Version>/`:

```
manifests/y/yiuf63/KOReader/2026.10-win32.2/
```

```sh
# fork microsoft/winget-pkgs, then:
git checkout -b yiuf63-koreader-2026.10-win32.2
mkdir -p manifests/y/yiuf63/KOReader/2026.10-win32.2
cp winget-manifest/*.yaml manifests/y/yiuf63/KOReader/2026.10-win32.2/
git add manifests/y/yiuf63/KOReader
git commit -m "New package: yiuf63.KOReader version 2026.10-win32.2"
```

Open the PR with the title `New package: yiuf63.KOReader version 2026.10-win32.2`
and sign the CLA at <https://cla.opensource.microsoft.com/microsoft/winget-pkgs>.

One version per PR, manifest files only. Validation runs ~10 automated steps,
then a moderator reviews; expect days rather than hours, and note that new
packages get more scrutiny than updates.

## What to expect

Two review points worth pre-empting in the PR description:

- **Domain validation.** Step 04 checks that the installer's domain is an
  approved source for the publisher, and only an administrator can waive it.
  GitHub is a common host, and `PublisherUrl`/`PackageUrl` both point at the same
  repository, so provenance is self-consistent — but a fork pointing at a
  different repository than upstream is exactly the case that draws this review.
  Say plainly in the description that upstream publishes no Windows build.
- **Portable-archive labels.** `Portable-Archive`/`Zip-Binary` labels may be
  applied, which add a blocking issue to resolve. Explain in the description why
  the application must run from its extracted directory
  (`ArchiveBinariesDependOnPath`) rather than through a symlink.

Not obstacles: being an unofficial fork (only honest naming is required), the
absence of an installer, and the lack of any dependency on the VC++ runtime
(MinGW-w64 links its own). A 205 MB asset is large but not unusual.
