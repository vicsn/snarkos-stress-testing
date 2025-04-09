defmodule GithubTrackerEx do
  @moduledoc """
  Documentation for `GithubTrackerEx`.
  """

  @supported_update_types [:new_branch]

  def subscribe(update_type, repository) do
    subscribe(self(), update_type, repository)
  end

  def subscribe(pid, update_type, {:github_path, path}) when is_binary(path) do
    url = "https://github.com/#{path}"

    subscribe(pid, update_type, url)
  end

  def subscribe(pid, update_type, url)
      when is_pid(pid) and update_type in @supported_update_types and is_binary(url) do
    PubSub.subscribe(pid, {update_type, url})
  end
end
