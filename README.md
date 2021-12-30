# infra-toolbox-nav
Bash functions for navigating around the infra-toolbox monorepo.

This file is intended to be `source'd` by .bashrc It adds various functions for navigating around the
infra-toolbox repo(s), and managing the state of Python virtualenvs therein.

## Installation

1. In your `~/.bashrc`, make sure `REPO_HOME` points to a directory where all your `infra-toolbox`
   repos are stored, e.g. `${HOME}/myrepos`. (Each repo is expected to be under its own directory
   e.g. `$HOME/myrepos/repo1/infra-toolbox/.git`, `$HOME/myrepos/anotherrepo/infra-toolbox/.git`, ... )

2. Make sure virtualenv is installed.

3. Add this script to your .bashrc:

```
[[ -f /path/to//infra-tools_nav.sh ]] && source /path/to/infra-tools_nav.sh
```

## Usage

### Cross repo commands
Commands in this section act on 1-many repos.

#### `switchrepo REPONAME`
cd to the top of `REPONAME`, and activate the last activated venv there.

#### `allbranches`
Display the list of all repos, and what git branch they're checked out to.


### Repo-specific commands

All commands below are expected to be called from within an `infra-toolbox` repo.

#### `venv on [refresh]`
Walk upwards from the current dir to find the nearest `pyproject.toml`, activate its venv, and set this
venv to be the "active project" within this repo. This means that any new shell created within the repo
will automatically activate that project's venv.

The venv is created if it doesn't exist.

If the 'refresh' option is given, the venv will be recreated regardless.

NB: the directory holding the venv (i.e. the python libs and binaries) will be in the same directory
as the `pyproject.toml`, under `.venv/`.

#### `venv off`
Deactivate the current venv if there is one, and set the "active project" to None. New shells will not be
in a venv.

#### `venv destroy`
Same as `venv off` except the `.venv/` directory will also be deleted.

#### `venv go PROJECT`
A `PROJECT` is one of the Poetry projects (e.g. 'atlas', 'aws-pruner', 'dpp-utils', ...)

This will change directory to that project, and activate a venv there.

Autocomplete on PROJECT is supported.


### Convenience shortcuts
These shortcuts help to quickly navigate directories within a repo

#### `cdd PROJECT`
cd to `PROJECT` (as described above). The venv is _not_ changed.

Autocomplete on `PROJECT` is supported.

#### `cdtop`
cd to `$REPO_TOP/`

#### `cdlibs`
cd to `$REPO_TOP/libs`

#### `cdapps`
cd to `$REPO_TOP/apps`

#### `cdat`
cd to `$REPO_TOP/apps/atlas/atlas`

#### `cdpylibs`
cd to the current venvs's directory of installed packages. This is useful for inspecting the source code of
any installed libs.

#### `cdsup`
cd to `/apps/support-toolkit` and activate the venv there. This is where much of the CLI tool running is done from.
