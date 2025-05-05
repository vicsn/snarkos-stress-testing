defmodule Talisker.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @main_observability_runner_configuration Application.compile_env(
                                             :talisker,
                                             :main_observability_runner_configuration,
                                             %{
                                               name: :main_observability_runner,
                                               tests_script: "auto_run_test_suite.sh"
                                             }
                                           )

  @impl true
  def start(_type, _args) do
    pre_release_snark_os_repo_config = %{
      name: :pre_release_snark_os_builder,
      github_path: "ProvableHQ/snarkOS",
      branch_filter: fn branch_name -> String.starts_with?(branch_name, "prerelease") end,
      tests_to_run: ~w(
        add_deployments reset_client_ledgers reset_validator_ledgers swap_ledgers halt_byzantine_majority halt_byzantine_minority
      )
    }

    release_snark_os_repo_config = %{
      name: :release_snark_os_builder,
      github_path: "ProvableHQ/snarkOS",
      branch_filter: fn branch_name -> not String.starts_with?(branch_name, "prerelease") end,
      tests_to_run: ~w(halt_byzantine_minority)
    }

    konstantin_snark_os_repo_config = %{
      name: :konstantin_snark_os_builder,
      github_path: "kpandl/snarkOS",
      tests_to_run: ~w(
        add_deployments reset_client_ledgers reset_validator_ledgers swap_ledgers halt_byzantine_majority halt_byzantine_minority
      )
    }

    staging_snark_os_repo_config = %{
      github_token: System.get_env("STAGING_REPO_TOKEN"),
      name: :staging_snark_os_builder,
      github_path: "ProvableHQ/snarkOS-staging",
      branch_filter: fn branch_name -> String.starts_with?(branch_name, "prerelease") end,
      tests_to_run: ~w(
        add_deployments reset_client_ledgers reset_validator_ledgers swap_ledgers halt_byzantine_majority halt_byzantine_minority
      )
    }
    IO.inspect(staging_snark_os_repo_config)

    IO.inspect(staging_snark_os_repo_config)

    observability_runner_config = @main_observability_runner_configuration

    children = [
      {Phoenix.PubSub, name: Talisker.PubSub},
      builder_child_spec(release_snark_os_repo_config),
      builder_child_spec(pre_release_snark_os_repo_config),
      builder_child_spec(konstantin_snark_os_repo_config),
      builder_child_spec(staging_snark_os_repo_config),
      {Talisker.Tester.ObservabilityRunner, observability_runner_config},
      Talisker.Ardbeg.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Talisker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def main_observability_runner_configuration, do: @main_observability_runner_configuration

  defp builder_child_spec(configuration) do
    Supervisor.child_spec({Talisker.Builder.Worker, configuration}, id: configuration.name)
  end
end
