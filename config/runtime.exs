import Config

config :logger, :default_handler, level: System.get_env("LOG_LEVEL", "notice") |> String.to_existing_atom()

config :logger, :default_formatter,
  format: "[$level] $metadata- $message\n",
  metadata: [:mfa, :pipeline]
