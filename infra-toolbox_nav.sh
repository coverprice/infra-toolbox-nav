# This file is intended to be `source'd` by .bashrc
# It adds various functions for navigating around the infra-toolbox repo(s), and managing the state of
# virtualenvs therein.
#
# SETUP
# -----
# 1) In your .bashrc, make sure 'REPO_HOME' points to your directory where all your infra-toolbox
#    repos are stored, e.g. "${HOME}/myrepos". (Each repo is expected to be under its own directory)
#    e.g. $HOME/myrepos/repo1/infra-toolbox/.git , $HOME/myrepos/anotherrepo/infra-toolbox/.git, ...
#    These repos will be referred to in commands as `repo1` and `anotherrepo`
#
# 2) Make sure virtualenv and virtualenv wrapper are installed and set up.
#
# 3) Add this script to your .bashrc:
#   [[ -f /path/to/this/script.sh ]] && source /path/to/this/script.sh
#
#
# USAGE
# -----
# switchrepo REPONAME
#     cd to the top of REPONAME, and activate the last activated venv there.
#
# [All commands below are expected to be called from within an infra-toolbox repo]
#
# == Various shortcuts to quickly setup / navigate / destroy venvs ==
# venv on [refresh]
#     From the current dir, walk upwards to find the nearest pyproject.toml, activate its venv, and set this
#     venv to be the "active venv" within this repo. (This means that any new shell created within the repo
#     will automatically activate that env.)
#
#     If not in a repo or no pyproject.toml found, show an error.
#     If the venv doesn't exist, create it.
#     If the 'fresh' option is given, the venv will be recreated no matter what.
#
#     NB: the directory holding the venv (i.e. the python libs and binaries) will be in the same directory
#     as the pyproject.toml.
# 
# venv off
#     Deactivate the current venv if there is one, and set the "active venv" to None. New shells will not be
#     in a venv.
#
# venv destroy
#     Same as 'venv off' except the .venv will also be deleted.
#
# venv go PROJECT
#     change directory to PROJECT, which is one of the Atlas apps or libs (e.g. 'atlas', 'aws-pruner', 'dpp-utils')
#     and activate the venv there.
#     Autocomplete on PROJECT is supported.
#
# 
# == Convenience shortcuts to quickly change directories within a repo ==
#
# cdd PROJECT
#     change directory to PROJECT, which is one of the Atlas apps or libs (e.g. 'atlas', 'aws-pruner', 'dpp-utils').
#     Do not modify the current venv (if there is one)
#     Autocomplete on PROJECT is supported.
# cdtop
#     cd to $REPO_TOP/
# cdlibs
#     cd to $REPO_TOP/libs
# cdapps
#     cd to $REPO_TOP/apps
# cdat
#     cd to $REPO_TOP/apps/atlas/atlas
# cdpylibs
#     cd to the current venvs's directory of installed packages. This is useful for inspecting the source code of
#     any installed libs.
# cdsup
#     cd to /apps/support-toolkit and activate the venv there. This is where much of the CLI tool running is done from.


# ========================================
# Functions that work over multiple repos.
# ========================================


# cd to another repo under REPO_HOME
#
# Usage:
#   switchrepo REPONAME
# Example:
#   switchrepo myrepo
function switchrepo() {
  local - reponame=$1 repodir
  set -e
  if [[ -z $REPO_HOME ]] ; then
    echo "ERROR: REPO_HOME not defined"
    return
  fi
  if [[ -z $reponame ]] ; then
    echo "You must specify a repo name, under ${REPO_HOME}"
    return
  fi
  repodir="${REPO_HOME}/${reponame}"
  if [[ ! -d $repodir ]] ; then
    echo "Directory does not exist: '${repodir}'"
    return
  fi
  cd "${repodir}"
  # shellcheck disable=SC2155
  local src_top="$(readlink -f "./infra-toolbox")"
  if [[ -d $src_top ]] ; then
    cd "${src_top}"
    export CDPATH=".:${src_top}:${src_top}/apps/atlas/atlas"
  fi

  # This _GIT_TOP is a cache, so clear it.
  unset _GIT_TOP
}

# Print out a list of all repos, along with the branch they're currently checked out to.
#
# Usage:
#   allbranches
function allbranches() {
  local dir_name
  if [[ -z $REPO_HOME ]] ; then
    echo "ERROR: REPO_HOME not defined"
    return
  fi
  for git_dir in "${REPO_HOME}"/*/infra-toolbox/.git ; do
    dir_name="$(basename "$(dirname "$(dirname "${git_dir}")")")"
    printf "%s: %s\n" "${dir_name}" "$(git --git-dir "${git_dir}" rev-parse --abbrev-ref HEAD)"
  done
}


# =======================================================
# Functions for manipulating venvs within a specific repo
# =======================================================

function venv() {
  local - command=$1
  shift

  case $command in
    on)
      _venv_on
      ;;
    off)
      _venv_off
      ;;
    destroy)
      _venv_off destroy
      ;;
    go)
      _venv_go "$@"
      ;;
    *)
      echo "ERROR: Unknown command '$command'"
      ;;
  esac
}


function _venv_autocomplete {
  # This autocompletes the 'venv go <dpp-project>'

  # shellcheck disable=SC2034
  local command_name="${1}" word_being_completed="${2}" word_preceding="${3}"
  unset COMPREPLY
  if [[ $word_preceding != 'go' ]]; then
    return
  fi
  
  _get_project_options
  [[ ! -v _PROJECT_OPTIONS ]] && return
  mapfile -t COMPREPLY < <(compgen -W "${_PROJECT_OPTIONS[*]}" "${word_being_completed}")
}
complete -o default -o bashdefault -F _venv_autocomplete venv


# Finds the nearest project directory (or the Repo's Active Project if not found) and activates the venv.
# If there is no venv, it creates one.
# INPUT:
#   NONE
# OUTPUT:
#   VIRTUAL_ENV
function _venv_on() {
  local project_path_to_activate
  _get_git_top
  [[ -z $_GIT_TOP ]] && return

  _get_nearest_poetry_project_dir
  if [[ -n $_POETRY_PROJECT_PATH ]] ; then
    project_path_to_activate="${_POETRY_PROJECT_PATH}"
  else
    # We're in a repo, but not in a project dir. So try to use the current active project if it exists.
    _get_repo_active_project_dir
    if [[ -n $_REPO_ACTIVE_PROJECT_DIR ]] && [[ -d $_REPO_ACTIVE_PROJECT_DIR ]] ; then
      project_path_to_activate="${_REPO_ACTIVE_PROJECT_DIR}"
    fi
  fi
  if [[ -z $project_path_to_activate ]]; then
    echo "ERROR: Could not find an appropriate project to activate. Try 'venv go <tab>'"
    return 1
  fi

  _activate_poetry_project_venv "${project_path_to_activate}"
}


# Deactivate the current venv, and remove the "current active project" file
function _venv_off() {
  local destroy="${1}"
  local active_project_path
  _deactivate_venv

  _get_git_top
  [[ -z $_GIT_TOP ]] && return 1

  if [[ $destroy == 'destroy' ]] ; then
    _get_repo_active_project_dir
    if [[ -n $_REPO_ACTIVE_PROJECT_DIR ]] && [[ -d "${_REPO_ACTIVE_PROJECT_DIR}/.venv" ]]; then
      _destroy_venv_dir "${_REPO_ACTIVE_PROJECT_DIR}/.venv"
    fi
  fi

  active_project_path="${_GIT_TOP}/.venv"
  [[ -e $active_project_path ]] && rm -f "${active_project_path}"
}


# Activate a specific project
#
# INPUT:
#   $1 - string - name of a project (dir name under /apps or /libs)
# OUTPUT:
#   VIRTUAL_ENV
function _venv_go() {
  local project="${1}" project_path_to_activate

  _get_git_top
  [[ -z $_GIT_TOP ]] && return

  if [[ -d "${_GIT_TOP}/apps/${project}" ]] ; then
    project_path_to_activate="${_GIT_TOP}/apps/${project}"
  elif [[ -d "${_GIT_TOP}/libs/${project}" ]] ; then
    project_path_to_activate="${_GIT_TOP}/libs/${project}"
  else
    echo "ERROR: unknown project '${project}'"
    return 1
  fi

  _activate_poetry_project_venv "${project_path_to_activate}"
  cd "${project_path_to_activate}"
}


# =====================================================
# Functions for navigating within an infra-toolbox repo
# =====================================================

# cd the repo's top dir
function cdtop() {
  _get_git_top
  [[ -n $_GIT_TOP ]] && cd "${_GIT_TOP}"
}

# cd to the repo's /apps directory
function cdapps() {
  _get_git_top
  [[ -n $_GIT_TOP ]] && cd "${_GIT_TOP}/apps"
}

# cd to the repo's /libs directory
function cdlibs() {
  _get_git_top
  [[ -n $_GIT_TOP ]] && cd "${_GIT_TOP}/libs"
}

# cd to Atlas's main work directory
function cdat() {
  _get_git_top
  [[ -n $_GIT_TOP ]] && cd "${_GIT_TOP}/apps/atlas/atlas"
}

# cd to the current venv's installed Python libaries. (Useful for inspecting source code of Python packages)
function cdpylibs() {
  if [[ -z $VIRTUAL_ENV ]] ; then
    echo "ERROR: No virtualenv is currently activated."
    return
  fi
  local - dir="${VIRTUAL_ENV}/lib/python3.9/site-packages"
  if [[ -d $dir ]]; then
    cd "${dir}"
  else
    echo "ERROR: ${dir} does not exist"
  fi
}

# cd to the support-toolkit directory (and activate the venv)
function cdsup() {
  _get_git_top
  if [[ -z $_GIT_TOP ]]; then
    return 1
  fi
  cd "${_GIT_TOP}/apps/support-toolkit"

  _venv_on
}

# Change directory to the given PROJECT ('atlas', 'aws-pruner', 'dpp-utils', ...)
# PROJECT is auto-completable with Tab.
#
# Usage:
#   cdd PROJECT
# Example:
#   cdd dpp-utils
function cdd() {
  local project=$1
  _get_git_top
  [[ -z $_GIT_TOP ]] && return
  if [[ -d "${_GIT_TOP}/apps/${project}" ]]; then
    cd "${_GIT_TOP}/apps/${project}"
  elif [[ -d "${_GIT_TOP}/libs/${project}" ]]; then
    cd "${_GIT_TOP}/libs/${project}"
  else
    echo "ERROR: no such project ${project}"
  fi
}

function _cdd_autocomplete() {
  # This autocompletes the 'venv go <dpp-project>'
  # shellcheck disable=SC2034
  local command_name="${1}" word_being_completed="${2}" word_preceding="${3}"
  unset COMPREPLY

  _get_project_options
  [[ ! -v _PROJECT_OPTIONS ]] && return
  mapfile -t COMPREPLY < <(compgen -W "${_PROJECT_OPTIONS[*]}" "${word_being_completed}")
}
complete -o default -o bashdefault -F _cdd_autocomplete cdd


# ==========================
# Internal utility functions
# ==========================


# INPUT: None
# OUTPUT:
#   @return _GIT_TOP - envvar string - Path to top directory of current git repo. Empty if not in a DPP git repo.
function _get_git_top() {
  _get_git_top_silent
  if [[ -z $_GIT_TOP ]] ; then
    echo "ERROR: Currently not in a git repo"
  fi
}
function _get_git_top_silent() {
  _GIT_TOP="$(git rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
}


# INPUT: None
# OUTPUT:
#   @return _PROJECT_OPTIONS - envvar array - an array of the project names available in the repo (projects are under /apps and /libs,
#   e.g. 'atlas', 'aws-pruner', ..., 'dpp-utils'). This is used for autocomplete.
function _get_project_options() {
  unset _PROJECT_OPTIONS
  [[ ! -v _GIT_TOP ]] && _get_git_top
  [[ -z $_GIT_TOP ]] && return
  mapfile -t _PROJECT_OPTIONS < <(find "${_GIT_TOP}/apps" "${_GIT_TOP}/libs" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
}


# INPUT: None
# OUTPUT:
#   @return _POETRY_PROJECT_PATH - envvar string - path to the poetry project the current dir belongs to, or empty.
function _get_nearest_poetry_project_dir() {
  _POETRY_PROJECT_PATH=
  [[ ! -v _GIT_TOP ]] && _get_git_top
  [[ -z $_GIT_TOP ]] && return

  local cur_dir
  cur_dir="${PWD}"
  while [[ $cur_dir != "${_GIT_TOP}" ]] && [[ $cur_dir != "/" ]] ; do
    if [[ -f "${cur_dir}/pyproject.toml" ]] ; then
      _POETRY_PROJECT_PATH="${cur_dir}"
      return
    else
      cur_dir=$(dirname "${cur_dir}")
    fi
  done
}


# INPUT:
#   $1 - path to a directory containing a poetry project
#   $2 - if 'refresh' then the venv will be destroyed and re-created if it already exists.
# OUTPUT:
#   @return return code: 0 on success, 1 on failure
#   @return VIRTUAL_ENV - envvar string - path to the activated virtual env
#
#  The path to the activated project will be put into $_GIT_TOP/.venv
function _activate_poetry_project_venv() {
  local project_dir="${1}" refresh="${2}"
  local venv_path

  if [[ ! -d $project_dir ]]; then
    echo "ERROR: Not a project directory: ${project_dir}"
    return 1
  fi

  pushd "${project_dir}" >/dev/null
  _get_git_top
  popd >/dev/null
  if [[ -z $_GIT_TOP ]]; then
    echo "ERROR: project directory is not inside a git repo"
    return 1
  fi

  _deactivate_venv

  venv_path="${project_dir}/.venv"
  if [[ -e $venv_path ]] && [[ $refresh == 'refresh' ]] ; then
    rm -rf "${venv_path}"
  fi

  # Create virtualenv if it doesn't exist
  if [[ ! -d $venv_path ]]; then
    virtualenv --python="$(which python3)" "${venv_path}"
  fi

  echo -n "${project_dir}" > "${_GIT_TOP}/.venv"
  source "${venv_path}/bin/activate"
}


# OUTPUT:
#    _REPO_ACTIVE_PROJECT_DIR - envvar string - the contents of the .venv file at the top of the repo. This
#               file contains a path to the "active" project. (This doesn't mean the project's venv exists or is activated,
#               it means it *should* exist and be activated)
function _get_repo_active_project_dir() {
  unset _REPO_ACTIVE_PROJECT_DIR
  [[ ! -v _GIT_TOP ]] && _get_git_top
  [[ -z $_GIT_TOP ]] && return 1

  local path="${_GIT_TOP}/.venv"
  if [[ -f $path ]]; then
    _REPO_ACTIVE_PROJECT_DIR="$(<"${_GIT_TOP}/.venv")"
  fi
}


# If already in a venv, deactivate it.
function _deactivate_venv() {
  [[ $(type -t deactivate) == "function" ]] && deactivate
  unset VIRTUAL_ENV
}


# Destroys a venv's directory, with some sanity checks.
#
# INPUT:
#   $1 - full path to a virtual env directory
# OUTPUT:
#   None
function _destroy_venv_dir() {
  local path="${1}"
  if [[ ! -d $path ]] ; then
    echo "ERROR: Cannot destroy venv, $path does not exist."
    return 1
  fi
  if [[ ! -e "${path}/bin/activate" ]]; then
    echo "ERROR: Out of an abudance of caution, will not destroy venv, $path does not appear to be a venv. (Missing bin/activate)"
    return 1
  fi
  rm -rf "${path}"
}


# Looks for a .venv file in the PWD or above, and activates it. Used when tmux
# creates a new pane in the current directory, which by default won't inherit
# the current virtualenv environment.
function _venv_auto_activate() {
  _get_git_top_silent
  [[ -z $_GIT_TOP ]] && return

  _get_repo_active_project_dir
  if [[ -n $_REPO_ACTIVE_PROJECT_DIR ]]; then
    if [[ -f "${_REPO_ACTIVE_PROJECT_DIR}/.venv/bin/activate" ]] ; then
      source "${_REPO_ACTIVE_PROJECT_DIR}/.venv/bin/activate"
    else
      echo "WARNING: Repo's active project ${_REPO_ACTIVE_PROJECT_DIR} does not have a valid venv."
    fi
  fi
}
_venv_auto_activate


# INPUT
#  $1 - string - path to git top directory
function _active_project_prompt() {
  local git_top="${1}" project_name

  _ACTIVE_PROJECT_PROMPT=
  [[ -z $git_top ]] && return

  _GIT_TOP="${git_top}"
  _get_repo_active_project_dir
  if [[ -z $_REPO_ACTIVE_PROJECT_DIR ]]; then
    _ACTIVE_PROJECT_PROMPT="$(printf "%s[No active project]%s " "${COLOR_RED}" "${COLOR_RESET}")"
    return
  fi

  project_name="$(basename "${_REPO_ACTIVE_PROJECT_DIR}")"
  if [[ ! -d "${_REPO_ACTIVE_PROJECT_DIR}/.venv" ]]; then
    _ACTIVE_PROJECT_PROMPT="$(printf "%s[%s]%s " "${COLOR_RED}" "${project_name}" "${COLOR_RESET}")"
    return
  fi

  if [[ $VIRTUAL_ENV != "${_REPO_ACTIVE_PROJECT_DIR}/.venv" ]]; then
    _ACTIVE_PROJECT_PROMPT="$(printf "%s[%s XXX different venv XXX]%s " "${COLOR_RED}" "${project_name}" "${COLOR_RESET}")"
    return
  fi

  # shellcheck disable=SC2034
  _ACTIVE_PROJECT_PROMPT="$(printf "%s[%s]%s " "${COLOR_LIGHT_BLUE}" "${project_name}" "${COLOR_RESET}")"
}
