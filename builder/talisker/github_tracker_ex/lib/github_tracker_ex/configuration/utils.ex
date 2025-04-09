defmodule GithubTrackerEx.Configuration.Utils do
  @moduledoc """
  An util (or helper module), used to initialize the `GithubTrackerEx.Configuration`.

  Its idea is to provide functions to be called compile time to build the `GithubTrackerEx.Configuration` module
  with the right configuration data.
  """

  alias GithubTrackerEx.Configuration.GithubRepository

  @default_tables_auto_save :timer.seconds(40)
  @default_polling_interval :timer.seconds(30)

  def load_repositories(repository_definitions) do
    repository_definitions
    |> Enum.flat_map(fn repository_definition ->
      load_repository_definition(repository_definition)
    end)
  end

  defp load_repository_definition(%{github_path: github_path} = repository_definition) do
    github_path
    |> String.split("/", trim: true)
    |> case do
      [owner, name] ->
        repository_definition
        |> Map.get(:tracking, [])
        |> Enum.map(fn tracking_definition ->
          tracking_type = Map.get(tracking_definition, :type, :new_branch)
          tracking_matcher = Map.get(tracking_definition, :matcher, fn _ -> true end)

          tracking_matcher =
            case tracking_matcher do
              list when is_list(list) ->
                fn to_be_matched ->
                  case Enum.find(list, fn reg -> Regex.match?(reg, to_be_matched) end) do
                    nil -> false
                    _ -> true
                  end
                end

              fun when is_function(fun, 1) ->
                fun
            end

          %GithubRepository{
            github_token: Map.get(tracking_definition, :token, :public),
            tracking_type: tracking_type,
            tracking_matcher: tracking_matcher,
            repository_owner: owner,
            repository_name: name,
            tables_auto_save:
              Map.get(tracking_definition, :tables_auto_save, @default_tables_auto_save),
            polling_interval:
              Map.get(tracking_definition, :polling_interval, @default_polling_interval)
          }
        end)

      _ ->
        exit(
          "Bad configuration, Github Repository path should be configured as 'owner/repository_name'!"
        )
    end
  end
end
