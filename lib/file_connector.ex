#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule FileResult do
  @moduledoc """
  Represents a result set from a `FileConnector` based Data Source.

  Intermediate representation between the raw Data Source, and the agnostic format created by `ResultSet`.

  Definitions:

  * `:conn`: the `FileConnectionWrapper`.
  * `:get_all`: whether the query requested all attributes (i.e. `SELECT *`)
  * `:columns`: List of actual attributes from the file (e.g. CSV headers)
  * `:files`: list of files involved in the query.
  * `:field_filter`: list of requested attributes in the query.
  * `:alias_fields`: alias mapping for for requested attributes that were aliased in the query (e.g. `SELECT ds.field AS alias`)
  * `:ds_alias`: target data source, as aliased in the query (e.g. `SELECT * FROM table ds_alias`)

  """
  @enforce_keys [:conn,:get_all,:files,:field_filter,:alias_fields,:ds_alias]
  defstruct [:conn,:get_all,:columns,:column_indexes,:files,:field_filter,:alias_fields,:ds_alias]
end
defmodule FileConnectionWrapper do
  @moduledoc """
  Represents a connection to a `FileConnector` based Data Source.

  Definitions:

  * `:path`: the OS level path, as defined in the Data Source.
  * `:result_type`: `:json` or `:csv`.
  * `:field_separator`: Delimiter for flat-file columns (e.g. ",") (`:csv` only)
  * `:result_path`: JSONPath to result data (e.g. "$.result[*]") (`:json` only)
  """
  @enforce_keys [:path,:result_type]
  defstruct [:path,:result_type,:field_separator,:result_path]
end
defimpl ResultSet, for: [FileResult,WebAPIResult] do
  # ResultSet protocol implementation to generate `Stream`s from `FileResult` and `WebAPIResult`.

  # Helper function to convert a raw map from the data source backend, into a list of aliased tuples.
  def map_to_aliased_list(result,map) do
    Enum.reduce(map,[],fn {key,val},acc ->
      val = {case Map.get(result.alias_fields,key) do
        nil -> {result.ds_alias,key,nil}
        f -> {result.ds_alias,f,key}
      end,val}
      [val|acc]
    end)
  end

  # Helper function to pair retrieved data attributes with their aliases.
  def alias_headers(result,headers) do
    tmp_field_map = Map.new(result.alias_fields,fn {key,val} -> {val,key} end)
    case headers do
      %{} = map ->
        Map.new(map,fn {key,val} ->
        {case Map.get(tmp_field_map,key) do
          nil -> {result.ds_alias,key,nil}
          f -> {result.ds_alias,key,f}
        end,val} end)
      [_head|_tail] = list -> Enum.map(list,fn key ->
        case Map.get(tmp_field_map,key) do
          nil -> {result.ds_alias,key,nil}
          f -> {result.ds_alias,key,f}
        end
      end)
    end |> LogUtil.inspect(label: "aliased_headers")
  end

  # Retrieves the full list of columns (attributes) from the associated result set.
  @impl true
  def get_all_columns(result) do
    result.columns
  end
  defp build_base_spnego_req(%{conn: %{url: url}}) do
      req = Req.new()
      Req.Request.merge_options(req,base_url: url,decode_body: false)
  end
  defp send_token(%{conn: _conn,endpoints: [endpoint|_]} = props,token) do
    req = build_base_spnego_req(props)
    token = Base.encode64(token)
    enc_resp = "Negotiate #{token}"
    req = Req.Request.put_header(req,"authorization",[enc_resp])
    case Req.get(req,url: endpoint) do
      {:ok,_resp} = ok -> ok
      {:error,err} -> {:error,"Exception during initial endpoint negotiation: #{inspect err}"}
    end
  end
  defp continue_spnego(props,state,prev_resp,num_attempts \\ 0) do
    case Req.Response.get_header(prev_resp,"www-authenticate") do
      [header] -> LogUtil.log("Found WWW Authenticate Response...")
        auth_header = header
        header_parts = String.split(auth_header," ",parts: 2)
        negotiate_token = Enum.at(header_parts,1,"")
        LogUtil.inspect(negotiate_token,label: "Negotiate token")
        decoded_token = Base.decode64!(negotiate_token)
        LogUtil.log(decoded_token,label: "Decoded token")
        case :sasl_auth.client_step(state,decoded_token) do
          {:ok,{:sasl_continue,token}} -> LogUtil.log("Got SPNEGO continuation...")
            case token do
              "" -> LogUtil.log("No continuation token, end of request")
                case prev_resp.status do
                  200 -> LogUtil.log("Access successful, returning final response...")
                    {:ok,prev_resp}
                  status -> LogUtil.log("Access failed with code #{inspect status}")
                      {:error,"Web API Request failed due to HTTP Status Code #{inspect status}"}
                end
              sasl_result ->
                  LogUtil.inspect(sasl_result,label: "Sasl result")
                  if num_attempts < 3 do
                    LogUtil.log("Found continuation token, continuing negotiation...")
                    case send_token(props,token) do
                      {:ok,resp} -> continue_spnego(props,state,resp,num_attempts+1)
                      {:error,_msg} = error -> error
                    end
                  else
                    LogUtil.log("Maximum attempts reached!")
                    {:error,"Failed to negotiate SPNEGO in #{inspect num_attempts} attempts!"}
                  end
            end
          {:ok,{code,_token}} -> {:error,"Unknown success state for SPNEGO continuation #{inspect code}"}
          {:error,{code,err}} -> {:error,"Error continuing SPNEGO: #{inspect err} (#{inspect code})"}
        end
      _ ->
        {:error,"No WWW authenticate header returned by endpoint!"}
    end
  end
  defp run_spnego(props,state) do
    case :sasl_auth.client_start(state) do
      {:ok,{_code,token}} -> LogUtil.log("Initial step successful, sending request")
        case send_token(props,token) do
          {:ok,resp} ->
            continue_spnego(props,state,resp)
          {:error,_msg} = error -> error
        end
      {:error,{code,err}} -> {:error,"Failed to initiate SPNEGO negotiation: #{inspect err} (#{inspect code})"}
    end
  end
  defp get_stream(result)
  defp get_stream(%WebAPIResult{conn: %{result_type: :json},sasl_state: sasl_state,result_path: result_path,columns: headers} = result) do
    if sasl_state != nil do
      case LogUtil.inspect(run_spnego(result,sasl_state),label: "run_spnego result") do
        {:ok,api_response} ->
          api_stream = api_response.body
          |> Jaxon.Stream.from_binary()
          |> Jaxon.Stream.query(result_path)
          if headers == nil do
            {:ok,api_stream |> Stream.flat_map(fn row -> [{:ok,row}] end)}
          else
            {:ok,api_stream |> Stream.flat_map(fn row -> [{:ok,alias_headers(result,row)}] end)}
          end
        {:error,_err} = error -> error
      end
    else
      {:error,"Invalid sasl state when retrieving Web API stream!"}
    end
  end
  defp get_stream(%FileResult{conn: %{result_type: :json,result_path: result_path},files: [file|_],columns: headers} = result) do
    f_stream = File.stream!(file,[read_ahead: 100_000],1000)
    |> Jaxon.Stream.from_enumerable()
    |> Jaxon.Stream.query(result_path)
    if headers == nil do
      {:ok,f_stream |> Stream.flat_map(fn row -> [{:ok,row}] end)}
    else
      {:ok,f_stream |> Stream.flat_map(fn row -> [{:ok,alias_headers(result,row)}] end)}
    end
  end
  defp get_stream(%FileResult{conn: %{result_type: :csv,field_separator: separator},files: [file|_],columns: headers}) do
    headers = if headers == nil do false else headers end
    f_stream = File.stream!(file,[read_ahead: 100_000],1000) |> CSV.decode([headers: headers, validate_row_length: true,separator: separator])
    {:ok,if is_list(headers) do f_stream |> Stream.drop(1) |> Stream.map(fn csv_out ->
      case csv_out do
        {:ok,row} -> {:ok,Map.new(row,fn {key,val} ->
          try do
            # Auto convert number-like fields to numeric data types, required because CSV parsing does not obey [lack of] quotations in the source file
            val = if String.match?(val,~r/^[\-|\+]?[[:digit:]]+\.[[:digit:]]+$/) do
              # Float
              String.to_float(val)
            else
              if String.match?(val,~r/^[\-|\+]?[[:digit:]]+$/) do
                # Integer
                String.to_integer(val)
              else
                # Neither
                val
              end
            end
            {key,val}
          rescue
            e ->
              msg = "Error during implicit type conversion for CSV data source (field: #{inspect key}, value: #{val}): #{Exception.message(e)})"
              raise(msg)
          end
        end)
      }
      out -> out
    end
    end) else f_stream end}
  end
  defp get_headers(result) do
    with {:ok,f_stream} <- get_stream(result) do
      case LogUtil.inspect(Enum.take(f_stream,1),label: "First row") do
        [{:ok,first_row}] ->
          {:ok,LogUtil.inspect(alias_headers(result,if result.conn.result_type == :json do Map.keys(first_row) else first_row end),label: "Aliased headers")}
        [{:error,_msg}] = error -> error
      end
    else
      {:error,_msg} = error -> error
    end
  end
  defp set_result_columns(result) do
    with {:ok,columns} <- get_headers(result) do
      result = Map.put(result,:columns,columns)
      {:ok,Map.put(result,:column_indexes,Enum.with_index(columns) |> Enum.into(%{}))}
    else
      {:error,_msg} = error -> error
    end
  end


  # Retrieves a `Stream` for a `WebAPIResult`. Performs Kerberos authentication prior to connecting to the Data Source.
  # Initializes a new kerberos context based on `:kerberos_client_keytab` and `:kerberos_client_uid` configuration values.
  @impl true
  def stream(%WebAPIResult{conn: conn,ds_alias: ds_alias} = result) do
    task = Task.async(fn ->
    case :sasl_auth.kinit(Application.fetch_env!(:DV,:kerberos_client_keytab),Application.fetch_env!(:DV,:kerberos_client_uid)) |> LogUtil.inspect(label: "kinit result") do
      :ok -> LogUtil.log("kinit successful...")
        with {:ok,spn_parts} <- SharedUtil.parse_spn(conn.auth.spn) do
          case :sasl_auth.client_new(spn_parts[:service],spn_parts[:host],Application.fetch_env!(:DV,:kerberos_client_uid)) |> LogUtil.inspect(label: "Client new") do
            {:ok,sasl_state} ->
              try do
                do_stream(Map.put(result,:sasl_state,sasl_state))
              rescue
                e ->
		LogUtil.error(Exception.format(:error,e,__STACKTRACE__))
		{:error,"Problem parsing data from Web API #{ds_alias}, check response and data source configuration!"}
              end
            {:error,error_code} -> {:error,"Failed to initiate SASL authentication: (#{inspect error_code})"}
          end
        else
          {:error,_err} = error -> error
        end
      {:error,kinit_state} -> {:error,"Failed to kinit during Web API call: #{inspect kinit_state}"}
    end end)
    case Task.yield(task,:infinity) || Task.shutdown(task) do
       {:ok,stream_result} -> stream_result
       {:exit,exit_reason} -> {:error,"web API Task Exited unexpectedly! #{exit_reason}"}
       nil -> {:error,"Timeout while streaming Web API Task!"}
    end
  end

  # Retrieves a `Stream` for a `FileResult`.
  @impl true
  def stream(%{ds_alias: ds_alias} = result) do
    try do
      do_stream(result)
    rescue
      e ->
	LogUtil.error(Exception.format(:error,e,__STACKTRACE__))
	{:error,"Problem parsing data from File #{ds_alias}, check contents and data source configuration!"}
    end
  end
  defp confirm_fields_exist(get_all_fields,field_filter,headers) do
    LogUtil.log("get_all_fields #{inspect get_all_fields},field_filter: #{inspect field_filter},headers: #{inspect headers}")
    filter_set = MapSet.new(field_filter,fn {attr,_val} -> attr end)
    header_set = Enum.reduce(headers,MapSet.new(),fn {_ds_alias,f_name,f_alias},acc ->
      acc = MapSet.put(acc,{f_name,f_alias})
      MapSet.put(acc,{f_name,nil})
    end)
    LogUtil.inspect(header_set,label: "Header set")
    diff_set = MapSet.difference(filter_set,header_set)
    all_fields_found = Enum.empty?(diff_set)
    result = case {get_all_fields,all_fields_found} do
      {true,true} -> true
      {true,false} -> false
      {false,true} -> true
      {false,false} -> false
    end
    if result do {:ok} else {:error,"Fields do not exist: #{diff_set |> Enum.map(fn {f_name,_f_alias} -> "#{f_name}" end) |> Enum.join(",")}"} end
  end
  defp do_stream(%{ds_alias: ds_alias,field_filter: field_filter,get_all: get_all_fields} = result) do
    LogUtil.log("Result param: #{inspect result}")
    case set_result_columns(result) do
      {:ok,%{columns: headers} = result} ->
        with {:ok} <- confirm_fields_exist(get_all_fields,field_filter,headers) do
          with {:ok,f_stream} <- get_stream(result) do
            {:ok,Stream.transform(
            f_stream,
            result,
            fn row,result ->
              case LogUtil.inspect(row,label: "FileConnector Row") do
                {:error,err} -> {[{:error,err}],result}
                {:ok,row_map} ->
                  {[Enum.map(LogUtil.inspect(headers,label: "headers"),fn header -> Map.get(row_map,header) end)] |> LogUtil.inspect(label: "Converted row"),result}
              end
            end
            ),result}
          else
            {:error,msg} -> {:error,"Error initiating stream for data source #{inspect ds_alias}: #{inspect msg}"}
          end
        else
          {:error,msg} -> {:error,"Error parsing stream for data source #{inspect ds_alias}: #{inspect msg}"}
        end
      [{:error,_err}] = error -> {error,result}
     end
  end
end

defmodule FileConnector do
  @moduledoc """
  Data Source connectivity for flat-files.

  Supports delimited (e.g. CSV), and JSON format files.

  Does NOT support any form of authentication. Files must be readable by the identity running the platform.
  """
  @doc """
  Prepares a connection to a flat-file Data Source.

  `ds_props.path` MUST exist and be readable by the identity running the platform.
  """
  def connect(ds_props,constants \\ []) do
    real_path = Path.expand(ds_props.path)
    if File.exists?(real_path,[:raw]) do
       case Keyword.get(constants,:result_type,:csv) do
        :csv ->
          [separator] = String.to_charlist(ds_props.field_separator)
          LogUtil.info("connected to CSV data source (path: #{real_path})")
          {:ok,%FileConnectionWrapper{path: real_path,result_type: :csv,field_separator: separator}}
        :json ->
          with {:ok,result_path} <- Jaxon.Path.parse(ds_props.result_path) do
            LogUtil.info("connected to JSON data source (path: #{real_path})")
            {:ok,%FileConnectionWrapper{path: real_path,result_type: :json,result_path: result_path}}
          else
            {:error,msg} ->
              LogUtil.error("invalid JSONPath for JSON data source (path: #{real_path},JSON Path: #{ds_props.result_path})")
              {:error,"Failed to parse result path: #{inspect msg}"}
          end
       end
    else
      LogUtil.error("file path does not exist (path: #{real_path})")
      {:error,"Path #{inspect real_path} does not exist!"}
    end
  end
  @doc """
  Prepares a result set for a flat-file Data Source connection.

  Queried files MUST exist and be readable by the identity running the platform.
  """
  def get(conn,segment) do
    LogUtil.inspect(segment,label: "Get segment")
    %QueryComponentResource{src: partial_path,alias: alias} = segment.resource
    file_part = Path.split(partial_path) |> Enum.filter(fn p -> not (p == "." or p == "..") end) |> Enum.join()
    file_path = LogUtil.inspect(Path.join(conn.path,file_part),label: "file_path")
    case File.exists?(file_path,[:raw]) do
      true ->
        case File.dir?(file_path,[:raw]) do
         false ->
          {field_filter,alias_map,all_columns} = parse_fields(segment.fields)
          {:ok,%FileResult{conn: conn,get_all: all_columns,files: [file_path],field_filter: field_filter,alias_fields: alias_map,ds_alias: alias}}
         true ->
          LogUtil.error("requested file is a directory, expected a file (file path: #{file_path})")
          {:error,"Path #{inspect file_path} is a directory!"}
      end
      false ->
        LogUtil.error("requested file does not exist (file path: #{file_path})")
        {:error,"Path #{inspect file_path} does not exist!"}
    end
  end
  # Translates parsed query components for fields into the format required for retrieval.
  # For `:file` data sources, `accum` is a map indicating which keys are being `SELECT`ed.
  # As with all `parse_fields/4` calls, also returns `alias_map` for alias translation, and `all_columns` indicating if e.g. `SELECT *` was used.
  defp parse_fields(fields,accum \\ %{},alias_map \\ %{},all_columns \\ false)
  defp parse_fields([],accum,alias_map,all_columns) do
    LogUtil.inspect({accum,alias_map,all_columns},label: "Final field list")
  end
  defp parse_fields([%{_index: _index} = field|fields],accum,alias_map,_all_columns) do
    case field do
      # If `SELECT *` is used, rely on `all_columns` since `:file` data sources pull all fields by default
      %QueryComponentAllFields{} ->
        parse_fields(fields,accum,alias_map,true)
      %QueryComponentField{field: name,alias: alias} ->
        field_parts = if alias == nil do {name,nil} else {name,alias} end
        alias_map = if alias == nil do alias_map else Map.put(alias_map,alias,name) end
        parse_fields(fields,Map.put(accum,field_parts,1),alias_map)
      # Flat files do not support functions, treat passing a function as an error
      # This should only happen if there is a misconfiguration with `PlatformFuncs` or `ForcePlatformFuncs`.
        _ -> {:error,"Unmatched field #{inspect field}"}
    end
  end
end
