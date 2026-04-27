#!/bin/bash
# shellcheck disable=2034  ## Unused variables.
# shellcheck disable=2207

## Only allow running 'sourced'.
declare -i isSourced_t4rhz; { (return 0 2>/dev/null) && isSourced_t4rhz=1; } || isSourced_t4rhz=0
((! isSourced_t4rhz)) && { echo -e "\nThis script is meant to be 'sourced' from within another script.\n"; exit 1; }

declare -a baseAliasesArr=()
declare -a baseAliasesArr_commonBaseNames_v1b_v2=()

__fAddPermutations(){
	baseNumname=${1:-0}
	[[ ${baseNumname} =~ ^[0-9].* ]]  ||  return 1
	baseAliasesArr+=("${baseNumname}")
#	baseAliasesArr+=("base${baseNumname}")
#	baseAliasesArr+=("base-${baseNumname}")
}

fPopulateArrays(){

	## 2
	__fAddPermutations  2  ;  _commonBaseNames_v1b_v2+=("2")
#	baseAliasesArr+=("deux")

	## 8
	__fAddPermutations  8  ; _commonBaseNames_v1b_v2+=("8")
	baseAliasesArr+=("oct")
	baseAliasesArr+=("octal")

	## 10
	__fAddPermutations  10  ;  _commonBaseNames_v1b_v2+=("10")
	baseAliasesArr+=("dec")
	baseAliasesArr+=("decimal")

	## 16
	__fAddPermutations  16  ; _commonBaseNames_v1b_v2+=("16")
	baseAliasesArr+=("hex")
	baseAliasesArr+=("hexadecimal")

	## 26
	__fAddPermutations  26  ;  _commonBaseNames_v1b_v2+=("26")

	## 32r
	__fAddPermutations  32 ; _commonBaseNames_v1b_v2+=("32r")
	__fAddPermutations  "32r"
	__fAddPermutations  "32rfc"
	__fAddPermutations  "32rfc4648s6"
	baseAliasesArr+=("rfc4648s6")

	## 32h
	__fAddPermutations  "32h"  ;  _commonBaseNames_v1b_v2+=("32h")
	__fAddPermutations  "32hex"
	__fAddPermutations  "32rfc4648s7"
	baseAliasesArr+=("rfc4648s7")

	## 32c
	__fAddPermutations  "32c"  ;  _commonBaseNames_v1b_v2+=("32c")
	__fAddPermutations  "32crock"
	__fAddPermutations  "32crockford"
	baseAliasesArr+=("crockford")

	## 32ws
	__fAddPermutations  "32w"  ;  _commonBaseNames_v1b_v2+=("32w")
	__fAddPermutations  "32ws"
	__fAddPermutations  "32wordsafe"

	## 36
	__fAddPermutations  36  ;  _commonBaseNames_v1b_v2+=("36")

	## 38hostname
	__fAddPermutations  "38hostname" ; _commonBaseNames_v1b_v2+=("38hostname")
	__fAddPermutations  "38jc1"

	## 38username
	__fAddPermutations  "39username"  ;  _commonBaseNames_v1b_v2+=("39username")
	__fAddPermutations  "39jc1"

	## 45email
	__fAddPermutations                            "45email"  ;  _commonBaseNames_v1b_v2+=("45email")
	__fAddPermutations  "45jc1"

	## 48jc1ws
	__fAddPermutations  "48jc1ws"  ;  _commonBaseNames_v1b_v2+=("48jc1ws")
	__fAddPermutations  "48jcw"
	__fAddPermutations  "48j1w"
	__fAddPermutations  "48jcws"
	__fAddPermutations  "48jcwordsafe"

	## 48v1compat
	__fAddPermutations  "48v1compat"  ;  _commonBaseNames_v1b_v2+=("48v1compat")

	## 52
	__fAddPermutations  52  ;  _commonBaseNames_v1b_v2+=("52")

	## 62
	__fAddPermutations  62  ;  _commonBaseNames_v1b_v2+=("62")

	## 64r
	__fAddPermutations  64  ;  _commonBaseNames_v1b_v2+=("64r")
	__fAddPermutations  "64r"
	__fAddPermutations  "64rfc"
	__fAddPermutations  "64rfc4648s4"
	baseAliasesArr+=("rfc4648s4")

	## 64u
	__fAddPermutations  "64u"  ;  _commonBaseNames_v1b_v2+=("64u")
	__fAddPermutations  "64url"
	__fAddPermutations  "64urlsafe"
	__fAddPermutations  "64rfc4648s5"
	baseAliasesArr+=("rfc4648s5")

	## 64h
	__fAddPermutations  "64h"  ;  _commonBaseNames_v1b_v2+=("64h")
	__fAddPermutations  "64hex"

	## 64jc1
	__fAddPermutations  "64jc1"  ;  _commonBaseNames_v1b_v2+=("64jc1")
	__fAddPermutations  "64jc"
	__fAddPermutations  "64j1"

	## 64jc1ws
	__fAddPermutations  "64jc1ws"  ;  _commonBaseNames_v1b_v2+=("64jc1ws")
	__fAddPermutations  "64jcw"
	__fAddPermutations  "64j1w"
	__fAddPermutations  "64jcws"
	__fAddPermutations  "64jcwordsafe"

	## 64v1compat
	__fAddPermutations  "64v1compat"  ;  _commonBaseNames_v1b_v2+=("64v1compat")

	## 128jc1
	__fAddPermutations  "128jc1"  ;  _commonBaseNames_v1b_v2+=("128jc1")
	__fAddPermutations  "128jc"
	__fAddPermutations  "128j1"

	## 128jc1ws
	__fAddPermutations  "128jc1ws"  ;  _commonBaseNames_v1b_v2+=("128jc1ws")
	__fAddPermutations  "128jcw"
	__fAddPermutations  "128j1w"
	__fAddPermutations  "128jcws"
	__fAddPermutations  "128jcwordsafe"

	## 128v1compat
	__fAddPermutations  "128v1compat"  ;  _commonBaseNames_v1b_v2+=("128v1compat")

	## 256jc1
	__fAddPermutations  "256jc1"  ;  _commonBaseNames_v1b_v2+=("256jc1")
	__fAddPermutations  "256jc"
	__fAddPermutations  "256j1"

	## 288jc1
	__fAddPermutations  "288jc1"  ;  _commonBaseNames_v1b_v2+=("288jc1")
	__fAddPermutations  "288jc"
	__fAddPermutations  "288j1"


	echo "[ Base aliases loaded. ]"
}

fPopulateArrays
