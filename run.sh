#!/usr/bin/env bash
# Symlinks the skills and instructions of resources/ into tool directories. Spec: run.spec.md
set -uo pipefail
shopt -s nullglob

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
  echo "run.sh requires bash >= 4.4 (found $BASH_VERSION). On macOS: brew install bash" >&2
  exit 1
fi

REPO=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RES="$REPO/resources"
PROPS="$REPO/run.properties"
PROPS_TEMPLATE="$REPO/run.properties.template"

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

NO_COLOR_FLAG=0
C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_MAGENTA=""

setup_colors() {
  if [[ ! -t 1 || -n ${NO_COLOR:-} ]] || ((NO_COLOR_FLAG)); then return 0; fi
  C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m' C_RED=$'\e[31m'
  C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_MAGENTA=$'\e[35m'
}

declare -A SYMBOL=([linked]='✔' [unlinked]='○' [partial]='◐' [broken]='✖' [dead]='✖' [conflict]='!' [collision]='✖')
STATUS_ORDER=(linked unlinked partial broken conflict collision dead)

status_color() {
  case $1 in
    linked) printf '%s' "$C_GREEN" ;;
    unlinked) printf '%s' "$C_DIM" ;;
    partial) printf '%s' "$C_YELLOW" ;;
    conflict) printf '%s' "$C_MAGENTA" ;;
    *) printf '%s' "$C_RED" ;;
  esac
}

badge() { printf '%s%s %-9s%s' "$(status_color "$1")" "${SYMBOL[$1]}" "$1" "$C_RESET"; }
# One feedback line per action: say <status> <message>
say() { printf '%s%s%s %s\n' "$(status_color "$1")" "${SYMBOL[$1]}" "$C_RESET" "$2"; }
dim() { printf '%s%s%s' "$C_DIM" "$1" "$C_RESET"; }
heading() { printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
summary() { printf '\n%s%s%s\n' "$1" "$2" "$C_RESET"; }
err() { printf '%serror: %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die() { err "$@"; exit 1; }

human_size() {
  local kb=$1
  if ((kb >= 1048576)); then printf '%d.%d GB' $((kb / 1048576)) $((kb % 1048576 * 10 / 1048576))
  elif ((kb >= 1024)); then printf '%d.%d MB' $((kb / 1024)) $((kb % 1024 * 10 / 1024))
  else printf '%d KB' "$kb"; fi
}

TTY_STATE=""

restore_tty() {
  [[ -n $TTY_STATE ]] || return 0
  stty "$TTY_STATE" </dev/tty 2>/dev/null
  printf '\e[?25h\e[?7h' >/dev/tty
  TTY_STATE=""
}
trap restore_tty EXIT
trap 'exit 130' INT TERM

KEY=""
read_key() {
  local k="" rest="" drain
  IFS= read -rsn1 k || { KEY=quit; return; }
  case $k in
    $'\e')
      IFS= read -rsn2 -t 0.05 rest
      # Swallow the tail of longer sequences (e.g. ctrl+arrows) so it is not read as keys.
      while IFS= read -rsn1 -t 0.01 drain; do :; done
      case $rest in
        '[A' | 'OA') KEY=up ;;
        '[B' | 'OB') KEY=down ;;
        '') KEY=quit ;;
        *) KEY=none ;;
      esac
      ;;
    k | K) KEY=up ;;
    j | J) KEY=down ;;
    ' ') KEY=space ;;
    a | A) KEY=all ;;
    q | Q) KEY=quit ;;
    '') KEY=enter ;;
    *) KEY=none ;;
  esac
}

# Selected item indices of the last menu_select call.
MENU_SEL=()

# menu_select <title> <label>... ; returns 1 when cancelled or nothing is selected.
menu_select() {
  MENU_SEL=()
  if [[ -t 0 ]]; then menu_tty "$@"; else menu_numbered "$@"; fi
}

menu_tty() {
  local title=$1
  shift
  local -a items=("$@") checked=()
  local n=$# total=$(($# + 1)) cur=0 top=0 view rows cols drawn=0 all box label out i j cancelled=0

  for ((i = 0; i < n; i++)); do checked[i]=0; done
  read -r rows cols < <(stty size </dev/tty 2>/dev/null)
  [[ ${rows:-} =~ ^[0-9]+$ ]] || rows=24
  view=$((rows - 4))
  ((view < 3)) && view=3
  ((view > total)) && view=$total

  TTY_STATE=$(stty -g </dev/tty)
  stty -echo -icanon min 1 time 0 </dev/tty
  # Hide the cursor and disable line wrapping so the redraw line count stays exact.
  printf '\e[?25l\e[?7l' >/dev/tty

  while true; do
    all=1
    for ((i = 0; i < n; i++)); do ((checked[i])) || { all=0; break; }; done
    ((cur < top)) && top=$cur
    ((cur >= top + view)) && top=$((cur - view + 1))

    out=""
    ((drawn)) && out+=$'\e['"${drawn}A"
    out+=$'\r\e[J'"${C_BOLD}${title}${C_RESET}"$'\n'
    for ((j = top; j < top + view; j++)); do
      if ((j == cur)); then out+="${C_BOLD}❯${C_RESET} "; else out+="  "; fi
      if ((j == 0)); then box=$all label="Select all"; else box=${checked[j - 1]} label=${items[j - 1]}; fi
      if ((box)); then out+="${C_GREEN}[x]${C_RESET} "; else out+="[ ] "; fi
      out+="$label"$'\n'
    done
    out+="${C_DIM}↑/↓ j/k move · space toggle · a all · enter confirm · q/esc cancel"
    ((total > view)) && out+="  ($((top + 1))-$((top + view))/$total)"
    out+="${C_RESET}"$'\n'
    drawn=$((view + 2))
    printf '%s' "$out" >/dev/tty

    read_key
    case $KEY in
      up) ((cur > 0)) && cur=$((cur - 1)) ;;
      down) ((cur < total - 1)) && cur=$((cur + 1)) ;;
      space | all)
        if [[ $KEY == all ]] || ((cur == 0)); then
          for ((i = 0; i < n; i++)); do checked[i]=$((!all)); done
        else
          checked[cur - 1]=$((!checked[cur - 1]))
        fi
        ;;
      enter) break ;;
      quit) cancelled=1 && break ;;
    esac
  done

  printf '\e[%dA\r\e[J' "$drawn" >/dev/tty
  restore_tty
  ((cancelled)) && return 1
  for ((i = 0; i < n; i++)); do ((checked[i])) && MENU_SEL+=("$i"); done
  ((${#MENU_SEL[@]} > 0))
}

menu_numbered() {
  local title=$1
  shift
  local -a items=("$@") tokens=()
  local n=$# i tok line=""
  local -A seen=()

  {
    printf '%s%s%s\n' "$C_BOLD" "$title" "$C_RESET"
    for ((i = 0; i < n; i++)); do printf '  %2d) %s\n' $((i + 1)) "${items[i]}"; done
    printf 'Numbers separated by spaces, %sa%s for all, empty to cancel: ' "$C_BOLD" "$C_RESET"
  } >&2
  IFS= read -r line || true
  printf '%s\n' "$line" >&2

  read -ra tokens <<<"${line//,/ }"
  ((${#tokens[@]} > 0)) || return 1
  if [[ ${#tokens[@]} -eq 1 && ${tokens[0]} == [aA] ]]; then
    for ((i = 0; i < n; i++)); do MENU_SEL+=("$i"); done
    return 0
  fi
  for tok in "${tokens[@]}"; do
    if [[ $tok =~ ^[0-9]+$ ]] && ((10#$tok >= 1 && 10#$tok <= n)); then
      i=$((10#$tok - 1))
      [[ -n ${seen[$i]:-} ]] || MENU_SEL+=("$i")
      seen[$i]=1
    else
      warn "ignored invalid choice: $tok"
    fi
  done
  ((${#MENU_SEL[@]} > 0))
}

confirm() {
  local answer=""
  printf '%s [y/%sN%s] ' "$1" "$C_BOLD" "$C_RESET" >&2
  IFS= read -r answer || true
  [[ -t 0 ]] || printf '%s\n' "$answer" >&2
  [[ $answer =~ ^[[:space:]]*[yY]([eE][sS])?[[:space:]]*$ ]]
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SKILLS_TGT="" INSTR_TGT="" CLAUDE_HOME=""
TARGET_DIRS=()

expand_path() {
  local p=$1
  [[ $p == '~' || $p == '~/'* ]] && p=$HOME${p:1}
  p=${p//'${HOME}'/$HOME}
  p=${p//'$HOME'/$HOME}
  [[ $p == / ]] || p=${p%/}
  printf '%s' "$p"
}

# Returns 1 when run.properties is missing.
read_config() {
  [[ -f $PROPS ]] || return 1
  local line key value
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|!|$) ]] && continue
    [[ $line =~ ^[[:space:]]*([^=[:space:]]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]] || continue
    key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
    case $key in
      skills.target) SKILLS_TGT=$(expand_path "$value") ;;
      instructions.target) INSTR_TGT=$(expand_path "$value") ;;
      claude.home) CLAUDE_HOME=$(expand_path "$value") ;;
      *) warn "run.properties: unknown key '$key' ignored" ;;
    esac
  done <"$PROPS"
  TARGET_DIRS=("$SKILLS_TGT")
  [[ $INSTR_TGT != "$SKILLS_TGT" ]] && TARGET_DIRS+=("$INSTR_TGT")
  return 0
}

require_config() {
  read_config || die "run.properties not found. Create it from the template: cp \"$PROPS_TEMPLATE\" \"$PROPS\""
  local key value
  for key in skills.target instructions.target claude.home; do
    case $key in
      skills.target) value=$SKILLS_TGT ;;
      instructions.target) value=$INSTR_TGT ;;
      claude.home) value=$CLAUDE_HOME ;;
    esac
    [[ -n $value ]] || die "run.properties: missing value for $key"
    [[ $value == /* ]] || die "run.properties: $key must be an absolute path (got '$value')"
  done
}

# ---------------------------------------------------------------------------
# Model: elements, collections, statuses
# ---------------------------------------------------------------------------

E_TYPE=() E_NAME=() E_SRC=() E_TGT=() E_COLL=() E_STATUS=()
COLLS=()
declare -A COLL_ELEMS=() COLL_STATUS=() TGT_OWNER=() COLLIDED=()
DEAD=()

add_element() { # type name src target collection
  local i=${#E_TYPE[@]}
  E_TYPE+=("$1") E_NAME+=("$2") E_SRC+=("$3") E_TGT+=("$4") E_COLL+=("$5")
  if [[ -n ${TGT_OWNER[$4]:-} ]]; then
    COLLIDED[$i]=1
    COLLIDED[${TGT_OWNER[$4]}]=1
  else
    TGT_OWNER[$4]=$i
  fi
  [[ -z $5 ]] || COLL_ELEMS[$5]+=" $i"
}

scan_dir() { # base collection
  local d f name
  for d in "$1"/skills/*/; do
    d=${d%/} name=${d##*/}
    add_element skill "$name" "$d" "$SKILLS_TGT/$name" "$2"
  done
  for f in "$1"/instructions/*.instructions.md; do
    name=${f##*/}
    add_element instruction "${name%.instructions.md}" "$f" "$INSTR_TGT/$name" "$2"
  done
}

discover() {
  local c
  for c in "$RES"/collections/*/; do
    c=${c%/}
    COLLS+=("${c##*/}")
    COLL_ELEMS[${c##*/}]=""
    scan_dir "$c" "${c##*/}"
  done
  scan_dir "$RES" ""
}

link_dest() {
  local d
  d=$(readlink -- "$1") || return 1
  [[ $d == /* ]] || d=${1%/*}/$d
  printf '%s' "${d%/}"
}

is_managed() { [[ -L $1 && $(link_dest "$1") == "$RES/"* ]]; }

coll_size() { local -a e=(${COLL_ELEMS[$1]}); printf '%d' ${#e[@]}; }

compute_statuses() {
  local i tgt dest c n linked dir p
  for i in "${!E_TYPE[@]}"; do
    tgt=${E_TGT[i]}
    if [[ -n ${COLLIDED[$i]:-} ]]; then
      E_STATUS[i]=collision
    elif [[ -L $tgt ]]; then
      dest=$(link_dest "$tgt")
      if [[ $dest == "${E_SRC[i]}" ]]; then E_STATUS[i]=linked
      elif [[ $dest == "$RES/"* ]]; then E_STATUS[i]=broken
      else E_STATUS[i]=conflict; fi
    elif [[ -e $tgt ]]; then
      E_STATUS[i]=conflict
    else
      E_STATUS[i]=unlinked
    fi
  done

  for c in "${COLLS[@]}"; do
    n=0 linked=0
    for i in ${COLL_ELEMS[$c]}; do
      n=$((n + 1))
      [[ ${E_STATUS[i]} == linked ]] && linked=$((linked + 1))
    done
    if ((n > 0 && linked == n)); then COLL_STATUS[$c]=linked
    elif ((linked > 0)); then COLL_STATUS[$c]=partial
    else COLL_STATUS[$c]=unlinked; fi
  done

  # A managed symlink sitting on a current element's target is `broken`, not dead.
  DEAD=()
  for dir in "${TARGET_DIRS[@]}"; do
    for p in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
      [[ -L $p && ! -e $p && -z ${TGT_OWNER[$p]:-} ]] || continue
      [[ $(link_dest "$p") == "$RES/"* ]] && DEAD+=("$p")
    done
  done
}

load_all() {
  require_config
  discover
  compute_statuses
}

elem_label() { printf '%s %s%s%s' "${E_TYPE[$1]}" "$C_BOLD" "${E_NAME[$1]}" "$C_RESET"; }

coll_label() {
  printf 'collection %s%s%s %s  %s' "$C_BOLD" "$1" "$C_RESET" \
    "$(dim "($(coll_size "$1") elements)")" "$(badge "${COLL_STATUS[$1]}")"
}

# ---------------------------------------------------------------------------
# Actions (the only code paths that touch the file system)
# ---------------------------------------------------------------------------

CREATED=0 REMOVED=0 SKIPPED=0

create_link() {
  mkdir -p -- "${E_TGT[$1]%/*}" && ln -sn -- "${E_SRC[$1]}" "${E_TGT[$1]}" ||
    { err "failed to link ${E_TGT[$1]}"; return 1; }
}

remove_link() {
  is_managed "$1" || { err "refusing to remove $1: not a managed symlink"; return 1; }
  rm -f -- "$1"
}

apply_link() {
  local i=$1 what="${E_TYPE[$1]} ${E_NAME[$1]}"
  case ${E_STATUS[i]} in
    unlinked) create_link "$i" && say linked "linked $what" && CREATED=$((CREATED + 1)) ;;
    broken) remove_link "${E_TGT[i]}" && create_link "$i" && say linked "relinked $what" && CREATED=$((CREATED + 1)) ;;
    conflict) say conflict "skipped $what: $(dim "${E_TGT[i]}") is not a managed symlink" && SKIPPED=$((SKIPPED + 1)) ;;
    collision) say collision "refused $what: several sources target $(dim "${E_TGT[i]}")" && SKIPPED=$((SKIPPED + 1)) ;;
  esac
  return 0
}

apply_unlink() {
  local i=$1 tgt=${E_TGT[$1]}
  case ${E_STATUS[i]} in
    linked | broken) ;;
    collision) [[ -L $tgt && $(link_dest "$tgt") == "${E_SRC[i]}" ]] || return 0 ;;
    *) return 0 ;;
  esac
  remove_link "$tgt" && say unlinked "unlinked ${E_TYPE[i]} ${E_NAME[i]}" && REMOVED=$((REMOVED + 1))
  return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

declare -A COUNT=()
NAME_W=0

collision_peers() {
  local j peers=""
  for j in "${!E_TGT[@]}"; do
    [[ $j != "$1" && ${E_TGT[j]} == "${E_TGT[$1]}" ]] && peers+="${peers:+, }${E_SRC[j]#"$REPO"/}"
  done
  printf '%s' "$peers"
}

print_element() { # index indent with_type
  local i=$1 name=${E_NAME[$1]} extra=""
  [[ -n ${3:-} ]] && name="${E_TYPE[i]} $name"
  case ${E_STATUS[i]} in
    broken) extra=" → $(link_dest "${E_TGT[i]}")" ;;
    conflict) extra=" (occupied, not managed)" ;;
    collision) extra=" (same target as $(collision_peers "$i"))" ;;
  esac
  printf '%s%s  %-*s %s\n' "$2" "$(badge "${E_STATUS[i]}")" "$NAME_W" "$name" "$(dim "${E_TGT[i]}$extra")"
}

cmd_list() {
  load_all
  local c i s p type title found parts=""
  for s in "${STATUS_ORDER[@]}"; do COUNT[$s]=0; done
  for i in "${!E_TYPE[@]}"; do
    s="${E_TYPE[i]} ${E_NAME[i]}"
    ((${#s} > NAME_W)) && NAME_W=${#s}
    COUNT[${E_STATUS[i]}]=$((COUNT[${E_STATUS[i]}] + 1))
  done

  heading Collections
  ((${#COLLS[@]})) || dim "  (none)"$'\n'
  for c in "${COLLS[@]}"; do
    [[ ${COLL_STATUS[$c]} == partial ]] && COUNT[partial]=$((COUNT[partial] + 1))
    printf '  %s  %s%s%s %s\n' "$(badge "${COLL_STATUS[$c]}")" "$C_BOLD" "$c" "$C_RESET" "$(dim "($(coll_size "$c") elements)")"
    for i in ${COLL_ELEMS[$c]}; do print_element "$i" '      ' with_type; done
  done

  for type in skill instruction; do
    [[ $type == skill ]] && title=Skills || title=Instructions
    heading "$title"
    found=0
    for i in "${!E_TYPE[@]}"; do
      [[ -z ${E_COLL[i]} && ${E_TYPE[i]} == "$type" ]] || continue
      print_element "$i" '  '
      found=1
    done
    ((found)) || dim "  (none)"$'\n'
  done

  if ((${#DEAD[@]})); then
    heading "Dead symlinks"
    for p in "${DEAD[@]}"; do printf '  %s  %s %s\n' "$(badge dead)" "$p" "$(dim "→ $(link_dest "$p")")"; done
    dim "  Run ./run.sh clean to remove them."$'\n'
    COUNT[dead]=${#DEAD[@]}
  fi

  for s in "${STATUS_ORDER[@]}"; do
    ((COUNT[$s])) && parts+="${parts:+ · }$(status_color "$s")${COUNT[$s]} $s${C_RESET}"
  done
  printf '\n%sSummary:%s %s\n' "$C_BOLD" "$C_RESET" "${parts:-nothing to deploy}"

  ((COUNT[broken] + COUNT[partial] + COUNT[conflict] + COUNT[collision] + COUNT[dead] == 0))
}

cmd_link() {
  load_all
  local -a labels=() kinds=() refs=()
  local c i k

  for c in "${COLLS[@]}"; do
    [[ -n ${COLL_ELEMS[$c]} && ${COLL_STATUS[$c]} != linked ]] || continue
    labels+=("$(coll_label "$c")") kinds+=(c) refs+=("$c")
  done
  for i in "${!E_TYPE[@]}"; do
    [[ -z ${E_COLL[i]} ]] || continue
    case ${E_STATUS[i]} in
      unlinked) labels+=("$(elem_label "$i")") kinds+=(e) refs+=("$i") ;;
      collision) say collision "not linkable: $(elem_label "$i") shares its target $(dim "${E_TGT[i]}") with another source" ;;
    esac
  done

  if ((${#labels[@]} == 0)); then
    summary "$C_GREEN" "${SYMBOL[linked]} nothing to link"
    return 0
  fi
  menu_select "Select resources to link" "${labels[@]}" || { warn "cancelled"; return 0; }

  for k in "${MENU_SEL[@]}"; do
    if [[ ${kinds[k]} == c ]]; then
      for i in ${COLL_ELEMS[${refs[k]}]}; do apply_link "$i"; done
    else
      apply_link "${refs[k]}"
    fi
  done
  if ((SKIPPED)); then
    summary "$C_YELLOW" "${SYMBOL[partial]} $CREATED symlink(s) created · $SKIPPED skipped"
  else
    summary "$C_GREEN" "${SYMBOL[linked]} $CREATED symlink(s) created"
  fi
}

cmd_unlink() {
  load_all
  local -a labels=() kinds=() refs=()
  local c i k

  for c in "${COLLS[@]}"; do
    [[ ${COLL_STATUS[$c]} == linked || ${COLL_STATUS[$c]} == partial ]] || continue
    labels+=("$(coll_label "$c")") kinds+=(c) refs+=("$c")
  done
  for i in "${!E_TYPE[@]}"; do
    [[ -z ${E_COLL[i]} && ${E_STATUS[i]} == linked ]] || continue
    labels+=("$(elem_label "$i")") kinds+=(e) refs+=("$i")
  done

  if ((${#labels[@]} == 0)); then
    summary "$C_GREEN" "${SYMBOL[linked]} nothing to unlink"
    return 0
  fi
  menu_select "Select resources to unlink" "${labels[@]}" || { warn "cancelled"; return 0; }

  for k in "${MENU_SEL[@]}"; do
    if [[ ${kinds[k]} == c ]]; then
      for i in ${COLL_ELEMS[${refs[k]}]}; do apply_unlink "$i"; done
    else
      apply_unlink "${refs[k]}"
    fi
  done
  summary "$C_GREEN" "${SYMBOL[linked]} $REMOVED symlink(s) removed"
}

cmd_clean() {
  load_all
  local p
  if ((${#DEAD[@]} == 0)); then
    summary "$C_GREEN" "${SYMBOL[linked]} no dead symlinks"
    return 0
  fi
  heading "Dead symlinks"
  for p in "${DEAD[@]}"; do printf '  %s  %s %s\n' "$(badge dead)" "$p" "$(dim "→ $(link_dest "$p")")"; done
  echo
  confirm "Delete ${#DEAD[@]} dead symlink(s)?" || { warn "cancelled"; return 0; }
  for p in "${DEAD[@]}"; do
    remove_link "$p" && say unlinked "removed $(dim "$p")" && REMOVED=$((REMOVED + 1))
  done
  summary "$C_GREEN" "${SYMBOL[linked]} $REMOVED dead symlink(s) removed"
}

cmd_fix() {
  load_all
  local c i p unresolved=0
  local -a stale=()

  for i in "${!E_TYPE[@]}"; do
    [[ ${E_STATUS[i]} == broken ]] && apply_link "$i"
  done
  compute_statuses

  # A collection with a linked element or a stale link is wanted: resync it.
  for c in "${COLLS[@]}"; do
    stale=()
    for p in "${DEAD[@]}"; do
      [[ $(link_dest "$p") == "$RES/collections/$c/"* ]] && stale+=("$p")
    done
    [[ ${COLL_STATUS[$c]} == partial || ${#stale[@]} -gt 0 ]] || continue
    for i in ${COLL_ELEMS[$c]}; do
      [[ ${E_STATUS[i]} == unlinked ]] && apply_link "$i"
    done
    for p in "${stale[@]}"; do
      remove_link "$p" && say unlinked "removed $(dim "$p") (no longer in collection $c)" && REMOVED=$((REMOVED + 1))
    done
  done
  compute_statuses

  for i in "${!E_TYPE[@]}"; do
    case ${E_STATUS[i]} in
      conflict) say conflict "unresolved conflict: $(elem_label "$i") $(dim "${E_TGT[i]}")" ;;
      collision) say collision "unresolved name collision: $(elem_label "$i") $(dim "${E_SRC[i]#"$REPO"/}")" ;;
      *) continue ;;
    esac
    unresolved=$((unresolved + 1))
  done
  ((${#DEAD[@]})) && warn "${#DEAD[@]} dead symlink(s) outside collections: run ./run.sh clean"

  if ((CREATED + REMOVED == 0 && unresolved == 0)); then
    summary "$C_GREEN" "${SYMBOL[linked]} nothing to fix"
  elif ((unresolved)); then
    summary "$C_YELLOW" "${SYMBOL[partial]} $CREATED linked · $REMOVED removed · $unresolved unresolved"
  else
    summary "$C_GREEN" "${SYMBOL[linked]} $CREATED linked · $REMOVED removed"
  fi
}

cmd_purge() {
  require_config
  local cache="$CLAUDE_HOME/plugins/cache" installed="$CLAUDE_HOME/plugins/installed_plugins.json"
  local -a p_path=() p_id=() p_kb=() p_orphan=() order=() labels=()
  local m p v vers kb i k total=0 freed=0 label

  [[ -f $installed ]] || warn "$installed not found: every cached plugin is tagged orphan"
  for m in "$cache"/*/; do
    for p in "$m"*/; do
      p=${p%/}
      vers=""
      for v in "$p"/*/; do v=${v%/}; vers+="${vers:+, }${v##*/}"; done
      read -r kb _ < <(du -sk -- "$p" 2>/dev/null)
      p_path+=("$p") p_id+=("${p##*/}@$(basename -- "$m")") p_kb+=("${kb:-0}")
      p_orphan+=("$([[ -f $installed ]] && grep -qF -- "\"${p##*/}@$(basename -- "$m")\"" "$installed" && echo 0 || echo 1)")
      labels+=("$vers")
    done
  done

  if ((${#p_path[@]} == 0)); then
    summary "$C_GREEN" "${SYMBOL[linked]} plugin cache is empty"
    return 0
  fi

  for i in "${!p_path[@]}"; do ((p_orphan[i])) && order+=("$i"); done
  for i in "${!p_path[@]}"; do ((p_orphan[i])) || order+=("$i"); done
  local -a menu_labels=()
  for i in "${order[@]}"; do
    label="$C_BOLD${p_id[i]}$C_RESET  $(dim "${labels[i]:-no version}")  $(human_size "${p_kb[i]}")"
    ((p_orphan[i])) && label+="  ${C_YELLOW}orphan${C_RESET}"
    menu_labels+=("$label")
  done

  menu_select "Select cached plugins to delete" "${menu_labels[@]}" || { warn "cancelled"; return 0; }

  heading "Will delete"
  for k in "${MENU_SEL[@]}"; do
    i=${order[k]}
    printf '  %s  %s  %s\n' "${p_id[i]}" "$(dim "${p_path[i]}")" "$(human_size "${p_kb[i]}")"
    total=$((total + p_kb[i]))
  done
  echo
  confirm "Delete ${#MENU_SEL[@]} cached plugin(s), $(human_size "$total")?" || { warn "cancelled"; return 0; }

  for k in "${MENU_SEL[@]}"; do
    i=${order[k]} p=${p_path[i]}
    [[ $p == "$cache"/*/* ]] || { err "refusing to delete $p: outside $cache"; continue; }
    rm -rf -- "$p" && say unlinked "deleted ${p_id[i]}" && freed=$((freed + p_kb[i]))
    rmdir -- "${p%/*}" 2>/dev/null && say unlinked "removed empty marketplace $(dim "${p%/*}")"
  done
  summary "$C_GREEN" "${SYMBOL[linked]} $(human_size "$freed") freed"
}

cmd_help() {
  cat <<EOF
${C_BOLD}run.sh${C_RESET} — deploys the skills and instructions of resources/ as symlinks into tool directories.

${C_BOLD}Usage${C_RESET}
  ./run.sh [--no-color] <command>

${C_BOLD}Commands${C_RESET}
  list         $(dim "read-only             ") Show the status of every resource; exits non-zero on problems
  link         $(dim "interactive, modifies ") Select collections and elements to symlink
  unlink       $(dim "interactive, modifies ") Select linked collections and elements to remove
  clean        $(dim "interactive, modifies ") Delete dead symlinks after one confirmation
  fix          $(dim "modifies              ") Relink broken elements and resync modified collections
  purge        $(dim "interactive, deletes  ") Delete Claude Code plugin cache entries (plugins/cache only)
  help, about  $(dim "read-only             ") Show this help

Colors are disabled with --no-color, NO_COLOR, or when stdout is not a terminal.

EOF
  if read_config; then
    printf '%sConfiguration%s %s\n' "$C_BOLD" "$C_RESET" "$(dim "$PROPS")"
    printf '  skills.target        %s\n' "${SKILLS_TGT:-${C_RED}missing${C_RESET}}"
    printf '  instructions.target  %s\n' "${INSTR_TGT:-${C_RED}missing${C_RESET}}"
    printf '  claude.home          %s\n' "${CLAUDE_HOME:-${C_RED}missing${C_RESET}}"
  else
    printf '%sConfiguration%s %srun.properties is missing%s: cp run.properties.template run.properties\n' \
      "$C_BOLD" "$C_RESET" "$C_YELLOW" "$C_RESET"
  fi
}

main() {
  local cmd="" arg
  for arg in "$@"; do
    case $arg in
      --no-color) NO_COLOR_FLAG=1 ;;
      *) if [[ -z $cmd ]]; then cmd=$arg; else cmd="$cmd $arg"; fi ;;
    esac
  done
  setup_colors
  case ${cmd:-help} in
    list) cmd_list ;;
    link) cmd_link ;;
    unlink) cmd_unlink ;;
    clean) cmd_clean ;;
    fix) cmd_fix ;;
    purge) cmd_purge ;;
    help | about | -h | --help) cmd_help ;;
    *)
      err "unknown command: $cmd"
      echo >&2
      cmd_help
      exit 2
      ;;
  esac
}

main "$@"
