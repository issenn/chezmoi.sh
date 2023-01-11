#!/usr/bin/env zsh
# shellcheck shell=bash


# -e: exit on error
# -u: exit on unset variables
set -eu

log_color() {
  color_code="$1"
  shift

  printf "\033[${color_code}m%s\033[0m\n" "$*" >&2
}

log_red() {
  log_color "0;31" "$@"
}

log_error() {
  log_red "❌" "$@"
}

error() {
  log_error "$@"
  exit 1
}

# https://github.com/twpayne/chezmoi/issues/1816
if ! chezmoi="$(command -v chezmoi)"; then
  bin_dir="${HOME}/.local/bin"
  chezmoi="${bin_dir}/chezmoi"
  echo "Installing chezmoi to '${chezmoi}'" >&2
  if command -v curl >/dev/null; then
    chezmoi_install_script="$(curl -fsSL https://get.chezmoi.io)"
  elif command -v wget >/dev/null; then
    chezmoi_install_script="$(wget -qO- https://get.chezmoi.io)"
  else
    echo "To install chezmoi, you must have curl or wget installed." >&2
    exit 1
  fi
  sh -c "${chezmoi_install_script}" -- -b "${bin_dir}"
  unset chezmoi_install_script bin_dir
fi

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
# script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"
# shellcheck disable=SC2312
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$(dirname -- "$(command -v -- "$0")")")" && pwd -P)"

CHEZMOI_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}/chezmoi"
CHEZMOI_SOURCE_DIR="."
CHEZMOI_DESTINATION_DIR="${HOME}"

# initial Chezmoi's hash definition
declare -gA CHEZMOI

CHEZMOI[DEFAULT_SOURCE_DIR]="${SCRIPT_DIR}"
CHEZMOI[DEFAULT_DESTINATION_DIR]="${XDG_DATA_HOME:-${HOME}/.local/share}/issenn"
CHEZMOI[DEFAULT_CACHE_DIR]="${CHEZMOI[DEFAULT_DESTINATION_DIR]}/.cache/chezmoi"
CHEZMOI[DEFAULT_CONFIG]="${CHEZMOI[DEFAULT_DESTINATION_DIR]}/.config/chezmoi/chezmoi.yaml"

# shellcheck source=.chezmoirc
. ".chezmoirc"

CHEZMOI[SOURCE_DIR]=""
CHEZMOI[DESTINATION_DIR]=""
CHEZMOI[CACHE_DIR]=""
CHEZMOI[CONFIG]=""
CHEZMOI[CONFIG_PATH]=""
CHEZMOI[PERSISTENT_STATE]=""

declare -ga COMMANDLINE_OPTS
declare -ga COMMANDLINE_NON_OPTS

chezmoi () {
  # if [[ -n "${DOTFILES_ONE_SHOT-}" ]]; then
  #   set -- "$@" --one-shot
  # else
  #   set -- "$@" --apply
  # fi

  # if [[ -n "${DOTFILES_DEBUG-}" ]]; then
  #   set -- "$@" --debug
  # fi

  # set -- "$@" --verbose
  echo "Running 'chezmoi $*'" >&2
  for item in "${@}"; do
    echo "DEBUG: [${item}]"
  done
  echo -e "DEBUG End.\n"
  # exec: replace current process with chezmoi
  exec "${chezmoi}" "$@"
}

parse_opts () {
  while [[ ${#} -gt 0 ]]; do
    case "${1}" in
      --config)
        _check_opts "${@}"
        CHEZMOI[CONFIG]="${2}" && shift ;;
      --config=*)
        CHEZMOI[CONFIG]="${1#*=}" ;;
      --config-path)
        _check_opts "${@}"
        CHEZMOI[CONFIG_PATH]="${2}" && shift ;;
      --config-path=*)
        CHEZMOI[CONFIG_PATH]="${1#*=}" ;;
      --persistent-state)
        _check_opts "${@}"
        CHEZMOI[PERSISTENT_STATE]="${2}" && shift ;;
      --persistent-state=*)
        CHEZMOI[PERSISTENT_STATE]="${1#*=}" ;;
      --source)
        _check_opts "${@}"
        CHEZMOI[SOURCE_DIR]="${2}" && shift ;;
      --source=*)
        CHEZMOI[SOURCE_DIR]="${1#*=}" ;;
      --cache)
        _check_opts "${@}"
        CHEZMOI[CACHE_DIR]="${2}" && shift ;;
      --cache=*)
        CHEZMOI[CACHE_DIR]="${1#*=}" ;;
      --data|--promptBool|--promptInt|--promptString)
        _check_opts "${@}"
        COMMANDLINE_OPTS+=("${1}=${2}") && shift ;;
      --data=*|--promptBool=*|--promptInt=*|--promptString=*)
        COMMANDLINE_OPTS+=("${1}") ;;
      -*)
        COMMANDLINE_OPTS+=("${1}")
        ;;
      *)
        COMMANDLINE_NON_OPTS+=("${1}")
        ;;
    esac
    shift
  done
  _check_config
  [[ -z "${CHEZMOI[SOURCE_DIR]}" ]] && CHEZMOI[SOURCE_DIR]="${CHEZMOI[DEFAULT_SOURCE_DIR]}"
  [[ -z "${CHEZMOI[DESTINATION_DIR]}" ]] && CHEZMOI[DESTINATION_DIR]="${CHEZMOI[DEFAULT_DESTINATION_DIR]}"
  [[ -z "${CHEZMOI[CACHE_DIR]}" ]] && CHEZMOI[CACHE_DIR]="${CHEZMOI[DEFAULT_CACHE_DIR]}"
}

_check_opts () {
  [[ ${#} -ge 2 ]] || error "Not enough arguments passed."
  [[ -n ${2##--*} ]] || error "Invalid argument."
}

# Automatically detected config-path from persistent-state with the same prefix filename in the same folder.
# The config-path file has the same extension as config or default config.
_check_config_path () {
  if [[ -n "${CHEZMOI[PERSISTENT_STATE]}" ]]; then
    if [[ -z "${CHEZMOI[CONFIG_PATH]}" ]]; then
      if [[ -n "${CHEZMOI[CONFIG]}" ]]; then
        CHEZMOI[CONFIG_PATH]="${CHEZMOI[PERSISTENT_STATE]%state.boltdb}${CHEZMOI[CONFIG]##*.}"
      else
        CHEZMOI[CONFIG_PATH]="${CHEZMOI[PERSISTENT_STATE]%state.boltdb}${CHEZMOI[DEFAULT_CONFIG]##*.}"
      fi
    fi
  fi
}

# Automatically detected persistent-state from config-path with the same prefix filename in the same folder.
# If a new config-path is generated, a new persistent-state needs to be generated in the same folder as the config-path.
_check_persistent_state () {
  if [[ -n "${CHEZMOI[CONFIG_PATH]}" ]]; then
    if [[ "${CHEZMOI[CONFIG_PATH]}" != "${CHEZMOI[CONFIG]}" ]]; then
      if [[ -z "${CHEZMOI[PERSISTENT_STATE]}" ]]; then
        CHEZMOI[PERSISTENT_STATE]="${CHEZMOI[CONFIG_PATH]%.*}state.boltdb"
      fi
    fi
  fi
}

_check_config () {
  if [[ -z "${CHEZMOI[CONFIG]}" ]]; then
    _check_config_path
    if [[ -z "${CHEZMOI[CONFIG_PATH]}" ]]; then
      if [[ -f "${CHEZMOI[DEFAULT_CONFIG]}" ]]; then
        CHEZMOI[CONFIG]="${CHEZMOI[DEFAULT_CONFIG]}"
        return
      else
        CHEZMOI[CONFIG_PATH]="${CHEZMOI[DEFAULT_CONFIG]}"
      fi
    fi
    _check_persistent_state
    return
  fi
  if [[ ! -f "${CHEZMOI[CONFIG]}" ]]; then
    _check_config_path
    if [[ -z "${CHEZMOI[CONFIG_PATH]}" ]]; then
      CHEZMOI[CONFIG_PATH]="${CHEZMOI[CONFIG]}"
    fi
    _check_persistent_state
    CHEZMOI[CONFIG]=""
  else
    _check_config_path
  fi
}

execute_template () {
  parse_opts "${@}"
  set --
  [[ -n "${CHEZMOI[CONFIG]}" ]] && set -- "${@}" --config="${CHEZMOI[CONFIG]}"
  [[ -n "${CHEZMOI[SOURCE_DIR]}" ]] && set -- "${@}" --source="${CHEZMOI[SOURCE_DIR]}"
  [[ -n "${CHEZMOI[DESTINATION_DIR]}" ]] && set -- "${@}" --destination="${CHEZMOI[DESTINATION_DIR]}"
  [[ -n "${CHEZMOI[CACHE_DIR]}" ]] && set -- "${@}" --cache="${CHEZMOI[CACHE_DIR]}"
  set -- "${@}" "${COMMANDLINE_OPTS[@]}"
  # exec chezmoi "execute-template" "${@}" <"${SCRIPT_DIR}/chezmoi_home/.chezmoi.yaml.tmpl"
  exec chezmoi "execute-template" "${@}" "${COMMANDLINE_NON_OPTS[@]:-$(</dev/stdin)}"
}

init () {
  parse_opts "${@}"
  set --
  [[ -n "${CHEZMOI[CONFIG]}" ]] && set -- "${@}" --config="${CHEZMOI[CONFIG]}"
  if [[ -n "${CHEZMOI[CONFIG_PATH]}" ]]; then
    set -- "${@}" --config-path="${CHEZMOI[CONFIG_PATH]}"
  else
    set -- "${@}" --config-path="${CHEZMOI[CONFIG]}"
  fi
  [[ -n "${CHEZMOI[PERSISTENT_STATE]}" ]] && set -- "${@}" --persistent-state="${CHEZMOI[PERSISTENT_STATE]}"
  [[ -n "${CHEZMOI[SOURCE_DIR]}" ]] && set -- "${@}" --source="${CHEZMOI[SOURCE_DIR]}"
  [[ -n "${CHEZMOI[DESTINATION_DIR]}" ]] && set -- "${@}" --destination="${CHEZMOI[DESTINATION_DIR]}"
  [[ -n "${CHEZMOI[CACHE_DIR]}" ]] && set -- "${@}" --cache="${CHEZMOI[CACHE_DIR]}"
  set -- "${@}" "${COMMANDLINE_OPTS[@]}"
  exec chezmoi "init" "${@}"
}

apply () {
  parse_opts "${@}"
  set --
  [[ -n "${CHEZMOI[CONFIG]}" ]] && set -- "${@}" --config="${CHEZMOI[CONFIG]}"
  [[ -n "${CHEZMOI[SOURCE_DIR]}" ]] && set -- "${@}" --source="${CHEZMOI[SOURCE_DIR]}"
  [[ -n "${CHEZMOI[DESTINATION_DIR]}" ]] && set -- "${@}" --destination="${CHEZMOI[DESTINATION_DIR]}"
  [[ -n "${CHEZMOI[CACHE_DIR]}" ]] && set -- "${@}" --cache="${CHEZMOI[CACHE_DIR]}"
  set -- "${@}" "${COMMANDLINE_OPTS[@]}"
  exec chezmoi "apply" "${@}"
}

main () {
  case "${1}" in
    "init")
      shift 1
      init "${@}"
      ;;
    "apply")
      shift 1
      apply "${@}"
      ;;
    "execute-template")
      shift 1
      execute_template "${@}"
      ;;
    *)
      # exec: replace current process with chezmoi
      exec chezmoi "${@}"
      ;;
  esac
}

main "${@}"
