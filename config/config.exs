import Config

config :logger, :console,
  format: "[$date] [$time] [$level] $metadata | $message\n",
  metadata: [:pid, :address, :seed]
