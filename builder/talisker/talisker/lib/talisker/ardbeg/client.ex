defmodule Talisker.Ardbeg.Client do
  @moduledoc false
  use WebSockex

  alias Talisker.Ardbeg.InterCom

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:connected?, :ref, :incoming]
  end

  @phx_join Jason.encode!(%{
              topic: "health:lobby",
              event: "phx_join",
              payload: %{},
              ref: "1"
            })

  @phx_join_resp ~s|{"ref":"1"|

  def update_central(client \\ __MODULE__, event, data) when is_map(data) do
    pid =
      if is_pid(client) do
        client
      else
        Process.whereis(client)
      end

    if is_pid(pid) && Process.alive?(pid) do
      send(client, {:update_central, event, data})
    else
      # Ardbeg functionality is turned off, so just return :ok
      :ok
    end
  end

  def start_link(_state \\ %{}) do
    extra_headers = [{"x-auth-token", auth_token()}]

    WebSockex.start_link(
      ardbeg_url(),
      __MODULE__,
      init_state(),
      name: __MODULE__,
      # Avoid blocking the rest of the application
      async: true,
      handle_initial_conn_failure: true,
      extra_headers: extra_headers
    )
  end

  @impl true
  def handle_connect(conn, state) do
    {:ok, binary_frame} = WebSockex.Frame.encode_frame({:text, @phx_join})
    :ok = WebSockex.Conn.socket_send(conn, binary_frame)
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_conn, _state) do
    # If the backend is down, we will take a break before we try again.
    Process.sleep(5000)
    {:reconnect, init_state()}
  end

  @impl true
  def handle_frame({:text, @phx_join_resp <> _}, state) do
    {:ok, %State{state | connected?: true, ref: 2}}
  end

  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"payload" => %{"status" => "error", "response" => %{"reason" => reason}}}} ->
        Logger.error("unable to send message reason=#{reason}")

      {:ok, %{"event" => _, "payload" => _} = data} ->
        InterCom.publish(data)

      {:ok, data} ->
        Logger.warning("received incorrect data from ardbeg data=#{inspect(data)}")

      {:error, reason} ->
        Logger.warning("unable to decode msg=#{inspect(msg)} reason=#{inspect(reason)}")
    end

    {:ok, state}
  end

  @impl true
  def handle_info({:update_central, event, data}, %State{ref: ref} = state) do
    encoded =
      Jason.encode!(%{
        topic: "health:lobby",
        event: event,
        payload: data,
        ref: Integer.to_string(ref)
      })

    {:reply, {:text, encoded}, %State{state | ref: ref + 1}}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.warning("ardbeg client terminated with reason=#{inspect(reason)}")
    {:reconnect, init_state()}
  end

  defp auth_token do
    Application.fetch_env!(:talisker, :ardbeg_hash)
    |> Base.encode64()
  end

  defp ardbeg_url do
    Application.fetch_env!(:talisker, :ardbeg_url)
  end

  defp init_state do
    %State{connected?: false, ref: 1, incoming: []}
  end
end
