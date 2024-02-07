#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule DataSources do
  @moduledoc """
  Provides functionality required for the system to connect to configured Data Sources:

    * Loads connector and function support modules based on platform configuration
    * Resolves connection requests for individual data sources
    * Resolves requests for function support modules
  """
  use GenServer
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__,state,name: __MODULE__)
  end
  # Used to force Data Source Connector and Function modules to be available.
  defp ensure_module_loaded(ds_module_raw) do
    case ds_module_raw do
      {ds_module,_constants} -> Code.ensure_loaded!(ds_module)
      ds_module -> Code.ensure_loaded!(ds_module)
    end
  end
  @impl true
  def init(_opts) do
    _connector_registry = :ets.new(:connectors,[:named_table,:set,:protected,read_concurrency: true])
    cfg = Application.get_env(:DV,:connectors,[])
    Enum.each(cfg,fn c ->
      with {class,type,version,connector_module,func_module} <- c do
        LogUtil.debug("Processing connector #{class} #{type} #{version} #{inspect connector_module} #{inspect func_module}")
        :ets.insert(:connectors,{{type,version},%{
          class: class,
          connector: connector_module,
          func: func_module
        }})
        ensure_module_loaded(connector_module)
        ensure_module_loaded(func_module)
      end
    end)
    {:ok,nil}
  end
  defp get_datasource(ds_name) do
    Metadata.get(:dv_data_sources,ds_name)
  end
  @doc """
  Returns the function support module for a given Data Source name.
  """
  def get_ds_func_module(ds_name) do
    with {:ok,ds_props} <- get_datasource(ds_name) do
      with {:ok,func_module} <- select_module(ds_props,:func) do
        {:ok,func_module}
      else
        {:error,str} -> {:error,"#{str} Check configuration of #{ds_name} data source"}
      end
    else
      _ -> {:error,"Datasource #{ds_name} not registered, cannot get function module!"}
    end
  end
  defp do_connect({ds_module,constants},ds_props) do
    {ds_module,apply(ds_module,:connect,[ds_props,constants])}
  end
  defp do_connect(ds_module,ds_props) do
    {ds_module,apply(ds_module,:connect,[ds_props])}
  end
  @doc """
  Connects to the specified data source.

  Returns the connection handle, and the connection module.
  """
  def connect(ds_name) do
      with {:ok,ds_props} <- get_datasource(ds_name) do
      with {:ok,ds_connector} <- select_module(ds_props,:connector) do
        LogUtil.debug("Connecting to #{ds_name} using #{inspect ds_connector}")
        {ds_module,{:ok,conn}} = do_connect(ds_connector,ds_props)
        {:ok,{conn,ds_module}}
      else
        {:error,str} -> {:error,"#{str} Check configuration of #{ds_name} data source"}
      end
    else
      _ -> {:error,"Datasource #{ds_name} not registered, cannot connect!"}
    end
  end
  defp select_module(ds_props,module_type) do
    case get_connector_settings(ds_props.type,ds_props.version) do
      {:ok,connector_settings} -> {:ok,connector_settings[module_type]}
      {:error,_msg} = err -> err
    end
  end
  @doc """
  Checks if a connector exists for the combination of `type` and `version`.

  Returns a boolean.
  """
  def connector_exists(type,version) do
    case select_module(%{type: type,version: version},:connector) do
      {:ok,_module} -> true
      _ -> false
    end
  end
  @doc """
  Returns the connector settings for`type` and `version`.

  This will start with strictly matching `type` + `version`, and failback to any `type` + nil (as defined in config).
  """
  def get_connector_settings(type,version) do
    LogUtil.debug("lookup: #{inspect :ets.lookup(:connectors,{type,version})}")
    case :ets.lookup(:connectors,{type,version}) do
      [] -> LogUtil.debug("Failing over to base type..")
        case :ets.lookup(:connectors,{type,nil}) do
          [] -> {:error,"Module does not exist!"}
          [{_key,connector_settings}] -> {:ok,connector_settings}
        end
      [{_key,connector_settings}] ->
        LogUtil.debug("Found strictly matching type #{inspect connector_settings}")
        {:ok,connector_settings}
    end
  end
end
