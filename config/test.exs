#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

# mix.config to be used with automated tests ONLY
# i.e. MIX_ENV=test mix test

import Config

config :lager,
  handlers: [
    level: :debug
  ]
  config :logger,backends: [:console]
  config :DV,enable_http: true
  config :DV,api_http_port: String.to_integer(System.get_env("DV_PORT","4111"))
  config :DV,enable_https: false
  config :DV,metadata_base_dir: System.get_env("DV_METADATA_DIR","/var/tmp/test_metadata") # Any existing CubDB tables in this folder will be purged
  config :DV,initial_admins: [{:user,:ldap,"test_user"}] # test_user is required
