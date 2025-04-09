defmodule Talisker.Ardbeg.InterCom do
  @moduledoc """
  Module to abstract away communication
  """
  require Logger

  alias Phoenix.PubSub

  @broker Talisker.PubSub
  @topic "ardbeg"

  def publish(%{"event" => _, "payload" => _} = data) do
    :ok = PubSub.broadcast(@broker, @topic, data)
  end

  def subscribe do
    :ok = PubSub.subscribe(@broker, @topic)
  end
end
