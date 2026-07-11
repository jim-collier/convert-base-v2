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

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----
| 20260511 |      |     | 4 | 4 |   | 4 |          |    |           | Update "How to design a base" from detailed notes file
| 20260711 |      |     | 4 | 4 | 1 |   |          |    |           | Decide whether README should embed assets/demo.gif | One image line; the gif already regenerates on each full cicd run
<!--
| 2026     |      |     |   |   |   |   |          |    |           |
-->

## Status: Started

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----

## Status: Canceled, moot

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----

## Status: Done

| Created  |Issue#|Score|Imp|Urg|Eff|Aff| Started  | by | Completed | Description | Notes
| :------  | :--- | --: |--:|--:|--:|--:| :------  |:---| :-------- | :---------- | :----
| 20260420 |      | 2.7 | 3 | 3 | 2 |   |          | JC | 20260422  | Add known issues to Github.
| 20260703 |      | 2.5 | 3 | 3 | 2 | 2 | 20260703 | JC | 20260703  | Add base query flags (count, name, symbols) and full-coverage self round-trip tests | Every base is now fuzzed with its own random symbols, source to target and back.
| 20260709 |      | 2.5 | 3 | 3 | 3 | 3 | 20260709 | JC | 20260709  | cicd: quiet/message flags, sister-project output style, lint + fuzz + security + profiler stages | -q/-m + Ctrl+C message prompt; go vet/golangci/staticcheck; go fuzz; govulncheck; flamegraph SVG + report, all rotated under cicd/artifacts
| 20260711 |      | 2.7 | 3 | 3 | 3 | 3 | 20260711 | JC | 20260711  | cicd: animated demo gif stage | cicd/utility/gen-demo-gif.py types cicd/demo-scenario.toml into a fake terminal and renders assets/demo.gif; runs the tested binary so output never goes stale; seeded and byte-stable; skipped by --quick / --no-demogif
