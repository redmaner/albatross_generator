import Config

config :albagen,
  sqlite_path: System.get_env("SQLITE_PATH", "~/albagen.sqlite"),
  albatross_nodes:
    System.get_env(
      "ALBATROSS_NODES",
      "http://seed1.nimiq.local:8648,http://seed2.nimiq.local:8648,http://seed3.nimiq.local:8648,http://seed4.nimiq.local:8648"
    )
    |> String.split(",", trim: true),
  seed_wallet_address:
    System.get_env("SEED_WALLET_ADDRESS", "NQ87 HKRC JYGR PJN5 KQYQ 5TM1 26XX 7TNG YT27"),
  seed_wallet_key:
    System.get_env(
      "SEED_WALLET_PRIVATE_KEY",
      "3336f25f5b4272a280c8eb8c1288b39bd064dfb32ebc799459f707a0e88c4e5f"
    ),
  new_account_min_nim: System.get_env("NEW_ACCOUNT_MIN_NIM", "100") |> String.to_integer(),
  new_account_max_nim: System.get_env("NEW_ACCOUNT_MAX_NIM", "1000") |> String.to_integer(),
  stakers_to_create: System.get_env("STAKERS_TO_CREATE", "1000") |> String.to_integer(),
  timer_cap_in_secs:
    System.get_env("TIMER_CAP_IN_SECS", "90")
    |> String.to_integer()
    |> :timer.seconds()
