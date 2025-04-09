defmodule Talisker do
  @moduledoc """
  Documentation for `Talisker`.
  """

  def trigger_test_run(label, tests \\ "all") do
    Phoenix.PubSub.broadcast(Talisker.PubSub, "testers", {:run, tests, label})
  end

  def trigger_build(hash, builder \\ :pre_release_snark_os_builder) do
    builder
    |> Process.whereis()
    |> send({:new_branch, %{ref_name: hash, ref_hash: hash, settings: %{should_run_tests: false, force: true}}})
  end

  def trigger_build_and_test_run(hash, builder \\ :pre_release_snark_os_builder) do
    builder
    |> Process.whereis()
    |> send({:new_branch, %{ref_name: hash, ref_hash: hash, settings: %{force: true}}})
  end
end
