defmodule RcCarAtomvm.MixProject do
  use Mix.Project

  def project do
    [
      app: :rc_car_atomvm,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: false,
      deps: deps(),
      atomvm: [start: RcCarAtomvm]
    ]
  end

  def application do
    [
      extra_applications: [:crypto, :logger, :ssl]
    ]
  end

  defp deps do
    [
      {:exatomvm, github: "atomvm/exatomvm", runtime: false},
      {:atomvm, "~> 0.7.0-beta.0", runtime: false},
      {:pythonx, "~> 0.4", runtime: false},
      {:req, "~> 0.5", runtime: false}
    ]
  end
end
