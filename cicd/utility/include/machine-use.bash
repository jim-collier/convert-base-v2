#!/usr/bin/env bash

##	Purpose: How many CPUs a pipeline step may use. Sourced by cicd.bash.
##		- A step gets half the logical CPUs, or a quarter when the box is busy.
##		- Busy means the 1-minute load average is over half the CPU count.
##		- The heavy steps, such as the race detector, soak, fuzz and CodeQL, get a
##		  quarter, busy or not.
##		- Never under 1.
##	History: At bottom of script.

##	Copyright © 2026 Jim Collier [ID: 2უNაɘ«҂թȹɤξπ๙¿ձϖ]
##	Licensed under The MIT License (MIT). Full text at:
##		https://mit-license.org/
##	SPDX-License-Identifier: MIT


## fMachineJobs CPUS LOAD1 sets machineJobs, machineJobsHeavy and machineBusy.
## It takes the numbers rather than reading them, so another host's numbers work too.
fMachineJobs(){
	local -i cpus=1
	local load="${2:-0}" whole frac
	if [[ "${1:-}" =~ ^[0-9]+$ ]] && ((10#${1} > 0)); then cpus=$((10#${1})); fi
	[[ "${load}" =~ ^[0-9]+(\.[0-9]*)?$ ]] || load=0
	## In hundredths, so 16.01 on 32 CPUs is busy and 16.00 isn't.
	whole="${load%%.*}"; frac="${load#"${whole}"}"; frac="${frac#.}00"; frac="${frac:0:2}"
	machineBusy=0; if (( 10#${whole} * 100 + 10#${frac} > cpus * 50 )); then machineBusy=1; fi
	machineJobsHeavy=$(( cpus / 4 )); ((machineJobsHeavy > 0)) || machineJobsHeavy=1
	machineJobs=$(( cpus / 2 )); ((machineJobs > 0)) || machineJobs=1
	if ((machineBusy)); then machineJobs="${machineJobsHeavy}"; fi
}

## This box's logical CPUs and 1-minute load. nproc is Linux, getconf is the
## Macs and BSD. CICD_LOADAVG_FILE stands in for /proc/loadavg in the tests.
fMachineCpus(){ nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1; }
fMachineLoad1(){
	local f="${CICD_LOADAVG_FILE:-/proc/loadavg}" load=""
	if [[ -r "${f}" ]]; then read -r load _ <"${f}"
	else load="$(sysctl -n vm.loadavg 2>/dev/null || true)"; load="${load#\{ }"; load="${load%% *}"; fi
	printf '%s\n' "${load:-0}"
}


##	History:
##		- 2026-10-25 JC: Created.
