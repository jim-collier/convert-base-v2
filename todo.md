<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD033 -- No inline html -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
# To-do

This is an easier way to brainstorm and prioritize tasks, before creating issues for them (if at all). Also allows for more fields and easier prioritization.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Column headings defined](#column-headings-defined)
- [Status: Staged](#status-staged)
- [Status: Started](#status-started)
- [Status: Canceled, moot](#status-canceled-moot)
- [Status: Done](#status-done)

<!-- /TOC -->

## Column headings defined

| Abbreviation | Full name or description     | Values
| :--          | :--                          | :--
| Score        | Average of next 4 values     | Floating point, lower=higher priority
| Imp          | Importance                   | 1=highest, 3=default, 5=lowest
| Urg          | Urgency                      | 1=highest, 3=default, 5=lowest
| Eff          | Estimated effort             | 1=quickest, 3=default, 5=maximum effort
| Aff          | Actual effort in retrospect  | 1=quickest, 3=default, 5=maximum effort

## Status: Staged

| Created  | Issue#                                                  |Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
|:---------|-------:                                                 |----:|--:|--:|--:|--:|:---------|:---|:----------|:------------|:------
| 20260413 |                                                         | 2.0 | 1 | 2 | 3 |   |  | tt |  | Set `cachefile=none` on rpool, on every boot. Figure out the most logical and reliable place to do this (a `systemd` service may not be te beste.)
| 20260413 |                                                         | 2.3 | 1 | 3 | 3 |   |  | tt |  | Find where rpool is first imported in init process, and add `-f` to it, to get around ZFS host ID and zfs.cache mismatch problems. At least until 'Boot-time filesystem mounting' task is finished.
| 20260410 |                                                         | 2.3 | 1 | 2 | 4 |   |  | tt |  | ZFS user home encryption: Improve PAM script to unlock ZFS filesystem on login
| 20260410 |                                                         | 2.3 | 1 | 2 | 4 |   |  | tt |  | ZFS user home encryption: Improve watchdog to close encrypted home folders after logout
| 20260410 |                                                         | 3.3 | 3 | 3 | 4 |   |  | tt |  | Boot-time filesystem mounting: Gain deterministic control over mount timing and order
| 20260410 |                                                         | 3.3 | 3 | 3 | 4 |   |  | tt |  | ZFS user home encryption: Tie into PAM password change hook
| 20260404 |                                                         | 3.3 | 3 | 4 | 3 |   |  | tt |  | Move the "Phases" section from 'README.md', to a new 'roadmap.md' file.
| 20260404 |                                                         | 3.3 | 2 | 5 | 3 |   |  | tt |  | Update all docs to reflect no "Grub fallback".
| 20260415 |                                                         | 3.3 | 3 | 4 | 3 |   |  | tt |  | Add a one-shot script for headless server use that removes all Windows and Flatpak apps, their residual files, and the entire Xorg/DE stack.
| 20260415 |                                                         | 3.7 | 4 | 4 | 3 |   |  | tt |  | Add and integrate AppImageUpdate and appimaged; and update the script that already takes a system snapshot then updates `apt` _and_ `flatpak` together. (For one-command system updates to everything - Apt, Flatpak, and AppImage.)
<!--
| 2026 |                                                         |  |  |  |   |  |  | tt |  |
-->

## Status: Started

| Created  | Issue# |Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
|:---------|:-------|----:|--:|--:|--:|--:|:---------|:---|:----------|:------------|:-----
| 20260402 |        | 2.0 | 1 | 2 | 3 |   | 20260320 | tt |  | Finish "Cloning" steps in `.md` doc.
| 20260402 |        | 2.3 | 2 | 2 | 3 |   | 20260320 | tt |  | Move "Creation" steps to formatted `.md` doc.

## Status: Canceled, moot

| Created  | Issue# |Score |Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
|:---------|:-------|-----:|--:|--:|--:|--:|:---------|:---|:----------|:------------|:-----

## Status: Done

| Created  | Issue# |Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Completion notes
|:---------|:-------|----:|--:|--:|--:|--:|:---------|:---|:----------|:------------|:-----
| 20260404 |        | 2.0 | 2 | 2 | 2 | 3 | 20260405 | tt | 20260405  | Update and merge helper scripts to auto-detect environment (build/rescue host or new target) and type (real/chroot). | `systemd-detect-virt --chroot` or non-systemd `ischroot`
| 20260404 |        | 4.0 | 3 | 5 | 4 | 3 | 20260412 | tt | 20260412  | Remove Grub fallback option. | It's added complexity for rare use and potential conflicting configuration.
| 20260404 |        | 3.7 | 2 | 4 | 5 | 2 | 20260412 | tt | 20260412  | Move `/boot` to same LV and ZPool as `/`, for less complexity and `/boot` mount fragility.
