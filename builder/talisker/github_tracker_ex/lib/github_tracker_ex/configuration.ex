defmodule GithubTrackerEx.Configuration do

  def repositories do
    repositories = Application.get_env(:github_tracker_ex, :repositories, [])

    __MODULE__.Utils.load_repositories(repositories)
  end
end
