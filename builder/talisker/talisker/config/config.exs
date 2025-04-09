import Config

config :ex_aws,
  region: "ue-central-1",
  json_codec: Jason,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  security_token: [{:system, "AWS_SESSION_TOKEN"}, :instance_role],
  s3: [
    scheme: "https://",
    host: "s3.us-west-2.amazonaws.com",
    region: "us-west-2"
  ]

config :talisker, :ardbeg_hash, :crypto.hash(:sha256, "TEST-SECRET")
config :talisker, :ardbeg_url, "ws://localhost:4000/jar-socket/websocket"

import_config "#{config_env()}.exs"
