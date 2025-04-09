defmodule Talisker.Ardbeg do
  @moduledoc """
  Context module for Ardbeg, the central information server
  """

  alias Talisker.Ardbeg.Client

  defdelegate update_central(event, data), to: Client
end
