use str

# the folder where the gitstatusd related data is stored
appdir = ~/.elvish/package-data/gitstatus

# the downloaded binary
binary = $appdir/gitstatusd

# runtime related data to keep track of the daemon
state = [
    &running=$false
    &stdout=$nil
    &stdin=$nil
]

# gets the os for the download link
fn os {
    name = (uname -s)

    if (eq $name "Linux") {
        if (eq (uname -o) "Android") {
            put "Android"
            return
        }
    }

    put $name
}

# gets the arch for the download link
fn arch {
    uname -m
}

# returns the download URL of the architecture specific gitstatusd build
fn download-url {
    base = 'https://github.com/romkatv/gitstatus/raw/master/bin/gitstatusd'
    echo (str:to-lower $base"-"(os)"-"(arch))
}

# downloads the required gitstatusd build
fn download {
    if (has-external curl) {
        curl -L -s (download-url) > $binary
    } elif (has-external wget) {
        wget -O $binary (download-url)
    } else {
        fail("found no http client to download gitstatusd with")
    }
}

# installs the gitstatusd binary and creates the necessary paths, if necessary
fn ensure-installed {
    mkdir -p $appdir

    if (not (has-external $binary)) {
        download
        chmod 0700 $binary
    }
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
        put (splits ": " (sysctl hw.ncpu)) | drop 1
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
        prclose $state[$k]
        pwclose $state[$k]
        state[$k] = $nil
    }

    state[running] = $false
}

# updates gitstatusd to the latest release
fn update {
    if (is-running) {
        stop
    }

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
        state[$k] = (pipe)
    }

    (external $binary) \
        --num-threads=(thread-count) \
        < $state[stdin] \
        > $state[stdout] \
        2> /dev/null &

    state[running] = $true
}

# parses the raw gitstatusd response
fn parse-response [response]{
    @output = (splits "\x1f" $response)

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
        result[untracked] = $output[12]
        result[commits-ahead] = $output[13]
        result[commits-behind] = $output[14]
        result[stashes] = $output[15]
        result[tag] = $output[16]
    }

    put $result
}

# runs the query against the given path and returns the result in a map
fn query [repository]{
    if (not (is-running)) {
        start
    }

    echo "\x1f"$repository"\x1e" > $state[stdin]

    # XXX replace this with something elvish!
    response = (sh -c 'read -rd $''\x1e'' && echo $REPLY' < $state[stdout])

    put (parse-response $response)
}
