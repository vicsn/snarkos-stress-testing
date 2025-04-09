defmodule Talisker.Ardbeg.Supervisor do
  @moduledoc """
  Supervisor for the Ardbeg module
  """
  use Supervisor

  require Logger

  def start_link(opts \\ :ok) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:talisker, __MODULE__) |> Map.new()

    if config.enabled do
      Logger.info("Ardbeg module enabled")
      do_init(opts, config)
    else
      Logger.warning("Ardbeg module disabled")
      :ignore
    end
  end

  defp do_init(_opts, _config) do
    children = [
      Talisker.Ardbeg.Client
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
