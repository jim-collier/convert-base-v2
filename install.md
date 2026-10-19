<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- TOC ignore:true -->
# Installation

Back to the [README](README.md).

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Packages and installers](#packages-and-installers)
- [Direct stable and dev install scripts](#direct-stable-and-dev-install-scripts)
- [DIY](#diy)

<!-- /TOC -->

## Packages and installers

Grab a build for your platform from the [Releases page](https://github.com/jim-collier/convert-base-v2/releases). Every native option installs the same single static executable.

- Linux gets a `.deb` or `.rpm` for x86_64 or arm64, or a `.tgz` tarball.

- Windows gets a one-click installer `.exe` that adds the tool to your PATH, or a plain `.zip`.

- macOS gets a `.tgz` tarball. The universal build runs on both Intel and Apple silicon Macs. A build for just one is half the size.

- FreeBSD gets a `.tgz` tarball.

- `convert-base-v2.wasm` is the whole command for any WASI runtime. One file for every CPU.

The release notes list them all in one table, by OS and CPU. Each release includes a `checksums.txt` so you can verify what you downloaded.

## Direct stable and dev install scripts

Each script prints what it will do, verifies the download against the release's checksum file, and asks before touching anything.

For Linux, macOS, FreeBSD, and WSL:

~~~bash
bash <(curl -fsSL https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.bash)
~~~

For Windows, and also anywhere else Windows PowerShell 5.1 or PowerShell 7 runs:

~~~powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/jim-collier/convert-base-v2/main/install.ps1)))
~~~

That gets the newest stable release. To include pre-releases, add `--release dev` at the end, or `-Release dev` for PowerShell. It works out your OS and CPU, uses sensible defaults, and asks before it does anything. `--help` or `-Help` lists the few options.

| Install        | Linux, macOS, FreeBSD            | Windows
| :---           | :---                             | :---
| User (default) | `~/.local/bin/convert-base-v2`   | `%LOCALAPPDATA%\Programs\convert-base-v2\`, added to your PATH
| System         | `/usr/local/bin/convert-base-v2` | `%ProgramFiles%\convert-base-v2\`, added to the system PATH

A Windows system install needs an elevated shell. It goes in the same folder as the installer `.exe`, so either one updates the other's copy.

## DIY

You need Go 1.21 or newer, and nothing else. There are no dependencies to fetch.

~~~bash
git clone https://github.com/jim-collier/convert-base-v2
cd convert-base-v2/lib
make local        # builds ./convert-base-v2
~~~

Copy the resulting binary anywhere on your PATH. For the full set of build targets, see [Set up a development environment](development.md).
