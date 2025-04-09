# GithubTrackerEx

Application that can track and react to changes in Git repositories.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `github_tracker_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:github_tracker_ex, "~> 0.1.0"}
  ]
end
```

## Version History

### 0.1.1

* Added some fixes to support tracking of multiple repositories at the same time.

### 0.1.0

* The initial version can track new branches and tags and can filter them with a regex
* There is work of progress GitHub pull request  tracker.
