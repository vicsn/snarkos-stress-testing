# Talisker

Talisker is responsible to build SnarkOS instances (in the future also other binaries) and to run stress tests.
It is a modular service, very flexible and extensible, so new type of test runners can be added in the future too.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `talisker` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:talisker, "~> 0.4.0"}
  ]
end
```

## How to compile

1. [Install Elixir](https://elixir-lang.org/install.html).
2. Be sure you are compiling for the right OS; For example compile on Ubuntu 22 if the target is Ubuntu 22 (Docker can be used, btw).
3. Navigate to the folder containing this readme and run `MIX_ENV=prod mix release`.
4. Tar the release with `tar -czvf talisker.tar.gz -C _build/prod/rel talisker`.

With Docker it can be done by just pulling [this image](https://hub.docker.com/_/elixir) and mounting the talisker source into it, logging into it and doing the steps 3 and 4.

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/talisker>.

## Version History

### 4.0.3

* Fix a bug with failing tests and their uploads.
* Add better logging.

### 4.0.2

* Fix a bug that was preventing the log files to be uploaded sometimes.

### 4.0.1

* Filter out "ERROR request{method=GET" as they are not real errors.

### 4.0.0

* Make Talisker's hard-coded locations to be in the Provable region. Can be made configurable in the Rust version.

### 0.3.1

* Make test results and releases buckets configurable through system vars.

### 0.3.0

* New file structure. Now for a specific git hash everything is structured in one folder.
* Better human-readable time stamps.
* Logs with errors are now marked with `_ERROR` in the file name.
* A prometheus snapshot is now being downloaded and uploaded to the results. It can be used to start local prometheus.

### 0.2.1

* Added an additional filter to the `Talisker.Builder.Worker`, so we can have multiple for the same repository.
* The builders are now 2 : One for building pre-releases (runs more tests) and one for building releases.
* Now every builder can be configured with a list of tests to run.
* Better logging for `Talisker.Builder.Worker`.
* Multiple source repositories can be configured now. Added one for development.
* Added the staging repository for SnarkOS and Konstantin's test repo

### 0.2.0

* Can build multiple versions of SnarkOS and put them on a configured S3 bucket under their git hashes (as folders).
* Can run tests using a specific tag that was already built. That way tests can be ran for older versions too.
* A built is reused if already has been built.
* Supports working with the new `ProvableHQ/stress-testing` repository.
* Stores the test run results by git hash and not tag/branch name.

### 0.1.0

* Can build a single current SnarkOS binary and put it on a configured S3 bucket.
* Can run the ProvableHQ stress tests using that stored version.
* Can output the results/logs of the test runs into a configured bucket.
* Can recover from a failure and continue running its tests.
* Can detect test failures and mark the results/logs as such.
* Can detect a new tag/branch named as a release and automatically run a build and then tests.
