defmodule GithubTrackerEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :github_tracker_ex,
      version: "0.1.1",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GithubTrackerEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:git_cli, "~> 0.3"},
      {:pubsub, "~> 1.0"},
      {:tentacat, "~> 2.4"}
    ]
  end
end
