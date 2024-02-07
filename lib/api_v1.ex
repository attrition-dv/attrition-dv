#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule APIV1 do
  @moduledoc """
  V1 API handlers.

  Wrapped by all `APIV1` delegates to implement APIV1 functionality.

  *Part of V1 API*
  """

  @doc """
  Accepts API request from the specified source (`:websocket` or `:rest`), executes relevant handler.

  Expects a request context providing, at minimum, the username of the authenticated user.

  When `request_source` is `:websocket`, will decode raw JSON from a binary. When source is `:rest`, expects a Map or Struct of parameters.

  Returns a JSON string wrapped in a status tuple (e.g. `{:ok,json_data}` or `{:error,json_data}`.
  """
  def handle(msg,request_context,request_source \\ :websocket)
  def handle(msg,request_context,:websocket) do
    # WebSockets only support JSON right now
    case Jason.decode(msg) do
      {:ok,payload} ->
        LogUtil.debug("Successfully decoded: #{inspect payload}")
        LogUtil.info("starting API call from websocket (#{payload_to_log(payload,request_context)})")
        result = handle_cmd(payload,request_context) |> LogUtil.inspect(label: "result payload")
        case result do
          {:ok,_payload} -> LogUtil.pipe(result,"API call from websocket (#{payload_to_log(payload,request_context)}) complete",level: :info)
          {:error,_code,_msg} -> LogUtil.pipe(result,"API call from websocket (#{payload_to_log(payload,request_context)}) failed!",level: :error)
        end
      {:error,payload} ->
        LogUtil.debug("Failed to decode: #{inspect payload}")
        LogUtil.error("invalid API call from websocket (#{payload_to_log(payload,request_context)})")
        encode_resp(payload)
    end
  end
  def handle(payload,request_context,:rest) do
    # REST requests are automatically decoded in `APIV1RESTHandler`.
    LogUtil.info("starting API call from REST (#{payload_to_log(payload,request_context)})")
    result = handle_cmd(payload,request_context)
    case result do
      {:ok,_payload} -> LogUtil.pipe(result,"API call from REST (#{payload_to_log(payload,request_context)}) complete",level: :info)
      {:error,_code,_msg} -> LogUtil.pipe(result,"API call from REST (#{payload_to_log(payload,request_context)}) failed!",level: :error)
    end
  end
  # Selectively builds a log segment out of a payload, with context
  defp payload_to_log(payload,context) do
    target_keys = ["action","request_id","model","data_source","endpoint","context"]
    payload = if context != nil do Map.put(payload,"context","{#{map_to_str(context)}}") else payload end
    Map.take(payload,target_keys) |> map_to_str()
  end
  defp map_to_str(map) do
    Enum.map_join(map,", ",&("#{elem(&1,0)}: #{elem(&1,1)}"))
  end
  #Dispatches individual API calls to `DV` backend.
  #Expects a Map or Struct of API call parameters, and a request context.
  defp handle_cmd(payload,request_context)
  defp handle_cmd(%{"action" => "poll_request","request_id" => request_id},request_context) do
    LogUtil.log("executing API call - poll_request (request_id: #{request_id})")
    if String.length(request_id) > 0 do
      resp = with {:ok,_request} = request_resp <- GenServer.call(DV,{{:request,:get},request_id,request_context}) do
        request_resp
      else
        {:error,_type,_msg} = err -> err
        {:error,msg} -> {:error,:not_found,msg}
      end
      encode_resp(resp)
    else
      encode_resp({:error,:validation_error,%{"request_id" => "Request ID cannot be empty"}})
    end
  end
  defp handle_cmd(%{"action" => "get_result","request_id" => request_id},request_context) do
    LogUtil.log("executing API call - get_result (request_id: #{request_id})")
    if String.length(request_id) > 0 do
      resp = with {:ok,result_set_file} <- GenServer.call(DV,{{:request,:get_result},request_id,request_context}) do
        {:file,result_set_file}
      else
        {:error,_type,_msg} = err -> err
        {:error,msg} -> {:error,:not_found,msg}
      end
      encode_resp(resp)
    else
      encode_resp({:error,:validation_error,%{"request_id" => "Request ID cannot be empty"}})
    end
  end
  defp handle_cmd(%{"action" => "get_acls"},request_context) do
    resp = GenServer.call(DV,{{:acl,:get_all},nil,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "add_model"} = payload,request_context) do
    resp = GenServer.call(DV,{{:model,:add},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "add_endpoint"} = payload,request_context) do
    resp = GenServer.call(DV,{{:endpoint,:add},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "add_data_source"} = payload,request_context) do
    resp = GenServer.call(DV,{{:data_source,:add},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "update_model"} = payload,request_context) do
    resp = GenServer.call(DV,{{:model,:update},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "update_endpoint"} = payload,request_context) do
    resp = GenServer.call(DV,{{:endpoint,:update},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "update_data_source"} = payload,request_context) do
    resp = GenServer.call(DV,{{:data_source,:update},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "update_all_acls"} = payload,request_context) do
    resp = GenServer.call(DV,{{:acl,:update_all},Map.drop(payload,["action"]),request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "delete_model"} = payload,request_context) do
    resp = GenServer.call(DV,{{:model,:delete},payload,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "delete_endpoint"} = payload,request_context) do
    resp = GenServer.call(DV,{{:endpoint,:delete},payload,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "delete_data_source"} = payload,request_context) do
    resp = GenServer.call(DV,{{:data_source,:delete},payload,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_model","model" => model_name},request_context) do
    resp = GenServer.call(DV,{{:model,:get},model_name,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_endpoint","endpoint" => endpoint_name},request_context) do
    resp = GenServer.call(DV,{{:endpoint,:get},endpoint_name,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_data_source","data_source" => ds_name},request_context) do
    resp = GenServer.call(DV,{{:data_source,:get},ds_name,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_models"},request_context) do
    resp = GenServer.call(DV,{{:model,:get_all},nil,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_endpoints"},request_context) do
    resp = GenServer.call(DV,{{:endpoint,:get_all},nil,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_data_sources"},request_context) do
    resp = GenServer.call(DV,{{:data_source,:get_all},nil,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "run_endpoint","endpoint" => endpoint_name},request_context) do
    resp = GenServer.call(DV,{{:endpoint,:run},endpoint_name,request_context}) |> LogUtil.pipe("Result of {:endpoint,:run} for #{endpoint_name}")
    resp = case resp do
      {:request_id,request_id} ->
        # Run was successful and returned a request ID, wrap it in a struct
        encode_resp({:ok,%{request_id: request_id}})
      msg ->
        # Unsuccessful, handle as-is
        encode_resp(msg)
    end
    resp
  end
  defp handle_cmd(%{"action" => "run_query","query" => query_string},request_context) do
    if String.length(query_string) > 0 do
      resp = GenServer.call(DV,{{:query,:run},query_string,request_context})
      resp = case resp do
        {:request_id,request_id} ->
          # Run was successful and returned a request ID, wrap it in a struct
          encode_resp({:ok,%{request_id: request_id}})
        msg ->
          # Unsuccessful, handle as-is
          encode_resp(msg)
      end
      resp
    else
      encode_resp({:error,:validation_error,%{"query" => "Query string cannot be empty"}})
    end
  end
  defp handle_cmd(%{"action" => "get_query_plans"},request_context) do
    resp = GenServer.call(DV,{{:query_plan,:get_all},nil,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_query_plan","request_id" => request_id},request_context) do
    resp = GenServer.call(DV,{{:query_plan,:get},request_id,request_context})
    encode_resp(resp)
  end
  defp handle_cmd(%{"action" => "get_requests"},request_context) do
    resp = GenServer.call(DV,{{:request,:get_all},nil,request_context})
    encode_resp(resp)
  end
  # Allows API handlers to trigger a 404 response.
  defp handle_cmd(%{"action" => "not_found"},_request_context) do
    encode_resp({:error,:not_found,"Not Found"})
  end
  # Allows API handlers to trigger a 500 response.
  defp handle_cmd(%{"action" => "internal_server_error"},_request_context) do
    encode_resp({:error,:internal_server_error,"Internal Server Error"})
  end
  # Unknown API action.
  defp handle_cmd(_payload,request_context) do
    handle_cmd(%{"action" => "not_found"},request_context)
  end
  # Uses `Jason` to encode responses into the JSON formats expected by API consumers
  # These formats are the same for WebSocket and REST
  defp encode_resp(response)
  defp encode_resp({:file,_filename} = file) do
    {:ok,file}
  end
  defp encode_resp({:ok,payload}) do
    wrapped_payload = %{
      data: payload
    }
    {:ok,Jason.encode!(wrapped_payload)}
  end
  defp encode_resp({:error,:access_denied,payload}) do
    {:error,401,Jason.encode!(%{code: 401,error: payload,details: %{}})}
  end
  defp encode_resp({:error,:validation_error,payload}) do
    {:error,400,Jason.encode!(%{code: 400,error: "Validation Error",details: payload})}
  end
  defp encode_resp({:error,:not_found,payload}) do
    {:error,404,Jason.encode!(%{code: 404,error: payload,details: %{}})}
  end
  defp encode_resp({:error,:internal_server_error,payload}) do
    {:error,500,Jason.encode!(%{code: 500,error: payload,details: %{}})}
  end
  defp encode_resp({:error,_err_type,payload}) do
    encode_resp({:error,:internal_server_error,payload})
  end
  defp encode_resp({:error,payload}) do
    encode_resp({:error,:generic,payload})
  end
  defp encode_resp(%Jason.DecodeError{position: pos}) do
    msg = "Invalid JSON Payload at position #{inspect pos}."
    encode_resp({:error,msg})
  end
end
