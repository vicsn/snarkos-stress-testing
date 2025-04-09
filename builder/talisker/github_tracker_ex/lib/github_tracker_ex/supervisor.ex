defmodule GithubTrackerEx.Supervisor do
  use Supervisor

  alias GithubTrackerEx.Configuration.GithubRepository

  def start_link(_) do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    children =
      GithubTrackerEx.Configuration.repositories()
      |> Enum.map(fn
        %GithubRepository{tracking_type: tracking_type} = repository
        when tracking_type in [:new_branch, :new_tag] ->
          id = String.to_atom("#{tracking_type}_#{repository.repository_owner}_#{repository.repository_name}")

          Supervisor.child_spec({GithubTrackerEx.BranchPoller, repository}, id: id)
      end)

    opts = [strategy: :one_for_one]

    Supervisor.init(children, opts)
  end
end
