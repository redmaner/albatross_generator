defmodule Albagen.MixProject do
  use Mix.Project

  def project do
    [
      app: :albagen,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Albagen.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nimiqex, git: "https://github.com/redmaner/nimiqex.git", tag: "0.1.0"},
      {:sqlitex, "~> 1.7"},
      {:hexate, "~> 0.6.1"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
