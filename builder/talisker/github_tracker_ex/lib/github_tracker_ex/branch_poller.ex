defmodule GithubTrackerEx.BranchPoller do
  use GenServer

  require Logger

  alias GithubTrackerEx.Configuration.GithubRepository

  defstruct [:table, :configuration, :repo]

  def start_link(%GithubRepository{} = configuration) do
    GenServer.start_link(__MODULE__, configuration)
  end

  @impl true
  def init(%GithubRepository{} = configuration) do
    {:ok, %__MODULE__{configuration: configuration}, {:continue, :setup_table}}
  end

  @impl true
  def handle_continue(:setup_table, %__MODULE__{configuration: configuration} = state) do
    table_name =
      :"#{configuration.tracking_type}_#{configuration.repository_owner}_#{configuration.repository_name}"

    {:ok, table} =
      :dets.open_file(table_name,
        access: :read_write,
        auto_save: configuration.tables_auto_save,
        max_no_slots: 256
      )

    :ets.new(table, [:named_table])
    table = :dets.to_ets(table, table)

    local_path = "#{configuration.repository_owner}_#{configuration.repository_name}"

    repo_prefix =
      if configuration.github_token == :public do
        ""
      else
        "#{configuration.github_token}@"
      end

    repo_url = "https://#{repo_prefix}github.com/#{configuration.repository_owner}/#{configuration.repository_name}"
    repo =
      case Git.clone([repo_url, local_path]) do
        {:ok, repo} ->
          repo

        {:error, %Git.Error{code: 128}} ->
          Git.new(local_path)
      end

    send(self(), :poll)

    {:noreply, %__MODULE__{state | table: table, repo: repo}}
  end

  @impl true
  def handle_info(:poll, %__MODULE__{configuration: configuration} = state) do
    repo_string = "#{configuration.repository_owner}/#{configuration.repository_name}"

    Logger.info(
      "[GithubTrackerEx.BranchPoller #{repo_string}] Polling #{configuration.repository_name}"
    )

    local_path = "#{configuration.repository_owner}_#{configuration.repository_name}"

    case check_and_get_updates(state) do
      :no_updates ->
        :noop

      {:updates, updates} ->
        url = "https://github.com/#{repo_string}"

        repo = Git.new(local_path)

        Enum.each(updates, fn update ->
          update_hash =
            case Git.rev_parse(repo, update) do
              {:ok, rev} ->
                String.trim(rev)

              {:error, _error} ->
                {:ok, rev} = Git.rev_parse(repo, "remotes/origin/#{update}")
                String.trim(rev)
            end

          update = %{
            ref_name: update,
            ref_hash: update_hash
          }

          Logger.info("New branch or tag detected: #{inspect(update)}")

          PubSub.publish({:new_branch, url}, {:new_branch, update})
        end)
    end

    poll_after_interval(configuration.polling_interval)

    {:noreply, state}
  end

  defp poll_after_interval(interval) do
    Process.send_after(self(), :poll, interval)
  end

  defp check_and_get_updates(%__MODULE__{configuration: configuration, repo: repo, table: table}) do
    case Git.fetch(repo) do
      {:error, error} ->
        Logger.error(inspect(error))
        :no_updates

      {:ok, ""} ->
        {:ok, branches_string} = Git.branch(repo, "--all")
        {:ok, tags_string} = Git.tag(repo)

        branches_string = "#{branches_string}\n#{tags_string}"

        branches =
          branches_string
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim_leading(&1, "*"))
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&String.contains?(&1, " -> "))
          |> Enum.uniq()

        Enum.each(branches, fn branch ->
          is_new = :ets.insert_new(table, [{branch}])

          if is_new && configuration.tracking_matcher.(branch) do
            case Git.rev_parse(repo, branch) do
              {:ok, rev} ->
                rev = String.trim(rev)
                branch = String.replace(branch, "remotes/origin/", "")

                Logger.debug("New matching branch: #{branch}, revision: #{rev}")

              {:error, error} ->
                Logger.error("Branch with no revision: #{branch}, error: #{inspect(error)}")
            end
          end
        end)

        :no_updates

      {:ok, _} ->
        {:ok, branches_string} = Git.branch(repo, "--all")
        {:ok, tags_string} = Git.tag(repo)

        branches_string = "#{branches_string}\n#{tags_string}"

        updates =
          branches_string
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim_leading(&1, "*"))
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&String.contains?(&1, " -> "))
          |> Enum.map(&String.replace(&1, "remotes/origin/", ""))
          |> Enum.uniq()
          |> Enum.filter(fn branch ->
            is_new = :ets.insert_new(table, [{branch}])
            is_new && configuration.tracking_matcher.(branch)
          end)

        if updates != [] do
          :ok = :dets.from_ets(table, table)
        end

        {:updates, updates}
    end
  end
end
