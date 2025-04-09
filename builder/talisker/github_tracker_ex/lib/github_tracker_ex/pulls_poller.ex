defmodule GithubTrackerEx.PullPoller do
  use GenServer

  defstruct [:table, :configuration]

  def start_link(configuration) do
    GenServer.start_link(__MODULE__, configuration, name: __MODULE__)
  end

  @impl true
  def init(configuration) do
    {:ok, %__MODULE__{configuration: configuration}, {:continue, :setup_table}}
  end

  @impl true
  def handle_continue(:setup_table, %__MODULE__{configuration: configuration} = state) do
    table_name = :"pulls_#{configuration.repository_owner}_#{configuration.repository_name}"

    {:ok, table} =
      :dets.open_file(table_name,
        access: :read_write,
        auto_save: configuration.tables_auto_save,
        max_no_slots: 256
      )

    :ets.new(table, [:named_table])
    table = :dets.to_ets(table, table)

    send(self(), :poll)

    {:noreply, %__MODULE__{state | table: table}}
  end

  @impl true
  def handle_info(:poll, %__MODULE__{configuration: configuration, table: table} = state) do
    Tentacat.Pulls.filter(
      configuration.client,
      configuration.repository_owner,
      configuration.repository_name,
      %{state: "open"}
    )
    |> case do
      {200, pulls, _} ->
        IO.puts("----")

        IO.inspect(pulls)

        updates =
          pulls
          |> Enum.map(fn %{
                           "title" => title,
                           "user" => %{"login" => user},
                           "url" => url,
                           "updated_at" => updated_at
                         } ->
            is_new = :ets.insert_new(table, [{url, title, user, updated_at}])

            if is_new do
              # TODO Here we notify our listeners:
              IO.puts("Update!")
            else
              # We already have this PR, but we should check if it is updated:
              :todo
            end

            IO.puts("'#{title}' by #{user}, url: #{url}, updated_at: #{updated_at}")

            updated = is_new

            updated
          end)

        if Enum.any?(updates, fn updated -> updated end) do
          :ok = :dets.from_ets(table, table)
        end

        IO.puts("----")

      x ->
        # TODO handle repo access error!
        IO.inspect(x)
        :noop
    end

    poll_after_interval(configuration.polling_interval)

    {:noreply, state}
  end

  defp poll_after_interval(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
