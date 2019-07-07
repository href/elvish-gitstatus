# Gitstatus for Elvish Shell

**[Gitstatus](https://github.com/romkatv/gitstatus)** is a 10x faster
alternative to git status and git describe. Its primary use case is to enable
fast git prompt in interactive shells.

**[Elvish](https://elv.sh)** is a friendly interactive shell and an expressive
programming language. It runs on Linux, BSDs, macOS and Windows.

This Elvish package automatically installs, runs and queries gitstatus and
returns the result in a [Map](https://elv.sh/ref/language.html#map):

```shell
$ pprint (gitstatus:query $pwd)
[
 &stashes=  0
 &unstaged= 0
 &commits-ahead=    0
 &tag=  ''
 &action=   ''
 &index-size=   0
 &untracked=    1
 &conflicted=   1
 &workdir=  /Users/denis/Documents/Code/elvish-gitstatus
 &local-branch= master
 &remote-branch=    ''
 &commit=   ''
 &is-repository=    $true
 &remote-url=   ''
 &upstream-branch=  $nil
 &commits-behind=   0
 &staged=   0
 &remote-name=  ''
]
```

The resulting map can then be used to change the prompt. For example:

```shell
edit:prompt = {
    git = (gitstatus:query $pwd)

    if (bool $git[is-repository]) {

        # show the branch, or current commit if not on a branch
        branch = ''
        if (eq $git[local-branch] "") {
            branch = $git[commit][:8]
        } else {
            branch = $git[local-branch]
        }

        put '|'
        put (styled $branch red)

        # show a state indicator
        if (or (> $git[unstaged] 0) (> $git[untracked] 0)) {
            put (styled '*' yellow)
        } elif (> $git[staged] 0) {
            put (styled '*' green)
        } elif (> $git[commits-ahead] 0) {
            put (styled '^' yellow)
        } elif (> $git[commits-behind] 0) {
            put (styled '⌄' yellow)
        }

    }
}
```

## Installation

Using the [Elvish package manager](https://elv.sh/ref/epm.html):

```shell
use epm
epm:install github.com/href/elvish-gitstatus
```

## Usage

To query a folder:

```shell
use github.com/href/elvish-gitstatus/gitstatus
gitstatus:query /foo/bar
```

To query the current folder:

```shell
gitstatus:query $pwd
```

To update gitstatus:

```shell
gitstatus:update
```

## Notes

Gitstatus is run in the background as a separate process. The binaries are
automatically downloaded from the gitstatus repository and run once per shell
process (no sharing between shell processes).

Processes should use fairly small amounts of memory (<2MiB on my system).

I have not yet tested this outside of my Macbook and I use the latest commit
of Elvish. So your mileage my vary on other systems (issues and PRs welcome).

Gitstatus needs to store a binary locally. This is currently done at the
following folder:

~/.elvish/package-data/gitstatus

This means that you might need to update the .gitignore file of your dotfiles
if you check them into git.

## Fields

```
result = gitstatus:query /foo/bar
```

**`result[is-repository]`**

`$true` if the given folder is part of a git repository. Note that all other
fields are set to `$nil` if the given folder is not part of a git repository.

**`result[workdir]`**

The root folder of the git repository.

**`result[commit]`**

The commit hash of the current commit.

**`result[local-branch]`**

The name of the local branch.

**`result[upstream-branch]`**

The name of the upstream branch.

**`result[remote-name]`**

The name of the remote.

**`result[remote-url]`**

The URL of the remote.

**`result[action]`**

The current repository state or active action (e.g. "rebase").

**`result[index-size]`**

The number of files in the index.

**`result[staged]`**

The number of staged files.
Limited to 1 by default (see configuration section).

**`result[unstaged]`**

The number of unstaged files.
Limited to 1 by default (see configuration section).

**`result[conflicted]`**

The number of conflicted files.
Limited to 1 by default (see configuration section).

**`result[untracked]`**

The number of untracked files.
Limited to 1 by default (see configuration section).

**`result[commits-ahead]`**

The number of commits ahead of the remote.

**`result[commits-behind]`**

The number of commits behind the remote.

**`result[stashes]`**

The number of stashes.

**`result[tag]`**

The current tag.

## Configuration

Configuration can be done via environment variables. It should be done before
querying gitstatus via `gitstatus:query`. If done later, the daemon has to
be restarted using `gitstatus:stop` and `gitstatus:start`.

### Max Staged, Unstaged, Untracked

By default, gitstatus limits the number of staged, unstaged and untracked files
that it enumerates. So those values are either set to 1 or to 0. This is of
course faster than providing an accurate count.

If you need to know the exact number of files (or of there are one or many),
then you should set the configuration as follows (here with the example value
of 10):

```
use gitstatus

$E:GITSTATUS_MAX_NUM_STAGED = "10"
$E:GITSTATUS_MAX_NUM_UNSTAGED = "10"
$E:GITSTATUS_MAX_NUM_UNTRACKED = "10"
$E:GITSTATUS_MAX_NUM_CONFLICTED = "10"
```

If you want an accurate count use "-1", disabling the limit.
