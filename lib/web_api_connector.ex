#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule WebAPIResult do
  @moduledoc """
  Represents a result set from a `WebAPIConnector` based Data Source.

  Intermediate representation between the raw Data Source, and the agnostic format created by `ResultSet`.

  Definitions:

  * `:conn`: the `WebAPIConnectionWrapper`
  * `:get_all`: whether the query requested all attributes (i.e. `SELECT *`)
  * `:columns`: List of actual attributes from the data source.
  * `:endpoints`: List of endpoint URIs relevant to this result set (obtained from the endpoint mappings for the data source). Only one entry is used currently.
  * `:field_filter`: list of requested attributes in the query.
  * `:result_path`: JSONPath to result data (e.g. "$.result[*]")
  * `:alias_fields`: alias mapping for for requested attributes that were aliased in the query (e.g. `SELECT ds.field AS alias`)
  * `:ds_alias`: target data source, as aliased in the query (e.g. `SELECT * FROM table ds_alias`)

  """
  @enforce_keys [:conn,:get_all,:endpoints,:field_filter,:alias_fields,:ds_alias]
  defstruct [:conn,:get_all,:columns,:endpoints,:field_filter,:alias_fields,:ds_alias,:sasl_state,result_path: [:root]]
end
defmodule WebAPIConnectionWrapper do
  @moduledoc """
  Represents a connection to a `WebAPIConnector` based Data Source.

  Definitions:

  * `:url`: Web API base URL.
  * `:endpoint_mappings`: Map of friendly names to API endpoint URIs with result path details (e.g. `"endpoint": {
          "uri": "/path/to/endpoint",
          "result_path": "$.result[*]"
       }`)
  * `:auth`: Authentication parameters for the API. Currently always a map containing a Kerberos SPN.
  * `:result_type`: Type of API (only `:json` is supported currently)
  """
  @enforce_keys [:url,:auth,:endpoint_mappings,:result_type]
  defstruct [:url,:auth,:endpoint_mappings,:result_type]
end
defmodule WebAPIConnector do
  @moduledoc """
  Data Source connectivity for Web APIs.

  Supports JSON responses ONLY.

  Supports SPNEGO (Kerberos) authentication ONLY.
  """
  @doc """
  Prepares a connection to a Web API Data Source.

  This is function builds `WebAPIConnectionWrapper` WITHOUT connecting to the API.

  """
  def connect(ds_props,constants \\ []) do
    LogUtil.log("ds_props: #{inspect ds_props}")
    {:ok,%WebAPIConnectionWrapper{result_type: Keyword.get(constants,:result_type,:json),url: ds_props.url,endpoint_mappings: ds_props.endpoint_mappings,auth: ds_props.auth}}
  end
  @doc """
  Prepares a result set for a Web API Data Source connection.

  Expects the requested endpoint to exist in the data source `Metadata` endpoint_mappings.
  """
  def get(conn,segment) do
    LogUtil.inspect(segment,label: "Get segment")
    %QueryComponentResource{src: api_endpoint,alias: alias} = segment.resource
    case Map.get(conn.endpoint_mappings,String.downcase(api_endpoint),nil) do
      nil -> {:error,"Endpoint #{inspect api_endpoint} does not exist in data source endpoint mapping!"}
      %{uri: endpoint,result_path: path} ->
      with {:ok,result_path} <- Jaxon.Path.parse(path) do
        {field_filter,alias_map,all_columns} = parse_fields(segment.fields)
        {:ok,%WebAPIResult{conn: conn,get_all: all_columns,endpoints: [endpoint],field_filter: field_filter,alias_fields: alias_map,ds_alias: alias,result_path: result_path}}
      else
        {:error,msg} -> {:error,"Could not parse result path: #{inspect msg}"}
      end
    end
  end
  # Translates parsed query components for fields into the format required for retrieval.
  # For `:web_api` data sources, `accum` is a map indicating which keys are being `SELECT`ed.
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
        _ -> {:error,"Unmatched field #{inspect field}"}
    end
  end
end
