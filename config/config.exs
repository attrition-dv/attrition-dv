#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

import Config

config :lager,
  handle_otp_reports: false, # https://github.com/erlang-lager/lager/issues/507#issuecomment-570378407j
  error_logger_redirect: false, # https://stackoverflow.com/revisions/61890551/1
  handlers: [
    level: :info
  ]

config :logger,
backends: [:console]

# CORS settings - See `CorsPlug` documentation
config :cors_plug,origin: "http://localhost"

config :DV,
  # Directory to store flat file metadata - this folder is where all platform data will be stored
  #   Only change this for new setups, or AFTER migrating data to a new location
  #   Must be an existing folder that the identity running the platform has full ownership of, and be chmoded at least 700 (recommended 700 or 755)
  metadata_base_dir: "/var/tmp/dv_metadata_store",

  # Initial admins - this is only used on startup, and only if BOTH ACL sets are empty
  # This will create appropriate ACL entries granting the entities listed FULL access to the API
  # Accepts {:user,:ldap,username} or {:group,:ldap,group_name} entries
  initial_admins: [{:user,:ldap,"win"},{:group,:ldap,"demo_group"}],

  # Enabled data source connectors - safe to add new connectors at any time, do NOT remove any connectors that are in use
  #
  # Format is {class,type,version,{connector_module,constants},function_module}
  #
  # Definitons:
  #
  # class: the class of the data source connector (e.g. :relational,:file,:web_api)  .
  # type: the type of the data source connector, as a string (used when defining data sources).
  # version: the supported version of the underlying data source, as an integer (used when defining data sources), version may be nil for a "failback" data source.
  #   failback data sources will be used if no specific connector exists for a type:version pair provided during data source creation.
  # connector_module: Name of the Connector module for the data source, as an atom.
  # constants (optional): Constants required for connecting to the data source, will be passed to the connect/2 method of the connector_module.
  # function_module: Function support module for the data source, as an atom. ForcePlatformFuncs can be used as a safe default.
  #
  connectors: [
    {:relational,"PostgreSQL",15,{StandardODBCConnector,[driver: "/usr/lib64/psqlodbca.so",
    connection_string: "driver=$driver;server=$hostname;database=$database;uid=$uid;krbsrvname=$spn"]},PostgreSQLFuncs},
    {:relational,"MariaDB",11,{StandardODBCConnector,[driver: "/usr/lib64/mariadb/libmaodbc.so",
      connection_string: "driver=$driver;server=$hostname;database=$database;uid=$uid;krbsrvname=$spn;authentication-kerberos-mode=GSSAPI"]},MariaDBFuncs},
    {:file,"JSON",1,{FileConnector,[result_type: :json]},ForcePlatformFuncs},
    {:file,"CSV",1,{FileConnector,[result_type: :csv]},ForcePlatformFuncs},
    {:web_api,"REST",1,{WebAPIConnector,[result_type: :json]},ForcePlatformFuncs}
  ],

  # Enable HTTP connections
  enable_http: true,
  # API port for HTTP connections
  api_http_port: 4001,
  # Enable HTTPS connections
  # If doing this, :certfile and :keyfile must be set to valid .pem format files. Must be readable by the identity running the platform.
  enable_https: true,
  # API port for HTTP connections
  api_https_port: 4431,
  # Certificate file for https
  https_certfile: "/var/tmp/ssl_cert/localhost.crt",
  # Key file for https
  https_keyfile: "/var/tmp/ssl_cert/localhost.key",

  # LDAP Server hostname
  ldap_server_hostname: "localhost",
  # LDAP Query base
  ldap_query_base: "dc=example,dc=com",
  # Kerberos keytab for the platform server, used for validating INCOMING Kerberos authentication (e.g. those passed via SPNEGO to the platform). Must be readable by the identity running the platform.
  kerberos_server_keytab: "/etc/http_kt",
  # Kerberos keytab for OUTGOING Kerberos authentication. Used for authenticating to all Kerberos data sources. Must be readable by the identity running the platform.
  kerberos_client_keytab: "/etc/test_user_keytab",
  # Kerberos user for OUTGOING Kerberos authentication. Used for authenticating to all Kerberos data sources. Must be readable by the identity running the platform.
  kerberos_client_uid: "test"

  import_config "#{Mix.env}.exs"
