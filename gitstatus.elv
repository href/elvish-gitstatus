use builtin
use file
use str

# the folder where the gitstatusd related data is stored
appdir = ~/.elvish/package-data/gitstatus

# use the same exact calls as gitstatus (despite having the platform module)
arch = (str:to-lower (uname -m))
os = (str:to-lower (uname -s))

# the downloaded binary
binary = $appdir"/gitstatusd-"$os"-"$arch

# separators in the gitstatusd API
rs = (str:from-codepoints 30)
us = (str:from-codepoints 31)

# runtime related data to keep track of the daemon
state = [
    &running=$false
    &stdout=$nil
    &stdin=$nil
]

# configurable arguments to the gitstatusd binary
if (not (has-env GITSTATUS_MAX_NUM_STAGED)) {
    E:GITSTATUS_MAX_NUM_STAGED = "1"
}

if (not (has-env GITSTATUS_MAX_NUM_UNSTAGED)) {
    E:GITSTATUS_MAX_NUM_UNSTAGED = "1"
}

if (not (has-env GITSTATUS_MAX_NUM_UNTRACKED)) {
    E:GITSTATUS_MAX_NUM_UNTRACKED = "1"
}

if (not (has-env GITSTATUS_MAX_NUM_UNTRACKED)) {
    E:GITSTATUS_MAX_NUM_UNTRACKED = "1"
}

if (not (has-env GITSTATUS_MAX_NUM_CONFLICTED)) {
    E:GITSTATUS_MAX_NUM_CONFLICTED = "1"
}

# default version uses an external call to bash
fn get-response {
    read-upto $rs < $state[stdout]
}

# pipes the GET request of the given URL to stdout, using curl or wget
fn http-get [url]{
    if (has-external curl) {
        curl -L -s -f $url
        return
    }

    if (has-external wget) {
        wget -q -O- $url
        return
    }

    fail("found no http client to download gitstatusd with")
}

# not all GitHub releases come with a binary release, so we need to find
# out which releases are available for the current platform
fn latest-version {
    http-get https://raw.githubusercontent.com/romkatv/gitstatus/master/install.info ^
      | grep -i (uname -s) ^
      | grep -i (uname -m) ^
      | head -n 1 ^
      | awk '{print $4}' ^
      | cut -d '"' -f 2
}

# get the download URL for the given version
fn download-url [version]{
    put "https://github.com/romkatv/gitstatus/releases/download/"$version"/gitstatusd-"$os"-"$arch".tar.gz"
}

# returns true if the gitstatusd daemon is running
fn is-running {
    put $state[running]
}

# cross-platform CPU count
fn cpu-count {
    try {
        put (getconf _NPROCESSORS_ONLN)
    } except {
        put (str:split ": " (sysctl hw.ncpu)) | drop 1
    }
}

# returns the number of threads gitstatusd should use
fn thread-count {
    cpus = (cpu-count)

    # see https://github.com/romkatv/gitstatus/issues/34
    # would be better, but there doesn't seem
    # to be a min function in Elvish at this point
    if (< $cpus 16) {
        put (* $cpus 2)
    } else {
        put 32
    }
}

# stops the gitstatusd daemon
fn stop {
    if (not is-running) {
        fail "gitstatusd is already stopped"
    }

    # closing the pipes stops the process
    for k [stdin stdout] {
        file:close $state[$k][r]
        file:close $state[$k][w]
        state[$k] = $nil
    }

    state[running] = $false
}

# installs the given version
fn install [version]{

    if (is-running) {
        stop
    }

    mkdir -p $appdir
    http-get (download-url $version) | tar -x -z -C $appdir -f -
    chmod 0700 $binary
}

# installs the gitstatusd binary and creates the necessary paths, if necessary
# does nothing if gitstatusd is in PATH
fn ensure-installed {
    if (has-external gitstatusd) {
        return  # already in PATH, lets use that
    }

    if (not ?(test -e $binary)) {
        install (latest-version)
    }
}

# updates gitstatusd to the latest release (keep the old version)
fn update {
    rm $binary
    ensure-installed
}

# starts the gitstatusd daemon in the background
fn start {
    if (is-running) {
        fail "gitstatusd is already running"
    } else {
        ensure-installed
    }

    for k [stdin stdout] {
        state[$k] = (file:pipe)
    }

    if (has-external gitstatusd) {
        # use from PATH
        binary = gitstatusd
    }

    (external $binary) ^
        --num-threads=(thread-count) ^
        --max-num-staged=$E:GITSTATUS_MAX_NUM_STAGED ^
        --max-num-unstaged=$E:GITSTATUS_MAX_NUM_UNSTAGED ^
        --max-num-untracked=$E:GITSTATUS_MAX_NUM_UNTRACKED ^
        --max-num-conflicted=$E:GITSTATUS_MAX_NUM_CONFLICTED ^
        < $state[stdin] ^
        > $state[stdout] ^
        2> /dev/null &

    state[running] = $true
}

# parses the raw gitstatusd response
fn parse-response [response]{
    @output = (str:split "\x1f" $response)

    result = [
        &is-repository=(eq $output[1] 1)
        &workdir=$nil
        &commit=$nil
        &local-branch=$nil
        &upstream-branch=$nil
        &remote-name=$nil
        &remote-url=$nil
        &action=$nil
        &index-size=$nil
        &staged=$nil
        &unstaged=$nil
        &untracked=$nil
        &conflicted=$nil
        &commits-ahead=$nil
        &commits-behind=$nil
        &stashes=$nil
        &tag=$nil
    ]

    if (bool $result[is-repository]) {
        result[workdir] = $output[2]
        result[commit] = $output[3]
        result[local-branch] = $output[4]
        result[remote-branch] = $output[5]
        result[remote-name] = $output[6]
        result[remote-url] = $output[7]
        result[action] = $output[8]
        result[index-size] = $output[9]
        result[staged] = $output[10]
        result[unstaged] = $output[11]
        result[conflicted] = $output[12]
        result[untracked] = $output[13]
        result[commits-ahead] = $output[14]
        result[commits-behind] = $output[15]
        result[stashes] = $output[16]
        result[tag] = $output[17]
    }

    put $result
}

# runs the query against the given path and returns the result in a map
fn query [repository]{
    if (not (is-running)) {
        start
    }

    echo $us$repository$rs > $state[stdin]
    put (parse-response (get-response))
}
