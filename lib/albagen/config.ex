defmodule Albagen.Config do

  @max_concurrency max(8, System.schedulers_online())

  def sqlite_path, do: System.get_env("SQLITE_PATH", "~/albagen.sqlite")

  def albatross_nodes,
    do:
      System.get_env(
        "ALBATROSS_NODES",
        "http://seed1.nimiq.local:8648,http://seed2.nimiq.local:8648,http://seed3.nimiq.local:8648,http://seed4.nimiq.local:8648"
      )
      |> String.split(",", trim: true)

  def seed_wallet_addres,
    do: System.get_env("SEED_WALLET_ADDRESS", "NQ87 HKRC JYGR PJN5 KQYQ 5TM1 26XX 7TNG YT27")

  def seed_wallet_key,
    do:
      System.get_env(
        "SEED_WALLET_PRIVATE_KEY",
        "3336f25f5b4272a280c8eb8c1288b39bd064dfb32ebc799459f707a0e88c4e5f"
      )

  def max_concurrency, do: System.get_env("MAX_CONCURRENCY", "#{@max_concurrency}") |> String.to_integer()
end
