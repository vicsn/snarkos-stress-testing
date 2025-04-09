defmodule Talisker.MixProject do
  use Mix.Project

  def project do
    [
      app: :talisker,
      version: "0.4.4",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :github_tracker_ex],
      mod: {Talisker.Application, []}
    ]
  end

  defp deps do
    [
      {:git_cli, "~> 0.3"},
      {:muontrap, "~> 1.0"},
      {:pubsub, "~> 1.0"},
      {:ex_aws, "~> 2.0"},
      {:ex_aws_s3, "~> 2.0"},
      {:hackney, "~> 1.9"},
      {:sweet_xml, "~> 0.6"},
      {:jason, "~> 1.1"},
      {:github_tracker_ex, path: "../github_tracker_ex"},
      {:websockex, github: "Raphexion/websockex"},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end
end
