# This file is intended to be `source'd` by .bashrc
# It adds various functions for navigating around the infra-toolbox repo(s), and managing the state of
# virtualenvs therein.
#
# SETUP
# -----
# 1) In your `.bashrc`, point 'REPO_HOME' to your directory where all your infra-toolbox
#    repos are stored, e.g. "${HOME}/myrepos".
#    e.g. $HOME/myrepos/infra-toolbox01/.git , $HOME/myrepos/infra-toolbox02/.git, $HOME/myrepos/foo/.git, ...
#    These repos will be referred to in commands as `infra-toolbox01`, `infra-toolbox02`, and `foo` respectively.
#
# 2) In your `.bashrc`, point 'VENV_HOME' to your directory where Python virtual environments should be created
#    repos are stored, e.g. "${HOME}/venvs".
#    Virtual environments will be created here under directories matching their corresponding repo name.
#
# 3) Add this script to your .bashrc:
#   [[ -f /path/to/this/script.sh ]] && source /path/to/this/script.sh
#
#
# USAGE
# -----
# repo REPONAME
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
#   repo REPONAME
# Example:
#   repo myrepo
function repo() {
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
  if [[ ! -d "${repodir}/.git" ]] ; then
    echo "Directory does not appear to be a git repository. '${repodir}'"
    return
  fi
  cd "${repodir}"

  # Refresh _GIT_TOP.
  _get_git_top
  if [[ -n $_GIT_TOP ]] && $_IS_MONOREPO ; then
    export CDPATH=".:${repodir}:${repodir}/apps/atlas/atlas"
  else
    export CDPATH=".:${repodir}"
  fi

  # Attempt to activate a venv
  _venv_on
  if [[ -n $_GIT_TOP ]] && [[ -n $_REPO_ACTIVE_PROJECT_DIR ]] ; then
    cd "${_GIT_TOP}/${_REPO_ACTIVE_PROJECT_DIR}"
  fi
}


function _repo_autocomplete() {
  # This autocompletes the 'repo <some-repo>'
  # shellcheck disable=SC2034
  local command_name="${1}" word_being_completed="${2}" word_preceding="${3}" repo_options
  unset COMPREPLY

  [[ -z $REPO_HOME ]] && return
  mapfile -t repo_options < <(find "${REPO_HOME}" -maxdepth 2 -mindepth 2 -name .git -type d -printf "%h\n" | sed -e 's#^.*/##')
  [[ ! -v repo_options ]] && return
  mapfile -t COMPREPLY < <(compgen -W "${repo_options[*]}" "${word_being_completed}")
}
complete -o default -o bashdefault -F _repo_autocomplete repo


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
    help|info|usage)
      _venv_usage
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


function _venv_usage() {
  cat <<"EOF"
Usage:
  repo REPONAME               Change directories to the repo and activate the most recently activated venv there.

  venv [info | help | usage]  Display this help
  venv go [COMPONENT]         Change directories and venvs to the given COMPONENT (which is auto-completeable)
                                 In infra-toolbox, 'COMPONENT' refers to an app or library.
                                 In other repos, this is not used and is equivalent to `venv on`.
  venv off                    Deactivate the current venv
  venv destroy                Deactivate and delete the current venv
  venv refresh                Destroy the current venv and recreate it

  cdtop                       Change directories to this repo's top level
  cdd COMPONENT               [Infra-toolbox repos only] cd to the given COMPONENT (which is auto-completeable)
  cdapps                      [Infra-toolbox repos only] cd to $REPO/apps
  cdlibs                      [Infra-toolbox repos only] cd to $REPO/libs
  cdsup                       [Infra-toolbox repos only] cd to the support-toolkit & activate the venv.
  cdpylibs                    Change directories to the venv's lib/site-packages dir
  cdpylibs64                  Change directories to the venv's lib64/site-packages dir
EOF
}


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

  _guess_project_to_activate
  if [[ -z $_PROJECT_PATH_TO_ACTIVATE ]]; then
    echo "ERROR: Could not find an appropriate project to activate. Try 'venv go <tab>'"
    return 1
  fi

  _activate_venv "${_PROJECT_PATH_TO_ACTIVATE}"
  _get_git_top
}


# Deactivate the current venv, and remove the "current active project" file
function _venv_off() {
  local destroy="${1}"
  local active_project_store
  _deactivate_venv

  _get_git_top
  [[ -z $_GIT_TOP ]] && return 1
  active_project_store="${_REPO_METADATA_PATH}/current_project.txt"
  [[ -e $active_project_store ]] && rm -f "${active_project_store}"
  unset _REPO_ACTIVE_PROJECT_DIR

  if [[ $destroy == "destroy" ]] && [[ -n $_REPO_ACTIVE_PROJECT_DIR ]] ; then
    local venv_dir="${_REPO_METADATA_PATH}/${_REPO_ACTIVE_PROJECT_DIR}/venv"
    [[ -e $venv_dir ]] && _destroy_venv_dir "${venv_dir}"
  fi
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

  if [[ -z $project ]] || ! $_IS_MONOREPO ; then
    _guess_project_to_activate
    if [[ -z $_PROJECT_PATH_TO_ACTIVATE ]] ; then
      echo "ERROR: Could not guess which project to activate."
      return 1
    fi
    project_path_to_activate="${_PROJECT_PATH_TO_ACTIVATE}"

  else
    if [[ -d "${_GIT_TOP}/apps/${project}" ]] ; then
      project_path_to_activate="apps/${project}"
    elif [[ -d "${_GIT_TOP}/libs/${project}" ]] ; then
      project_path_to_activate="libs/${project}"
    else
      echo "ERROR: unknown project '${project}'"
      return 1
    fi
  fi

  _activate_venv "${project_path_to_activate}"
  cd "${_GIT_TOP}/${project_path_to_activate}"
  _get_git_top
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
  [[ -n $_GIT_TOP ]] && $_IS_MONOREPO cd "${_GIT_TOP}/apps"
}

# cd to the repo's /libs directory
function cdlibs() {
  _get_git_top
  [[ -n $_GIT_TOP ]] && $_IS_MONOREPO && cd "${_GIT_TOP}/libs"
}

# cd to Atlas's main work directory
function cdat() {
  _get_git_top
  [[ -n $_GIT_TOP ]] && $_IS_MONOREPO && cd "${_GIT_TOP}/apps/atlas/atlas"
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

function cdpylibs64() {
  if [[ -z $VIRTUAL_ENV ]] ; then
    echo "ERROR: No virtualenv is currently activated."
    return
  fi
  local - dir="${VIRTUAL_ENV}/lib64/python3.9/site-packages"
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
  if ! $_IS_MONOREPO ; then
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
  if $_IS_MONOREPO ; then
    if [[ -d "${_GIT_TOP}/apps/${project}" ]]; then
      cd "${_GIT_TOP}/apps/${project}"
    elif [[ -d "${_GIT_TOP}/libs/${project}" ]]; then
      cd "${_GIT_TOP}/libs/${project}"
    else
      echo "ERROR: no such project ${project}"
    fi
  else
    cd "${_GIT_TOP}"
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


# Purpose: Determines various attributes of the repo pointed to by the current directory.
# INPUT: None
# OUTPUT:
#   @return
#      _GIT_TOP - envvar string - Path to top directory of current git repo. Empty if not in a git repo.
#      _IS_MONOREPO - envvar string - `true` if this is infra-toolbox, `false` for all other repos
#      _REPO_METADATA_PATH - absolute path to directory where this repos Venvs and other metadata is stored.
#      _REPO_ACTIVE_PROJECT_DIR - envvar string - the path (relative to the top of the current repo) of the current
#           active project. (This doesn't mean the project's venv exists or is activated, it means it *should* exist
#           and be activated)
function _get_git_top() {
  unset _GIT_TOP
  unset _IS_MONOREPO
  unset _REPO_METADATA_PATH
  unset _REPO_ACTIVE_PROJECT_DIR
  _get_git_top_silent
  if [[ -z $_GIT_TOP ]] ; then
    echo "ERROR: Currently not in a git repo"
  fi
  if [[ "${_GIT_TOP#"${REPO_HOME}/"}" == "${_GIT_TOP}" ]] ; then
    unset _GIT_TOP
    echo "ERROR: Git repo not currently under dir: ${REPO_HOME}"
    return
  fi

  if [[ -z $VENV_HOME ]] ; then
    echo "ERROR: VENV_HOME not set"
  fi

  if [[ -d "${_GIT_TOP}/apps/atlas" ]] ; then
    _IS_MONOREPO=true
  else
    _IS_MONOREPO=false
  fi

  _REPO_METADATA_PATH="${VENV_HOME}/$(basename "${_GIT_TOP}")"
  if [[ ! -d $_REPO_METADATA_PATH ]] ; then
    mkdir -p "${_REPO_METADATA_PATH}"
  fi

  local active_project_store="${_REPO_METADATA_PATH}/current_project.txt"
  if [[ -f $active_project_store ]]; then
    _REPO_ACTIVE_PROJECT_DIR="$(<"${active_project_store}")"
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
  if ! $_IS_MONOREPO ; then
    return
  fi
  mapfile -t _PROJECT_OPTIONS < <(find "${_GIT_TOP}/apps" "${_GIT_TOP}/libs" -mindepth 1 -maxdepth 1 -type d -printf "%f\n")
}


# INPUT: None
# OUTPUT:
#   @return _PROJECT_PATH - envvar string - path (relative to the top of the git repo) to the project the current dir
#                                           belongs to, or empty.
function _get_nearest_project_dir() {
  _PROJECT_PATH=
  [[ ! -v _GIT_TOP ]] && _get_git_top
  [[ -z $_GIT_TOP ]] && return

  local cur_dir
  cur_dir="${PWD}"
  while [[ $cur_dir != "${_GIT_TOP}" ]] && [[ $cur_dir != "/" ]] ; do
    if [[ -f "${cur_dir}/pyproject.toml" ]] || [[ -f "${cur_dir}/requirements.txt" ]] ; then
      # Return the project path
      _PROJECT_PATH="${cur_dir#"${_GIT_TOP}/"}"
      if [[ "${_PROJECT_PATH}" == "${cur_dir}" ]] ; then
         echo "ERROR: assert failure. _GIT_TOP was not correctly stripped as a prefix from cur_dir: ${cur_dir}"
         return 1
      fi
      return
    else
      cur_dir=$(dirname "${cur_dir}")
    fi
  done
}


# Assumes _get_git_top has been called. Tries to determine from the current directory
# what project to automatically activate.
# - For regular repos, this means the "top" project (".")
# - For monorepos, it will look at the current directory and work its way towards the top
#     until it finds an app/lib project dir. If it does not find one, then it tries
#     to use the project name stored in "$VENV_HOME/$REPO_NAME/current_project.txt"
#
# INPUT:
#   _GIT_TOP et al
# OUTPUT:
#   _PROJECT_PATH_TO_ACTIVATE - envvar string - path relative to _GIT_TOP (empty if it couldn't find one)
function _guess_project_to_activate() {
  unset _PROJECT_PATH_TO_ACTIVATE
  if $_IS_MONOREPO ; then
    _get_nearest_project_dir
    if [[ -n $_PROJECT_PATH ]] ; then
      _PROJECT_PATH_TO_ACTIVATE="${_PROJECT_PATH}"
    else
      # We're in a repo, but not in a project dir. So try to use the current active project if it exists.
      if [[ -n $_REPO_ACTIVE_PROJECT_DIR ]] && [[ -d $_REPO_ACTIVE_PROJECT_DIR ]] ; then
        _PROJECT_PATH_TO_ACTIVATE="${_REPO_ACTIVE_PROJECT_DIR}"
      fi
    fi
  else
    _PROJECT_PATH_TO_ACTIVATE="."
  fi
}


# INPUT:
#   $_GIT_TOP - path to the top of the git repo
#   $1 - path relative to $_GIT_TOP containing a poetry project / requirements.txt file. (must be under $_GIT_TOP)
#   $2 - if 'refresh' then the venv will be destroyed and re-created if it already exists.
# OUTPUT:
#   @return return code: 0 on success, 1 on failure
#   @return VIRTUAL_ENV - envvar string - path to the activated virtual env
#
#  The path to the activated project will be put into $_GIT_TOP/.venv
function _activate_venv() {
  local project_dir="${1}" refresh="${2}"
  local venv_path was_venv_created=false

  if [[ -z $VENV_HOME ]] || [[ -z $_GIT_TOP ]] || [[ -z $_REPO_METADATA_PATH ]] ; then
    echo "ERROR: VENV_HOME, _GIT_TOP, or _REPO_METADATA_PATH not defined"
    return 1
  fi

  if [[ ! -d "${_GIT_TOP}/${project_dir}" ]]; then
    echo "ERROR: Not a project directory: ${_GIT_TOP}/${project_dir}"
    return 1
  fi

  _deactivate_venv

  venv_path="${_REPO_METADATA_PATH}/${project_dir}/venv"
  if [[ -e $venv_path ]] && [[ $refresh == 'refresh' ]] ; then
    _destroy_venv_dir "${venv_path}"
  fi

  # Create virtualenv if it doesn't exist
  if [[ ! -d $venv_path ]]; then
    echo "$venv_path is not a directory, so creating the venv:"
    mkdir -p "${venv_path}"
    python3 -m venv "${venv_path}"
    was_venv_created=true
  fi

  echo -n "${project_dir}" > "${_REPO_METADATA_PATH}/current_project.txt"
  source "${venv_path}/bin/activate"
  if $was_venv_created ; then
    pip3 install --upgrade pip
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

  if [[ -n $_REPO_METADATA_PATH ]] && [[ -n $_REPO_ACTIVE_PROJECT_DIR ]]; then
    local venv_path="${_REPO_METADATA_PATH}/${_REPO_ACTIVE_PROJECT_DIR}/venv"
    if [[ -f "${venv_path}/bin/activate" ]] ; then
      source "${venv_path}/bin/activate"
    else
      echo "WARNING: Repo's active project does not have a valid venv: ${venv_path}"
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

  if [[ -z $VIRTUAL_ENV ]] ; then
    return
  fi

  _GIT_TOP="${git_top}"
  if [[ -z $_REPO_ACTIVE_PROJECT_DIR ]]; then
    _ACTIVE_PROJECT_PROMPT="$(printf "%s[No active project]%s " "${COLOR_RED}" "${COLOR_RESET}")"
    return
  fi

  if [[ $_REPO_ACTIVE_PROJECT_DIR == "." ]] ; then
    project_name="repo-wide venv"
  else
    project_name="$(basename "${_REPO_ACTIVE_PROJECT_DIR}")"
  fi
  # shellcheck disable=SC2155
  local venv_path="$(readlink -f "${_REPO_METADATA_PATH}/${_REPO_ACTIVE_PROJECT_DIR}/venv")"
  if [[ ! -d $venv_path ]]; then
    _ACTIVE_PROJECT_PROMPT="$(printf "%s[%s]%s " "${COLOR_RED}" "${project_name}" "${COLOR_RESET}")"
    return
  fi

  if [[ $VIRTUAL_ENV != "${venv_path}" ]]; then
    _ACTIVE_PROJECT_PROMPT="$(printf "%s[%s XXX different venv XXX]%s " "${COLOR_RED}" "${project_name}" "${COLOR_RESET}")"
    return
  fi

  # shellcheck disable=SC2034
  _ACTIVE_PROJECT_PROMPT="$(printf "%s[%s]%s " "${COLOR_LIGHT_BLUE}" "${project_name}" "${COLOR_RESET}")"
}
