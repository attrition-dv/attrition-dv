#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule APIV1RESTHandler do
  @moduledoc """
  `Plug.Router` for REST (non-WebSocket) API calls. Wrapper for `APIV1`.

  Supports JSON payloads only. Returns JSON.

  Handles requests sent to /api/v1/`category`/`action`.

  *Part of V1 API*
  """
  use Plug.Router
  use Plug.ErrorHandler # Primarily to handle Unknown Media Hype errors
  plug Plug.Parsers,parsers: [:json],json_decoder: Jason # REST only supports JSON right now

  @impl Plug.ErrorHandler
  def handle_errors(conn,%{kind: _kind,reason: _reason,stack: _stack}) do
    {:error,code,payload} = APIV1.handle(%{"action" => "internal_server_error"},%{},:rest)
    send_resp(conn,code,payload) |> halt()
  end
  # Base handler for API calls using URL parameters obtained from APIV1Router.
  # Returns `200 OK` with the payload response, or the correct response code for the standardized API error.
  defp handle_request(conn,payload) do
    LogUtil.debug("START REST call for payload #{inspect payload}")
    case LogUtil.inspect(APIV1.handle(payload,%{username: conn.assigns[:username]},:rest),label: "APIV1.handle/3 Response") do
      {:ok,{:file,filename}} -> send_file(conn,200,filename,0,:all)
      {:ok,payload} -> send_resp(conn,200,payload)
      {:error,code,payload} -> send_resp(conn,code,payload)
    end |> halt() |> LogUtil.pipe("END REST call for payload")
  end
  # Handler for POST-ed API calls. Merges URL parameters obtained from APIV1Router with params from the request body.
  # Passes merged parameters to handle_request/2.
  defp handle_post_request(conn,payload) do
    payload = Map.merge(payload,conn.body_params)
    handle_request(conn,payload)
  end

  plug :match
  plug :dispatch

  get "/request/poll/:request_id" do
    handle_request(conn,%{"action" => "poll_request","request_id" => request_id})
  end
  get "/request/result/:request_id" do
    handle_request(conn,%{"action" => "get_result","request_id" => request_id})
  end
  get "/request/get" do
    handle_request(conn,%{"action" => "get_requests"})
  end
  get "/acl/get" do
    handle_request(conn,%{"action" => "get_acls"})
  end
  post "/acl/update_all" do
    handle_post_request(conn,%{"action" => "update_all_acls"})
  end

  post "/model/add" do
    handle_post_request(conn,%{"action" => "add_model"})
  end
  post "/model/update" do
    handle_post_request(conn,%{"action" => "update_model"})
  end
  post "/model/delete" do
    handle_post_request(conn,%{"action" => "delete_model"})
  end
  get "/model/get/:model_name" do
    handle_request(conn,%{"action" => "get_model","model" => model_name})
  end
  get "/model/get" do
    handle_request(conn,%{"action" => "get_models"})
  end

  post "/data_source/add" do
    handle_post_request(conn,%{"action" => "add_data_source"})
  end
  post "/data_source/update" do
    handle_post_request(conn,%{"action" => "update_data_source"})
  end
  post "/data_source/delete" do
    handle_post_request(conn,%{"action" => "delete_data_source"})
  end
  get "/data_source/get/:data_source_name" do
    handle_request(conn,%{"action" => "get_data_source","data_source" => data_source_name})
  end
  get "/data_source/get" do
    handle_request(conn,%{"action" => "get_data_sources"})
  end

  post "/endpoint/add" do
    handle_post_request(conn,%{"action" => "add_endpoint"})
  end
  post "/endpoint/update" do
    handle_post_request(conn,%{"action" => "update_endpoint"})
  end
  post "/endpoint/delete" do
    handle_post_request(conn,%{"action" => "delete_endpoint"})
  end
  get "/endpoint/get/:endpoint_name" do
    handle_request(conn,%{"action" => "get_endpoint","endpoint" => endpoint_name})
  end
  get "/endpoint/get" do
    handle_request(conn,%{"action" => "get_endpoints"})
  end
  get "/endpoint/run/:endpoint_name" do
    handle_request(conn,%{"action" => "run_endpoint","endpoint" => endpoint_name})
  end
  post "/endpoint/run" do
    handle_post_request(conn,%{"action" => "run_endpoint"})
  end

  post "/query/run" do
    handle_post_request(conn,%{"action" => "run_query"})
  end

  get "/query_plan/get/:request_id" do
    handle_request(conn,%{"action" => "get_query_plan","request_id" => request_id})
  end
  get "/query_plan/get" do
    handle_request(conn,%{"action" => "get_query_plans"})
  end

  # Unknown API endpoint, passing to API in case custom 404 handling is needed.
  match _ do
    handle_request(conn,%{"action" => "not_found"})
  end
end
