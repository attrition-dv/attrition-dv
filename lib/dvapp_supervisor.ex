#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule DVApp.Supervisor do
  @moduledoc """
  Primary supervisor for the platform application. Starts and manages:

    * All `CubDB` instances for `Metadata`
    * `QP` for Query Plan management
    * `QueryHandler` for processing Data Source queries
    * `DV` as the primary entry point for platform tasks
    * `Bandit` for the web-based API connectivity

  """
  use Supervisor
  require Logger
  def start_link(opts) do
    LogUtil.inspect(Supervisor.start_link(__MODULE__,:ok,opts),label: "Supervisor pid")
  end
  @impl true
  def init(:ok) do
    metadata_base_dir = Application.fetch_env!(:DV,:metadata_base_dir)
    children = [
      # Metadata stores, need to start first
      Supervisor.child_spec({CubDB,data_dir: Path.join(metadata_base_dir,"dv_models"),name: :dv_models,auto_file_sync: true},id: :CubDB_dv_models),
      Supervisor.child_spec({CubDB,data_dir: Path.join(metadata_base_dir,"dv_endpoints"),name: :dv_endpoints,auto_file_sync: true},id: :CubDB_dv_endpoints),
      Supervisor.child_spec({CubDB,data_dir: Path.join(metadata_base_dir,"dv_data_sources"),name: :dv_data_sources,auto_file_sync: true},id: :CubDB_dv_data_sources),
      Supervisor.child_spec({CubDB,data_dir: Path.join(metadata_base_dir,"dv_user_acls"),name: :dv_user_acls,auto_file_sync: true},id: :CubDB_dv_user_acls),
      Supervisor.child_spec({CubDB,data_dir: Path.join(metadata_base_dir,"dv_group_acls"),name: :dv_group_acls,auto_file_sync: true},id: :CubDB_dv_group_acls),
      Supervisor.child_spec({CubDB,data_dir: Path.join(metadata_base_dir,"dv_result_sets"),name: :dv_result_sets,auto_file_sync: true},id: :CubDB_dv_result_sets),
      QP, # Query Plan tracker, start before DV
      DV, # Query mediator/generic request handler

  ]
    # API REST/WebSocket endpoints
    api_children = []
    # HTTP
    api_children = if Application.fetch_env!(:DV,:enable_http) do
      [{Bandit,scheme: :http,plug: WebBrokerPlug,port: Application.fetch_env!(:DV,:api_http_port)}|api_children]
    else
      api_children
    end
    # HTTPS
    api_children = if Application.fetch_env!(:DV,:enable_https) do
      [{Bandit,scheme: :https,plug: WebBrokerPlug,port: Application.fetch_env!(:DV,:api_https_port),certfile: Application.fetch_env!(:DV,:https_certfile),keyfile: Application.fetch_env!(:DV,:https_keyfile)}|api_children]
    else
      api_children
    end
    Supervisor.init(children ++ api_children,strategy: :one_for_one)
  end
end
