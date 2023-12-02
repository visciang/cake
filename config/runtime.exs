import Config

log_level = System.get_env("LOG_LEVEL", "notice") |> String.to_existing_atom()

config :logger, :default_handler, level: log_level

config :logger, :default_formatter,
  format: "[$level] $metadata- $message\n",
  metadata: [:mfa, :pipeline]
