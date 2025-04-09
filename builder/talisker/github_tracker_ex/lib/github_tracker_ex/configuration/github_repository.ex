defmodule GithubTrackerEx.Configuration.GithubRepository do
  # tracking_type can be `new_branch`, `new_pull`, `new_tag`

  defstruct [
    :tracking_type,
    :tracking_matcher,
    :repository_owner,
    :repository_name,
    :client,
    :tables_auto_save,
    :polling_interval,
    :github_token
  ]
end
