#!/bin/bash
# shellcheck disable=SC2034  ## Don't complain about unused variables.
# shellcheck disable=SC2207  ## 'Prefer mapfile or read -a to split command output (or quote to avoid splitting).' (Applies to most or all of the base definitions below.)
# shellcheck disable=SC2178  ## False warning about array references.
# shellcheck disable=SC2317  ## Unreachble code. Makes debugging visually harder.
# shellcheck disable=SC2329  ## The function is never invoked.

declare LANG="C.UTF-8"

## Only allow running 'sourced'.
declare -i isSourced_t4rfy; { (return 0 2>/dev/null) && isSourced_t4rfy=1; } || isSourced_t4rfy=0
((! isSourced_t4rfy)) && { echo -e "\nThis script is meant to be 'sourced' from within another script.\n"; exit 1; }


####
#### Generic functions

fArrayToStr(){
	## Collapses an array to a string, removing spaces - unless one of the elements IS a space.
	local -n parentVarRef_Result_t4s9y=${1:-}      ; shift || true  ## Parent variable reference to store result in.
	local -n parentVarRef_InputArray_t4s9y=${1:-}  ; shift || true  ## Input array to work on.
	parentVarRef_Result_t4s9y=""
	local outputStr=""
	for nexItem in "${parentVarRef_InputArray_t4s9y[@]}"; do  outputStr="${outputStr}${nexItem}"; done
	parentVarRef_Result_t4s9y="${outputStr}"
}

fKeyVal_Add(){
	## Add a key/value pair to a pair of arrays. The assoc array will store the index# to indexed array, referenceable by key.
	## Args
	local -n parentVarRef_Array_KeyToVal=${1:-}   ; shift || true  ## Parent assoc key/val array variable to add to.
	local -n parentVarRef_Array_KeyToIdx=${1:-}   ; shift || true  ## Parent assoc key/idx array variable to add to.
	local -n parentVarRef_Array_IdxToKey=${1:-}   ; shift || true  ## Parent index idx/key array variable to add to.
	local -r keyStr="${1:-}"                      ; shift || true  ## The key to associate with the next value.
	local -r valStr="${1:-}"                      ; shift || true  ## The value to associate with the key.
	## Validate
	[[ -z "${keyStr}"                                     ]]  &&  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): The fourth argument - array 'key' - must be specified.\n" 1>&2; return 1; }
	[[ -n "${parentVarRef_Array_KeyToVal["${keyStr}"]:-}" ]]  &&  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): The specified key already exists in the associative array: '${keyStr}', with value '${parentVarRef_Array_KeyToVal["${keyStr}"]:-}'.\n" 1>&2; return 1; }
	## Variables
	local -i nextIndex=-1
	## Populate the arrays
	parentVarRef_Array_KeyToVal["${keyStr}"]="${valStr}"
	nextIndex=$((${#parentVarRef_Array_KeyToVal[@]} - 1))
	parentVarRef_Array_KeyToIdx["${keyStr}"]=${nextIndex}
	parentVarRef_Array_IdxToKey[nextIndex]="${keyStr}"
}

fKeyVal_Get_ByKey(){
	## Get a value from the arrays by its key.
	## Args
	local -n parentVarRef_Result_t4sdb=${1:-}     ; shift || true  ## Parent string variable to put return (value) in.
	local -n parentVarRef_Array_KeyToVal=${1:-}   ; shift || true  ## Parent asoc key/val array variable.
	local -r keyStr="${1:-}"                      ; shift || true  ## The key to look up.
	## Validate
	[[ -v parentVarRef_Result_t4sdb                ]]  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): The first argument - Parent string return variable - appears to be undefined.\n" 1>&2; return 1; }
	parentVarRef_Result_t4sdb=""
	[[ -n "${keyStr}"                              ]]  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): The third argument - array 'key' - can't be empty.\n" 1>&2; return 1; }
	[[ -v parentVarRef_Array_KeyToVal["${keyStr}"]      ]]  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): Key '${keyStr}' not found in array.\n" 1>&2; return 1; }
	## Get the value
	parentVarRef_Result_t4sdb="${parentVarRef_Array_KeyToVal["${keyStr}"]}"
:;}

fKeyVal_Get_ByIdx(){
	## Get a value from the indexed array by its numeric index.
	## Args
	local -n  parentVarRef_Result_t4sdf=${1:-}     ; shift || true  ## Parent string variable to put return value value in.
	local -n  parentVarRef_Array_IdxToKey=${1:-}   ; shift || true  ## Parent index idx/key array variable.
	local -n  parentVarRef_Array_KeyToVal=${1:-}   ; shift || true  ## Parent assoc key/val array variable.
	local -ri idxNum="${1:--1}"                    ; shift || true  ## The 0-based index to look up.
	## Validate
	[[ -v parentVarRef_Result_t4sdf              ]]  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): The first argument - Parent string return variable - appears to be undefined.\n" 1>&2; return 1; }
	parentVarRef_Result_t4sdf=""
	[[ "${idxNum}" =~ ^[1-9][0-9]*$              ]]  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): The third argument - 'index' - must be an integer >= 0.\n" 1>&2; return 1; }
	[[ -v parentVarRef_Array_KeyToVal[${idxNum}] ]]  ||  { echo -e "\nError in $(basename "${BASH_SOURCE[0]}").${FUNCNAME[0]}(): Index '${idxNum}' not present in indexed array.\n" 1>&2; return 1; }
	## Get the value
	local tmpKey=""
	tmpKey="${parentVarRef_Array_IdxToKey[idxNum]}"
	parentVarRef_Result_t4sdf="${parentVarRef_Array_KeyToVal["${tmpKey}"]}"
:;}


####
#### Custom functions
#### Pack bases _from_ their own arrays each, _to_ strings in a named and indexed array pair. Idx array needs to use 1 as starting index, therefor index=0 will ignored.

fAddBase_To_Arrs(){
	## Args
	local -ri alsoAddToInputBaseArrs=${1:-0}        ; shift || true  ## 0 [default]: Add only to output arrays. 1: Add to input arrays to.
	local -ri alsoAddToCommon_V1b_V2_array=${1:-0}  ; shift || true  ## 0 [default]: Add only to v2 arrays. 1: Also add to common array.
	local -r  baseName=${1:-0}                      ; shift || true  ## Name of the base to use as a key.
	local -n  parentVarRef_baseArray=${1:-0}        ; shift || true  ## The array to collapse into a value and store as key/value.
	## Get string from base array
	local tmpStr=""
	## Add name and permutations to alias array
	fAddAsAliasWithPermutations "${baseName}"
	## Add to output base arrays
	fArrayToStr  tmpStr  parentVarRef_baseArray
	fKeyVal_Add  bases_Output_KeyToVal  bases_Output_KeyToIdx  bases_Output_IdxToKey  "${baseName}"  "${tmpStr}"
	((alsoAddToInputBaseArrs))       &&  fKeyVal_Add  bases_Input_KeyToVal  bases_Input_KeyToIdx  bases_Input_IdxToKey  "${baseName}"  "${tmpStr}"
	((alsoAddToCommon_V1b_V2_array)) && _commonBaseNames_v1b_v2+=("${baseName}")
:;}

fAddAsAliasWithPermutations(){
	baseNumname=${1:-0}
	[[ ${baseNumname} =~ ^[0-9].* ]]  ||  return 1
	## Add the base name itself as an alias
	baseAliasesArr+=("${baseNumname}")
	## Not yet
#	baseAliasesArr+=("base${baseNumname}")
#	baseAliasesArr+=("base-${baseNumname}")
}


####
####
#### Define bases as they exist in go program to test

## Constants
declare -ri alsoAddToOutputArr=1
declare -ri noV1b=0
declare -ri alsoV1b=1

## Arrays
declare  -a baseAliasesArr=()
declare  -a baseAliasesArr_commonBaseNames_v1b_v2=()
declare  -A bases_Output_KeyToVal=() ; declare -A bases_Output_KeyToIdx=()  ; declare -a bases_Output_IdxToKey ;
declare  -A bases_Input_KeyToVal=()  ; declare -A bases_Input_KeyToIdx=()   ; declare -a bases_Input_IdxToKey ;

## 2
	declare -ra base2=($(echo {0..1}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "2"  base2
#	baseAliasesArr+=("deux")

## 8
	declare -ra base8=($(echo {0..7}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "8"  base8
	baseAliasesArr+=("oct")
	baseAliasesArr+=("octal")

## 10
	declare -ra base10=($(echo {0..9}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "10"  base10
	baseAliasesArr+=("dec")
	baseAliasesArr+=("decimal")

## 16
	declare -ra base16=($(echo {0..9} {A..F}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "16"  base16
	baseAliasesArr+=("hex")
	baseAliasesArr+=("hexadecimal")

## 26
	declare -ra base26=($(echo {A..Z}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "26"  base26

## 32r
	declare -ra base32r=($(echo {A..Z} {2..7}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "32r"  base32r
	fAddAsAliasWithPermutations  32
	fAddAsAliasWithPermutations  "32rfc"
	fAddAsAliasWithPermutations  "32rfc4648s6"
	baseAliasesArr+=("rfc4648s6")

## 32h
	declare -ra base32h=($(echo {0..9} {A..V}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "32h"  base32h
	fAddAsAliasWithPermutations  "32hex"
	fAddAsAliasWithPermutations  "32rfc4648s7"
	baseAliasesArr+=("rfc4648s7")

## 32c
	declare -ra base32c=(0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T V W X Y Z)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "32c"  base32c
	fAddAsAliasWithPermutations  "32crock"
	fAddAsAliasWithPermutations  "32crockford"
	baseAliasesArr+=("crockford")

## 32w
	declare -ra base32w=(2 3 4 5 6 7 8 9 C F G H J M P Q R V W X c f g h j m p q r v w x)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "32w"  base32w
	fAddAsAliasWithPermutations  "32ws"
	fAddAsAliasWithPermutations  "32wordsafe"
	fAddAsAliasWithPermutations  "32g"
	fAddAsAliasWithPermutations  "32google"
	fAddAsAliasWithPermutations  "32nofks"

## 36
	declare -ra base36=($(echo {0..9} {A..Z}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "36"  base36

## 38hostname
	declare -ra base38hostname=($(echo {0..9} {a..z} "- ."))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "38hostname"  base38hostname
	fAddAsAliasWithPermutations  "38jc1"

## 39username
	declare -ra base39username=($(echo {0..9} {a..z} "- _ ."))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "39username"  base39username
	fAddAsAliasWithPermutations  "39jc1"

## 45email
	declare -ra base45email=($(echo {0..9} {a..z} "- _ % + . : @ [ ]"))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "45email"  base45email
	fAddAsAliasWithPermutations  "45jc1"

## 48jc1ws
	declare -ra base48jc1ws=(2 3 4 5 6 7 8 9 C F G H J M P Q R V W X c f g h j m p q r v w x ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "48jc1ws"  base48jc1ws
	fAddAsAliasWithPermutations  "48w"
	fAddAsAliasWithPermutations  "48ws"
	fAddAsAliasWithPermutations  "48wordsafe"
	fAddAsAliasWithPermutations  "48nofks"

## 48v1compat
	declare -ra base48v1compat=(0 1 2 3 4 5 6 7 8 9 c f g h j m p q r v w x ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "48v1compat"  base48v1compat
	fAddAsAliasWithPermutations  "48depr"
	fAddAsAliasWithPermutations  "48j1"

## 52
	declare -ra base52=($(echo {A..Z} {a..z}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "52"  base52

## 62
	declare -ra base62=($(echo {0..9} {A..Z} {a..z}))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "62"  base62

## 64r
	declare -ra base64r=($(echo {A..Z} {a..z} {0..9} "+ /"))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "64r"  base64r
	fAddAsAliasWithPermutations  64
	fAddAsAliasWithPermutations  "64rfc"
	fAddAsAliasWithPermutations  "64rfc4648s4"
	baseAliasesArr+=("rfc4648s4")

## 64u
	declare -ra base64u=($(echo {A..Z} {a..z} {0..9} "- _"))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "64u"  base64u
	fAddAsAliasWithPermutations  "64url"
	fAddAsAliasWithPermutations  "64rfc4648s5"
	baseAliasesArr+=("rfc4648s5")

## 64h
	declare -ra base64h=($(echo {0..9} {A..Z} {a..z} "- _"))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "64h"  base64h
	fAddAsAliasWithPermutations  "64hex"

## 64jc1
	declare -ra base64jc1=($(echo {0..9} {A..Z} {a..z} "ʞ λ"))
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "64jc1"  base64jc1
	fAddAsAliasWithPermutations  "64j1u"

## 64jc1ws
	declare -ra base64jc1ws=(2 3 4 5 6 7 8 9 C F G H J M P Q R V W X c f g h j m p q r v w x ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "64jc1ws"  base64jc1ws
	fAddAsAliasWithPermutations  "64w"
	fAddAsAliasWithPermutations  "64ws"
	fAddAsAliasWithPermutations  "64wordsafe"
	fAddAsAliasWithPermutations  "64nofks"

## 64v1compat
	declare -ra base64v1compat=(0 1 2 3 4 5 6 7 8 9 C F G H J M P Q R V W X c f g h j m p q r v w x ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "64v1compat"  base64v1compat
	fAddAsAliasWithPermutations  "64depr"
	fAddAsAliasWithPermutations  "64j1uw"

## 128jc1
	declare -ra base128jc1=(0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Î Ĵ Ô Ŝ Û Ŵ)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "128jc1"  base128jc1

## 128jc1ws
	declare -ra base128jc1ws=(2 3 4 5 6 7 8 9 C F G H J M P Q R V W X c f g h j m p q r v w x ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Î Ĵ Ô Ŝ Û Ŵ Ŷ Ẑ â ĉ ê ĝ ĥ î ĵ ô ŝ û ŵ ŷ ẑ Ã Ẽ Ĩ Ñ Õ Ũ Ỹ ã ẽ ĩ ñ õ ũ ỹ Ä)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "128jc1ws"  base128jc1ws
	fAddAsAliasWithPermutations  "128w"
	fAddAsAliasWithPermutations  "128ws"
	fAddAsAliasWithPermutations  "128wordsafe"
	fAddAsAliasWithPermutations  "128nofks"

## 128v1compat
	declare -ra base128v1compat=(0 1 2 3 4 5 6 7 8 9 C F G H J M P Q R V W X c f g h j m p q r v w x ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Ĵ Ŝ Ŵ Ŷ â ĉ ê ĝ ĥ ĵ ŝ ŵ ŷ Ã Ẽ Ñ Ỹ ã ẽ ñ ỹ Ä Ë Ẅ Ẍ Ÿ ä ë ẅ ẍ ÿ Á Ć É)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "128v1compat"  base128v1compat
	fAddAsAliasWithPermutations  "128depr"

## 256jc1
	declare -ra base256jc1=(0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Î Ĵ Ô Ŝ Û Ŵ Ŷ Ẑ â ĉ ê ĝ ĥ î ĵ ô ŝ û ŵ ŷ ẑ Ã Ẽ Ĩ Ñ Õ Ũ Ỹ ã ẽ ĩ ñ õ ũ ỹ Ä Ë Ï Ö Ü Ẅ Ẍ Ÿ ä ë ï ö ü ẅ ẍ ÿ Á Ć É Ǵ Í Ń Ó Ŕ Ś Ú Ẃ Ý Ź á ć é ǵ í ń ó ŕ ś ú ẃ ý ź Ā Ē Ī Ō Ū Ȳ ā ē ī ō ū ȳ Ǎ Č Ď Ě Ǧ Ȟ Ǩ Ň Ǒ Ř Š Ǔ ǎ č ď ě ǧ ȟ ǩ ň ǒ ř š ǔ ǝ ɹ ʇ ʌ ₸ ᛬ 웃 유 ㅈ ㅊ ㅍ ㅎ ㅱ ㅸ ㅠ ソ ッ ゞ ぅ ぇ ォ)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "256jc1"  base256jc1
	fAddAsAliasWithPermutations  "256j1"

## 288jc1
	declare -ra base288jc1=(0 1 2 3 4 5 6 7 8 9 A B C D E F G H I J K L M N O P Q R S T U V W X Y Z a b c d e f g h i j k l m n o p q r s t u v w x y z ʞ λ μ ᛎ ᛏ ᛘ ᛯ ᛝ ᛦ ᛨ ᚠ ᚧ ᚬ ᚼ 🜣 🜥 🜿 🝅 ▵ ▸ ▿ ◂ ҂ ‡ ± ⁑ ÷ ∞ ≈ ≠ Ω Ʊ Ξ ψ Ϡ δ ϟ Ћ Ж Я Ѣ ф ¢ £ ¥ § ¿ ɤ ʬ ⍤ ⍩ ⌲ ⍋ ⍒ ⍢ Â Ĉ Ê Ĝ Ĥ Î Ĵ Ô Ŝ Û Ŵ Ŷ Ẑ â ĉ ê ĝ ĥ î ĵ ô ŝ û ŵ ŷ ẑ Ã Ẽ Ĩ Ñ Õ Ũ Ỹ ã ẽ ĩ ñ õ ũ ỹ Ä Ë Ï Ö Ü Ẅ Ẍ Ÿ ä ë ï ö ü ẅ ẍ ÿ Á Ć É Ǵ Í Ń Ó Ŕ Ś Ú Ẃ Ý Ź á ć é ǵ í ń ó ŕ ś ú ẃ ý ź Ā Ē Ī Ō Ū Ȳ ā ē ī ō ū ȳ Ǎ Č Ď Ě Ǧ Ȟ Ǩ Ň Ǒ Ř Š Ǔ ǎ č ď ě ǧ ȟ ǩ ň ǒ ř š ǔ ǝ ɹ ʇ ʌ ₸ ᛬ 웃 유 ㅈ ㅊ ㅍ ㅎ ㅱ ㅸ ㅠ ソ ッ ゞ ぅ ぇ ォ ゲ サ じ す ス せ ち づ で ネ ビ べ ぺ ま モ ゟ ヲ ½ ⅓ ⅔ ¼ ¾ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅛ ⅜ ⅝ ⅞)
	fAddBase_To_Arrs  $alsoAddToOutputArr  $alsoV1b  "288jc1"       base288jc1
	fAddAsAliasWithPermutations  "288j1"


##DEBUG; list output arrays
#declare    strVal=""
#declare -i intIdx=0
#declare    allStr=""
#for nextKey in "${!bases_Output_KeyToIdx[@]}"; do
#	intIdx=${bases_Output_KeyToIdx["${nextKey}"]}
#	strVal="${bases_Output_KeyToVal["${nextKey}"]}"
#	allStr="${allStr}${intIdx}\t${nextKey}\t${strVal}\n"
#done
#allStr="$(echo -e "${allStr}" | sort -k 2 -g)"
#allStr="IDX\tKEY\tVAL\n${allStr}"
#echo -e "${allStr}" | column -t -s $'\t'
#exit

echo "[ Base definitions loaded. ]"


##	History:
##		- 20260427 JC: Combined base-definitions.sh and alias-definitions.sh into this refactored, simpler one.
