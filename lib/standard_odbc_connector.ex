#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defprotocol ResultSet do
  @moduledoc """
  Protocol all result sets for every data source type must implement.

  Provides utility functions to retrieve a stream from the data source, and to retrieve a full column (attribute) list.

  """
  @spec stream(Struct.t()) :: {:ok,Stream.t()}#{:ok,Stream.t()} | {:halt,any()} | {:error,String.t()}
  @spec get_all_columns(Struct.t()) :: list()
  @doc """
  Return a Stream that provides all records from the underlying data source.

  Expected to stream lists of tuples in the form of [{{ds_alias,field_name,field_alias},field_value}...]
  """
  def stream(result)
  @doc """
  Return a list of all columns in the result set, in {{ds_alias,field_name,field_alias},field_value} format.
  """
  def get_all_columns(result)
end
defmodule ODBCResult do
  @moduledoc """
  Represents a result set from a `StanardODBCConnector` based Data Source. Can also be used for any other connector that requires ODBC results.

  Intermediate representation between the raw Data Source, and the agnostic format created by `ResultSet`.

  Definitions:

  * `:conn`: the raw `:odbc` connection.
  * `:get_all`: whether the query requested all attributes (i.e. `SELECT *`)
  * `:columns`: List of actual attributes from the data source (i.e. columns)
  * `:alias_fields`: alias mapping for for requested attributes that were aliased in the query (e.g. `SELECT ds.field AS alias`)
  * `:ds_alias`: target data source, as aliased in the query (e.g. `SELECT * FROM table ds_alias`)
  * `:sasl_state`: Tracks SASL Kerberos library state, used during `WebAPIResult` handling.
  """
  @enforce_keys [:conn,:ds_alias]
  defstruct [:conn,:get_all,:columns,:column_indexes,:alias_fields,:ds_alias]
end
defimpl ResultSet, for: ODBCResult do
  @impl true
  def get_all_columns(result) do
    result.columns
  end
  # Retrieves a `Stream` for a `ODBCResult`. Expects an already established connection.
  @impl true
  def stream(result) do
    {:ok,Stream.resource(fn -> result.conn end,
    fn conn ->
      case :odbc.next(conn) do
        {:error,err} -> {[{:error,to_string(err)}],conn}
        {:selected,_cols,[]} -> {:halt,conn}
        {:selected,_cols,value_tuple_list} ->
          values = Tuple.to_list(List.first(value_tuple_list,{}))
          {[values],conn}
        end
    end,
    fn conn -> :odbc.disconnect(conn) end
    ),result}
  end
end
defmodule StandardODBCConnector do
  @moduledoc """
  Data Source connectivity for ODBC-based data sources.

  Supports Kerberos authentication ONLY.
  """
  defp build_connection_string(string,[{key,value}|values]) do
    build_connection_string(String.replace(string,"$#{key}",value),values)
  end
  defp build_connection_string(string,[]) do
    string
  end
  @doc """
  Prepares a connection to an ODBC Data Source.

  Initializes a new kerberos context based on `:kerberos_client_keytab` and `:kerberos_client_uid` configuration values.
  """
  def connect(ds_props,constants \\ []) do
    case :sasl_auth.kinit(Application.fetch_env!(:DV,:kerberos_client_keytab),Application.fetch_env!(:DV,:kerberos_client_uid)) |> LogUtil.inspect(label: "kinit result") do
      :ok -> LogUtil.log("kinit successful...")
      {:error,kinit_state} -> {:error,"Failed to kinit during Web API call: #{inspect kinit_state}"}
    end
    LogUtil.log("Connecting to #{inspect ds_props}")
    conn_str = build_connection_string(Keyword.fetch!(constants,:connection_string),[
      {"driver",Keyword.fetch!(constants,:driver)},
      {"hostname",ds_props.hostname},
      {"database",ds_props.database},
      {"spn",ds_props.auth.spn},
      {"uid",Map.get(ds_props,:uid,Application.fetch_env!(:DV,:kerberos_client_uid))}
    ]
    )
    LogUtil.inspect(:odbc.connect(to_charlist(conn_str),[binary_strings: :on]),label: "odbc.connect result")
  end
  # Prepends all columns not already selected to the field list (resolves SELECT *)
  defp prepend_star_cols(conn,tname,field_list,alias_map) do
    with {:ok,column_types} <- LogUtil.inspect(:odbc.describe_table(conn,String.to_charlist(tname)),label: "Describe table") do
      column_list = Enum.reverse(column_types) |> Enum.reduce(field_list,fn col,acc ->
        col = to_string(elem(col,0))
        if not Map.has_key?(alias_map,col) do
          [col|acc]
        else
          acc
        end
      end)
      {:ok,column_list}
    else
      {:error,msg} -> {:error,"Error mapping * fields: #{to_string(msg)}"}
    end
  end
  # Converts a list of columns from the ODBC result into the expected field tuple format (i.e. `{data_source,field_name,field_alias}`)
  defp map_cols(cols,ds_alias,alias_fields) do
    field_to_alias = Map.new(alias_fields,fn {key,val} -> {val,key} end)
    cols |> Enum.map(fn col ->
      col = to_string(col) |> LogUtil.inspect(label: "col string")
      case LogUtil.inspect(Map.get(field_to_alias,col),label: "alias_fields value") do
        nil -> {ds_alias,col,nil}
        # {f,nalias} -> {ds_alias,f,nalias}
        alias -> {ds_alias,col,alias}
      end
    end)
  end
  @doc """
  Prepares a result set for an ODBC Data Source connection.
  """
  def get(conn,segment) do
    LogUtil.inspect(segment,label: "Get segment")
    %QueryComponentResource{src: tname,alias: ds_alias} = segment.resource
    {field_list,query_fields,alias_map,all_columns} = parse_fields(segment.fields) |> LogUtil.inspect(label: "parse_fields")
    full_field_list = if all_columns do prepend_star_cols(conn,tname,alias_map,field_list) else {:ok,field_list} end
    with {:ok,column_list} <- full_field_list do
      alias_str = if ds_alias == nil do "" else " #{ds_alias}" end
      q_string = "SELECT #{query_fields} FROM #{tname}#{alias_str}"
      LogUtil.log("Query String: #{inspect q_string}")
      with {:ok,_num_rows} <- :odbc.select_count(conn,String.to_charlist(q_string)) do
        mapped_cols = map_cols(column_list,ds_alias,alias_map)
        {:ok,%ODBCResult{conn: conn,get_all: all_columns,columns: mapped_cols,column_indexes: Enum.with_index(mapped_cols) |> Enum.into(%{}),alias_fields: alias_map,ds_alias: ds_alias}}
      else
        {:error,msg} -> {:error,to_string(msg)}
      end
    else
      {:error,msg} -> {:error,msg}
    end
  end
  # Translates parsed query components for fields into the format required for retrieval.
  # For `:relational` data sources, `accum` is all `SELECT`ed fields and functions in SQL format (e.g. strings like `field AS alias`).
  # As with all `parse_fields/4` calls, also returns `alias_map` for alias translation, and `all_columns` indicating if e.g. `SELECT *` was used.
  defp parse_fields(fields,field_list_accum \\ [],query_fields_accum \\ [],alias_map \\ %{},all_columns \\ false)
  defp parse_fields([],field_list_accum,query_fields_accum,alias_map,all_columns) do
    query_fields = Enum.join(query_fields_accum,",")
    LogUtil.inspect({field_list_accum,query_fields,alias_map,all_columns},label: "Final field list")
  end
  defp parse_fields([%{_index: _index} = field|fields],field_list_accum,query_fields_accum,alias_map,_all_columns) do
    case field do
      # If `SELECT *` is used, need to actually `SELECT` all columns
      %QueryComponentAllFields{} ->
        parse_fields(fields,field_list_accum,query_fields_accum,alias_map,true)
      %QueryComponentField{field: name,alias: alias} ->
        alias_map = if alias == nil do alias_map else Map.put(alias_map,alias,name) end
        parse_fields(fields,[name|field_list_accum],[name|query_fields_accum],alias_map)
      # For functions, executes the data source specific function support callback to obtain the string representation of the function
      %QueryComponentFunc{params: params,alias: alias,_ident: ident,_func: {module,func}} ->
        LogUtil.debug("Executing #{inspect module}.#{inspect func} with params #{inspect params}")
        {:ok,func_str} = apply(module,func,params)
        func_str = "#{func_str} AS #{ident}"
        alias_map = if alias == nil do alias_map else Map.put(alias_map,alias,ident) end
        # alias_map = if alias == nil do alias_map else Map.put(alias_map,ident,{ident,alias}) end
        parse_fields(fields,[ident|field_list_accum],[func_str|query_fields_accum],alias_map)
        _ -> {:error,"Unmatched field #{inspect field}"}
    end
  end
end
