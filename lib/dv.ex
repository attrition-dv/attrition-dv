#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule DV.ValidatorUtils do
  @moduledoc """
  Shared utility functions for `DV.Requests` validators.

  All of these functions return a boolean.
  """
  defp exists(_type,nil) do
    false
  end
  defp exists(type,name) do
    result = case type do
      :model -> DV.get_model(name)
      :endpoint -> DV.get_endpoint(name)
      :data_source -> DV.get_data_source(name)
    end
    case result do
      {:error,_msg} -> {:error,"#{String.replace(Atom.to_string(type),"_"," ")} does not exist"}
      {:ok,_val} -> :ok
    end
  end
  defp available(_type,nil) do
    {:error,"unknown value"}
  end
  defp available(:data_source,name) do
    case exists(:data_source,name) do
      {:error,_msg} -> :ok
      :ok -> {:error,"A data source exists with this name"}
    end
  end
  defp available(_type,name) do
    identifier_available(name)
  end
  # Checks if `identifier` is a model or an endpoint.
  defp identifier_available(identifier) do
    case DV.get_endpoint(identifier) do
      {:error,_msg} ->
        case DV.get_model(identifier) do
          {:error,_msg} -> :ok
          _ -> {:error,"A model exists with this name"}
        end
      _ -> {:error,"An endpoint exists with this name"}
    end
  end
  @doc """
  Checks if data source name exists in `Metadata`.
  """
  def model_name_exists(name) do
    exists(:model,name)
  end
  @doc """
  Checks if model name is available in `Metadata` (opposite of `model_name_exists/1`)
  """
  def model_name_available(name) do
    available(:model,name)
  end
  @doc """
  Checks if endpoint name exists in `Metadata`.
  """
  def endpoint_name_exists(name) do
    exists(:endpoint,name)
  end
  @doc """
  Checks if endpoint name is available in `Metadata` (opposite of `endpoint_name_exists/1`)
  """
  def endpoint_name_available(name) do
    available(:endpoint,name)
  end
  @doc """
  Checks if data source name exists in `Metadata`.
  """
  def data_source_name_exists(name) do
    exists(:data_source,name)
  end
  @doc """
  Checks if data source name is available in `Metadata` (opposite of `data_source_name_exists/1`)
  """
  def data_source_name_available(name) do
    available(:data_source,name)
  end
  # @doc """
  # Checks if data source connector module exists.
  # """
  # def data_source_connector_valid(connector) do
  #   case DataSources.connector_exists(elem(connector,0),elem(connector,1)) |> LogUtil.inspect(label: "Connector exists") do
  #     true -> :ok
  #     false -> {:error,"connector does not exist"}
  #   end
  # end
  @doc """
  Checks if data source authentication settings are valid (i.e.`%{type: "kerberos",spn: "spn"}`)
  """
  def data_source_auth_valid(auth) do
    if is_map(auth) do
      case Map.get(auth,"type",nil) do
        "kerberos" -> case Map.get(auth,"spn",nil) do
          nil -> {:error,"SPN must be provided for Kerberos authentication"}
          spn ->
            case SharedUtil.parse_spn(spn) do
              {:ok,_spn_parts} -> :ok
              {:error,_msg} -> {:error,"SPN must be in service/hostname@DOMAIN format"}
            end
        end
        _ -> {:error,"Invalid authentication type (expected \"kerberos\")"}
      end
    else
      {:error,"Auth must be a map of {\"type\": \"kerberos\",\"spn\":\"spn\"}"}
    end
  end
  @doc """
  Checks if a data source file path setting is a valid directory (e.g. '/var/tmp')
  """
  def data_source_file_path_valid(path) do
    case File.dir?(path,[:raw]) do
      true -> :ok
      false -> {:error,"File path must exist and be a directory"}
    end
  end
  @doc """
  Checks if a data source URL setting is valid (i.e. `http[s]://...`)
  """
  def data_source_url_valid(url) do
    url = String.downcase(url)
    case String.starts_with?(url,["http://","https://"]) do
      true -> :ok
      false -> {:error,"URL must start with http:// or https://"}
    end
  end
  @doc """
  Checks if single endpoint_mapping is valid.
  """
  def endpoint_mapping_valid(mapping) do
    case LogUtil.inspect(mapping,label: "mapping") do
      %{"uri" => uri,"result_path" => result_path} ->
        String.length(uri) > 0 and String.length(result_path) > 0
      _ -> false
    end
  end
  @doc """
  Checks if a map of endpoint mappings is valid.
  """
  def data_source_endpoint_mappings_valid(endpoint_mappings) do
    if is_map(endpoint_mappings) and not Enum.empty?(endpoint_mappings) do
      case Enum.reduce_while(endpoint_mappings,{true,nil},fn {_key,mapping},_acc ->
        if endpoint_mapping_valid(mapping) do {:cont,{true,nil}} else {:halt,{false,mapping}} end
      end
      ) do
        {true,nil} -> :ok
        {false,mapping} -> {:error,"Invalid endpoint mapping provided: #{inspect mapping}"}
      end
    else
      {:error,"Endpoint mappings must be a map of {\"name\": {\"uri\": \"...\",\"result_path\": \"...\"}}"}
    end
  end
  defp validate_acl_ident(ident) do
    if is_map(ident) and not Enum.empty?(ident) do
      Enum.reduce_while(["type","subtype","id"],true,fn key,_acc ->
        if Map.has_key?(ident,key) and String.length(Map.get(ident,key)) > 0 do
          {:cont,true}
        else
          {:halt,false}
        end
      end)
    else
      false
    end
  end
  defp validate_acl_acl(acls) do
    if is_map(acls) and not Enum.empty?(acls) do
      Enum.reduce_while(acls,true,fn {key,val},_acc ->
        if String.length(key) > 0 do
          cond do
          key == "disabled" and is_boolean(val) ->
            LogUtil.debug("ACL disabled")
            {:cont,true}
          key in ["data_source","endpoint","model","user","query","acl","request","query_plan"] ->
            LogUtil.log("Key #{key} in valid key list")
            if is_map(val) and not Enum.empty?(val) do
              LogUtil.debug("val is map")
              if Enum.all?(val,fn {key2,_val2} -> key2 in ["add","update","delete","get","run"] end) do {:cont,true} else {:halt,false} end
            else
              LogUtil.debug("val is NOT map")
              {:halt,false}
            end
          true ->
            LogUtil.debug("Unexpected ACL key #{key}")
            {:halt,false}
          end
        else
          LogUtil.debug("Empty ACL key")
          {:halt,false}
        end
      end)
    else
      LogUtil.debug("ACLs are not a map")
      false
    end
  end
  @doc """
  Checks if single ACL is valid.
  """
  def acl_valid(acl) do
    case acl do
      %{"ident" => ident,"acls" => acls} ->
        LogUtil.inspect(acls,label: "ACLs")
        validate_acl_ident(ident) and validate_acl_acl(acls)
      _ -> false
    end
  end
  @doc """
  Checks if list of ACLs is valid.
  """
  def acls_valid(acls) do
    LogUtil.log("Checking list of ACLS: #{inspect acls}")
    if is_list(acls) and not Enum.empty?(acls) do
      case Enum.reduce_while(acls,{true,nil},fn acl,_acc ->
        LogUtil.log("Checking acl: #{inspect acl}")
      if acl_valid(acl) do {:cont,{true,nil}} else {:halt,{false,acl}} end
      end
      ) do
        {true,nil} -> :ok
        {false,acl} -> {:error,"Invalid ACL entry provided: #{inspect acl}"}
      end
    else
      {:error,"ACL updates must be a list of maps in the format of {\"ident\": {\"type\": \"...\",\"subtype\": \"...\",\"id\": \"...\"},\"acls\": {\"category\": {\"action\":\true|false},..}}"}
    end
  end
  @doc """
  Checks if a query submitted for a model is valid.
  """
  def model_query_valid(nil) do
    {:error,"Query cannot be empty!"}
  end
  def model_query_valid(query_string) do
    with {:ok,[{:parts,parsed_query}],_rest,_context,_line,_column} <- Parsec.sql(query_string) do
      case DV.validate_data_sources(parsed_query) do
        {:ok} -> :ok
        {:error,failed_data_sources} ->{:error,"Data source(s) do not exist: #{Enum.join(failed_data_sources,",")}"}

      end
    else
      {:error,err,rest,_context,_line,_column} ->
      {:error,"Query parse error: #{err} (remaining query segment: #{rest})"}
    end
  end
end

defmodule DV.Request do
  @moduledoc """
  Represents a platform query request. Stored in `Metadata`.

  Definitions:

  * `:status`: Status of the request (`:IN_PROGRESS`,`:COMPLETED`,`:FAILED`).
  * `:start_time`: The start time of the request.
  * `:end_time`: The start time of the request.
  * `:model`: The name of the executed model (`run_endpoint` only).
  * `:endpoint`: The name of the executed endpoint (`run_endpoint` only).
  * `:query`: The raw query being executed
  * `:username`: The name of the requesting user.
  * `:result_set`: The request result set (`:COMPLETED` only). This is populated during request polling, and the result is purged immediately thereafter.
  * `:error`: The error that occurred during request processing (`:FAILED` only)
  * `:expired`: Boolean indicating if the `:result_set` was previously purged.
  """
  @derive {Jason.Encoder,only: [:status,:start_time,:end_time,:model,:endpoint,:query,:username,:error,:expired]}
  defstruct [:status,:start_time,:end_time,:model,:endpoint,:query,:username,:error,expired: false]
end
defmodule DV.Requests.Model.Add do
  @moduledoc """
  Represents an API request to add a model.

  Definitions:

  * `:model`: Model name.
  * `:query`: Model query.
  """
  use Vex.Struct
  defstruct [:model,:query]
  validates :model,presence: true,by: &DV.ValidatorUtils.model_name_available/1
  validates :query,presence: true,by: &DV.ValidatorUtils.model_query_valid/1
end
defmodule DV.Requests.Model.Update do
  @moduledoc """
  Represents an API request to update a model.

  Definitions:

  * `:model`: Model name.
  * `:query`: Model query.
  """
  use Vex.Struct
  defstruct [:model,:query]
  validates :model,presence: true,by: &DV.ValidatorUtils.model_name_exists/1
  validates :query,presence: true,by: &DV.ValidatorUtils.model_query_valid/1
end
defmodule DV.Requests.Model.Delete do
  @moduledoc """
  Represents an API request to delete a model.

  Definitions:

  * `:model`: Model name.
  """
  use Vex.Struct
  defstruct [:model]
  validates :model,presence: true,by: &DV.ValidatorUtils.model_name_exists/1
end
defmodule DV.Requests.Endpoint.Add do
  @moduledoc """
  Represents an API request to add an endpoint.

  Definitions:

  * `:model`: Model name.
  * `:endpoint`: Endpoint name.
  """
  use Vex.Struct
  defstruct [:model,:endpoint]
  validates :model,presence: true,by: &DV.ValidatorUtils.model_name_exists/1
  validates :endpoint,presence: true,by: &DV.ValidatorUtils.endpoint_name_available/1
end
defmodule DV.Requests.Endpoint.Update do
  @moduledoc """
  Represents an API request to update an endpoint.

  Definitions:

  * `:model`: Model name.
  * `:endpoint`: Endpoint name.
  """
  use Vex.Struct
  defstruct [:model,:endpoint]
  validates :model,presence: true,by: &DV.ValidatorUtils.model_name_exists/1
  validates :endpoint,presence: true,by: &DV.ValidatorUtils.endpoint_name_exists/1
end
defmodule DV.Requests.Endpoint.Delete do
  @moduledoc """
  Represents an API request to delete an endpoint.

  Definitions:

  * `:endpoint`: Endpoint name.
  """
  use Vex.Struct
  defstruct [:endpoint]
  validates :endpoint,presence: true,by: &DV.ValidatorUtils.endpoint_name_exists/1
end
defmodule DV.Requests.DataSource.AddRelational do
  @moduledoc """
  Represents an API request to add a relational data source.

  Definitions:

  * `:type`: Data source connector name (as defined in configuration)
  * `:version`: Data source connector version (as defined in configuration)
  * `:data_source`: Data source name.
  * `:hostname`: Data source server hostname.
  * `:database`: Data source database name.
  * `:auth`: Authentication parameters for the database. Currently always a map containing a Kerberos SPN.
  """
  use Vex.Struct
  defstruct [:type,:version,:data_source,:hostname,:database,:auth]
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_available/1
  validates :hostname,presence: true
  validates :database,presence: true
  validates :auth,presence: true,by: &DV.ValidatorUtils.data_source_auth_valid/1
end
defmodule DV.Requests.DataSource.UpdateRelational do
  @moduledoc """
  Represents an API request to update a relational data source.

  Definitions:

  * `:data_source`: Data source name.
  * `:hostname`: Data source server hostname.
  * `:database`: Data source database name.
  * `:auth`: Authentication parameters for the database. Currently always a map containing a Kerberos SPN.
  """
  use Vex.Struct
  defstruct [:data_source,:hostname,:database,:auth]
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_exists/1
  validates :hostname,presence: true
  validates :database,presence: true
  validates :auth,presence: true,by: &DV.ValidatorUtils.data_source_auth_valid/1
end
defmodule DV.Requests.DataSource.AddWebAPI do
  @moduledoc """
  Represents an API request to add a web API data source.

  Definitions:

  * `:type`: Data source connector name (as defined in configuration)
  * `:version`: Data source connector version (as defined in configuration)
  * `:data_source`: Data source name.
  * `:url`: Web API base URL.
  * `:endpoint_mappings`: Map of friendly names to API endpoint URIs with result path details (e.g. `"endpoint": {
          "uri": "/path/to/endpoint",
          "result_path": "$.result[*]"
       }`)
  * `:auth`: Authentication parameters for the API. Currently always a map containing a Kerberos SPN.
  """
  use Vex.Struct
  defstruct [:type,:version,:data_source,:url,:auth,:endpoint_mappings]
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_available/1
  validates :url,presence: true,by: &DV.ValidatorUtils.data_source_url_valid/1
  validates :auth,presence: true,by: &DV.ValidatorUtils.data_source_auth_valid/1
  validates :endpoint_mappings,by: &DV.ValidatorUtils.data_source_endpoint_mappings_valid/1
end
defmodule DV.Requests.DataSource.UpdateWebAPI do
  @moduledoc """
  Represents an API request to update a web API data source.

  Definitions:

  * `:data_source`: Data source name.
  * `:url`: Data source base URL.
  * `:endpoint_mappings`: Map of friendly names to API endpoint URIs with result path details (e.g. `"endpoint": {
          "uri": "/path/to/endpoint",
          "result_path": "$.result[*]"
       }`)
  * `:auth`: Authentication parameters for the API. Currently always a map containing a Kerberos SPN.
  """
  use Vex.Struct
  defstruct [:data_source,:url,:auth,:endpoint_mappings]
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_exists/1
  validates :url,presence: true,by: &DV.ValidatorUtils.data_source_url_valid/1
  validates :auth,presence: true,by: &DV.ValidatorUtils.data_source_auth_valid/1
  validates :endpoint_mappings,presence: true,by: &DV.ValidatorUtils.data_source_endpoint_mappings_valid/1
end
defmodule DV.Requests.DataSource.AddFile do
  @moduledoc """
  Represents an API request to add a flat-file data source.

  Definitions:

  * `:type`: Data source connector name (as defined in configuration)
  * `:version`: Data source connector version (as defined in configuration)
  * `:data_source`: Data source name.
  * `:path`: Flat-file base path.
  * `:field_separator`: Delimiter for flat-file columns (e.g. ",") (when configured data source `:type` is defined with `result_type: :csv`)
  * `:result_path`: JSONPath to result data (e.g. "$.result[*]") (when configured data source `:type` is defined with `result_type: :json`)
  """
  use Vex.Struct
  defstruct [:type,:version,:data_source,:path,field_separator: ",",result_path: "$"]
  # validates :__struct__,by: &DV.ValidatorUtils.data_source_file_type_valid/2
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_available/1
  validates :path,presence: true,by: &DV.ValidatorUtils.data_source_file_path_valid/1
end
defmodule DV.Requests.DataSource.UpdateFile do
  @moduledoc """
  Represents an API request to update a flat-file data source.

  Definitions:

  * `:data_source`: Data source name.
  * `:path`: Flat-file base path.
  * `:field_separator`: Delimiter for flat-file columns (e.g. ",") (when configured data source `:type` is defined with `result_type: :csv`)
  * `:result_path`: JSONPath to result data (e.g. "$.result[*]") (when configured data source `:type` is defined with `result_type: :json`)
  """
  use Vex.Struct
  defstruct [:data_source,:path,:result_path,:field_separator]
  # validates :__struct__,by: &DV.ValidatorUtils.data_source_file_type_valid/2
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_exists/1
  validates :path,presence: true, by: &DV.ValidatorUtils.data_source_file_path_valid/1
end
defmodule DV.Requests.DataSource.Delete do
  @moduledoc """
  Represents an API request to delete a data source.

  Definitions:

  * `:data_source`: Data source name.
  """
  use Vex.Struct
  defstruct [:data_source]
  validates :data_source,presence: true,by: &DV.ValidatorUtils.data_source_name_exists/1
end
defmodule DV.Requests.ACL.UpdateAll do
  @moduledoc """
  Represents an API request to update all platform ACLs.

  Definitions:

  * `:acls`: A list of `:ident`,`:acls` pairs.

  """
  use Vex.Struct
  defstruct [:acls]
  validates :acls,by: &DV.ValidatorUtils.acls_valid/1
end
defmodule DV.Responses.VexResult do
  @moduledoc """
  Represents a validation result from the `DV.Requests` modules.

  Used to implement `Jaseon Encoder` for encoding of validation errors.
  """
  @enforce_keys [:result]
  defstruct [:result]
end
defimpl Jason.Encoder,for: DV.Responses.VexResult do
  defp encode_reducer([],acc) do
    acc
  end
  defp encode_reducer([tuple|tuples],acc) do
    acc = case tuple do
      {:error,:__struct__,_validator,results} ->
        encode_reducer(results,acc)
      {:error,field,msg} ->
        Map.update(acc,Atom.to_string(field),[msg],fn existing -> [msg|existing] end)
      {:error,field,_validator,msg} ->
        Map.update(acc,Atom.to_string(field),[msg],fn existing -> [msg|existing] end) |> LogUtil.inspect(label: "Acc")
      _ -> acc
    end
    encode_reducer(tuples,acc)
  end
  def encode(value,opts) do
    out = encode_reducer(value.result,%{}) |> LogUtil.inspect(label: "Encoded vexresult")
    Jason.Encode.map(out,opts)
  end
end
defmodule DV do
  @moduledoc """
  Primary entry point for all platform API operations.

  Primary Responsibilities:

  * Accept API requests from API entry points (e.g. `APIV1Router` and related modules)
  * Centralize ACL verification
  * Perform CRUD operations against `Metadata`
  * Spawn async mediator processes to handle query requests
  * Handle async responses from query requests and update `DV.Request` entries

  """
  require Logger
  use GenServer
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__,state,name: __MODULE__)
  end
  @impl true
  def init(_state) do
    # :requests stores request metadata
    # Result sets are stored in the :dv_result_sets CubDB table
    # This is to allow for expiring the result set after retrieval, while keeping the metadata

    purge_result_sets() # Purging stale result sets
    result_set_expiry = Application.get_env(:DV,:result_set_expiry,3 * 60)
    Process.send_after(self(),{:purge_old_results,result_set_expiry},result_set_expiry * 1000)
    _request_registry = :ets.new(:requests,[:named_table,:set,:protected,read_concurrency: true])

    DataSources.start_link()
    Parsec.init_required_atoms() # Initializing atoms to allow for to_existing_atom
    :odbc.start()
    children = [
      {Task.Supervisor, name: DV.QMSupervisor}
    ]
    Supervisor.start_link(children,strategy: :one_for_one)

    create_initial_admins()

    state = %{} # Not actually used for anything
    {:ok,state}
  end
  # Creates ACL entries for `:initial_admins` - only done if ACLs are empty
  defp create_initial_admins() do
    if Metadata.size(:dv_user_acls) == 0 and Metadata.size(:dv_group_acls) == 0 do
      LogUtil.info("ACL repositories are empty, creating initial admins...")
      admin_acl = %PermACL{add: true,update: true,delete: true,get: true,run: true}
      full_acl_group = %PermACLGroup{
        disabled: false,
        data_source: admin_acl,
        endpoint: admin_acl,
        model: admin_acl,
        query: admin_acl,
        acl: admin_acl,
        query_plan: admin_acl,
        request: admin_acl
      }
      Enum.each(Application.get_env(:DV,:initial_admins,[]),fn {type,subtype,id} = entry ->
        acl_key = {subtype,String.downcase(id)}
        LogUtil.info("creating initial admin #{inspect entry}")
        case type do
          :user -> Metadata.add(:dv_user_acls,acl_key,full_acl_group)
          :group -> Metadata.add(:dv_group_acls,acl_key,full_acl_group)
        end
      end)
    else
      :ok
    end
  end
  defp get_all_acls() do
    Stream.concat(Metadata.get_all(:dv_user_acls) |> Stream.map(fn {{subtype,id},val} -> %PermPair{ident: %PermIdent{type: :user,subtype: subtype,id: id},acls: val} end),
    Metadata.get_all(:dv_group_acls) |> Stream.map(fn {{subtype,id},val} -> %PermPair{ident: %PermIdent{type: :group,subtype: subtype,id: id},acls: val} end)
    ) |> LogUtil.inspect(label: "get_all_acls")
  end
  # Takes a list of ACL changes from the API payload, and converts them to `PermACLGroup`, before updating the `Metadata` repository.
  defp update_all_acls(tmp_acls,user_acls \\ [],group_acls \\ [])
  defp update_all_acls([],user_acls,group_acls) do
    LogUtil.inspect(user_acls,label: "user_acls")
    LogUtil.inspect(group_acls,label: "group_acls")
    # These should never be empty in the current implementation, but might be if deletion were allowed
    if not Enum.empty?(user_acls) do Metadata.update_multi(:dv_user_acls,user_acls) |> LogUtil.inspect(label: "dv_user_acls update") end
    if not Enum.empty?(group_acls) do Metadata.update_multi(:dv_group_acls,group_acls) |> LogUtil.inspect(label: "dv_group_acls update")  end
  end
  defp update_all_acls([%{"ident" => %{"type" => acl_type,"subtype" => acl_subtype,"id" => acl_id} ,"acls" => acl_group}|acls],user_acls,group_acls) do
    acl_key = {String.to_existing_atom(String.downcase(acl_subtype)),String.downcase(acl_id)}
    acl_val = map_to_struct(PermACLGroup,acl_group,true)
    acl_tuple = {acl_key,acl_val} |> LogUtil.inspect(label: "ACL tuple")
    # Appends the current ACL to either user_acls or group_acls, based on acl_type
    update_all_acls(acls,if String.downcase(acl_type) == "user" do [acl_tuple|user_acls] else user_acls end,if String.downcase(acl_type) == "group" do [acl_tuple|group_acls] else group_acls end)
  end
  # Data source names are converted to lowercase before adding to the `Metadata` repository.
  defp add_data_source(:relational,ds_request) do
    Metadata.add(:dv_data_sources,String.downcase(ds_request.data_source),
    %ODBCDataSource{
      data_source: ds_request.data_source,
      type: ds_request.type,
      version: ds_request.version,
      hostname: ds_request.hostname,
      database: ds_request.database,
      # Only Kerberos is supported for :relational data sources
      auth: %DataSourceKerberosAuth{
      spn: ds_request.auth["spn"]
      }
      })
  end
  defp add_data_source(:web_api,ds_request) do
    Metadata.add(:dv_data_sources,String.downcase(ds_request.data_source),
    %WebAPIDataSource{
      data_source: ds_request.data_source,
      type: ds_request.type,
      version: ds_request.version,
      url: ds_request.url,
      # Only Kerberos is supported for :web_api data sources
      auth: %DataSourceKerberosAuth{
      spn: ds_request.auth["spn"]
      },
      # endpoint_mappings are converted to `WebAPIEndPointMapping`
      endpoint_mappings: Enum.reduce(ds_request.endpoint_mappings,%{},fn {key,mapping},acc -> Map.put(acc,key,%WebAPIEndpointMapping{uri: mapping["uri"],result_path: mapping["result_path"]}) end)
      }
      )
  end
  # :file data sources do NOT support authentication
  defp add_data_source(:file,ds_request) do
    Metadata.add(:dv_data_sources,String.downcase(ds_request.data_source),
    %FileDataSource{
      data_source: ds_request.data_source,
      type: ds_request.type,
      version: ds_request.version,
      path: ds_request.path,
      result_path: ds_request.result_path,
      field_separator: ds_request.field_separator
    }
    )
  end
  # Update calls wrap the equivalent add call - this is because `Metadata.backend` does the same thing for both.
  defp update_data_source(type,ds_request) do
    add_data_source(type,ds_request)
  end
  defp delete_data_source(ds_request) do
    Metadata.delete(:dv_data_sources,String.downcase(ds_request.data_source))
  end
  @doc """
  Get data source by `ds_name`.
  """
  def get_data_source(ds_name) do
    Metadata.get(:dv_data_sources,String.downcase(ds_name))
  end
  @doc """
  Get all data sources.
  """
  def get_all_data_sources() do
    Metadata.get_all(:dv_data_sources)
  end
  defp add_model(model_request) do
    Metadata.add(:dv_models,String.downcase(model_request.model),
    %VirtualModel{
      model: model_request.model,
      query: model_request.query
    }
    )
  end
  defp update_model(model_request) do
    add_model(model_request)
  end
  defp delete_model(model_request) do
    Metadata.delete(:dv_models,String.downcase(model_request.model))
  end
  @doc """
  Get model by `model_name`.
  """
  def get_model(model_name) do
    Metadata.get(:dv_models,String.downcase(model_name))
  end
  @doc """
  Get all models.
  """
  def get_all_models() do
    Metadata.get_all(:dv_models)
  end
  defp add_endpoint(endpoint_request) do
    Metadata.add(:dv_endpoints,String.downcase(endpoint_request.endpoint),
    %VirtualEndpoint{
      endpoint: endpoint_request.endpoint,
      model: endpoint_request.model
    }
    )
  end
  defp update_endpoint(endpoint_request) do
    add_endpoint(endpoint_request)
  end
  defp delete_endpoint(endpoint_request) do
    Metadata.delete(:dv_endpoints,String.downcase(endpoint_request.endpoint))
  end
  @doc """
  Get endpoint by `endpoint_name`.
  """
  def get_endpoint(endpoint_name) do
    Metadata.get(:dv_endpoints,String.downcase(endpoint_name))
  end
  @doc """
  Get all endpoints.
  """
  def get_all_endpoints() do
    Metadata.get_all(:dv_endpoints)
  end
  @doc """
  Retrieves and formats all query plan steps of a given `type`. Wraps `QP.get_query_plan_entries_for_type/1`.
  """
  def get_query_plan_entries_for_type(type \\ :select) do
    QP.get_query_plan_entries_for_type(type)
  end
  @doc """
  Retrieves and formats the query plan for `request_id`. Wraps `QP.get_query_plan/1`.
  """
  def get_query_plan(request_id) do
    QP.get_query_plan(request_id)
  end
  defp add_request(request_id,request) do
    :ets.insert(:requests,{request_id,request})
  end
  defp update_request(request_id,request) do
    add_request(request_id,request)
  end
  defp add_result_set(request_id,result_set_file) do
    Metadata.add(:dv_result_sets,request_id,result_set_file)
  end
  defp rm_result_set_file(result_set_file) do
    case LogUtil.inspect(File.rm(result_set_file),label: "rm status for #{result_set_file}") do
      :ok -> :ok
      {:error,:enoent} -> :ok # Ignore if already removed
      {:error,error} -> throw("Error removing result set file #{result_set_file}: #{error}")
    end
  end
  defp get_result_set(request_id) do
    case Metadata.get(:dv_result_sets,request_id) do
      {:error,_msg} -> {:error,"Result set for Request ID #{request_id} not found!"}
      {:ok,result_set_file} -> {:ok,result_set_file}
    end
  end
  defp purge_result_sets(expire_mins \\ :all)
  defp purge_result_sets(:all) do
    LogUtil.info("Purging all result sets...")
    Metadata.get_all(:dv_result_sets) |> Enum.each(fn {_request_id,result_set_file} ->
      if result_set_file do
        LogUtil.info("Purging #{result_set_file}")
        rm_result_set_file(result_set_file)
      end
    end)
    Metadata.delete_all(:dv_result_sets)
  end
  defp purge_result_sets(expire_mins) do
    current_time = DateTime.now!("Etc/UTC")
    Enum.filter(get_all_requests(),fn {request_id,request} ->
      if request.status == :FAILED or request.end_time == nil do
        false
      else
        time_diff = round(DateTime.diff(current_time,request.end_time) / 60)
        purge = time_diff >= expire_mins
        if purge do LogUtil.debug("Will purge #{request_id} (age: #{expire_mins} mins)") end
        purge
      end
  end) |> Enum.each(fn {request_id,request} ->
    update_request(request_id,%{request|expired: true,error: "Result set has expired."})
    case Metadata.get(:dv_result_sets,request_id) do
      {:ok,result_set_file} ->
        LogUtil.log("Purging #{result_set_file}")
        rm_result_set_file(result_set_file)
      {:error,_msg} -> :ok # Ignore if already removed
    end
    Metadata.delete(:dv_result_sets,request_id)
    LogUtil.info("Request #{request_id} marked as expired...")
  end)
  end
  @doc """
  Get request by `request_id`. Does NOT pull the associated `:result_set`.
  """
  def get_request(request_id) do
    case :ets.lookup(:requests,request_id) do
      [] -> {:error,"Request ID #{request_id} not found!"}
      [{_request_id,request}] -> {:ok,request}
    end
  end
  @doc """
  Get all requests. Does NOT pull the associated `:result_set`s.
  """
  def get_all_requests() do
    :ets.tab2list(:requests) |> Enum.into(%{})
  end
  @doc """
  Handlers for async callbacks from query operations.

  Performs `DV.Request` updates as required.
  """
  @impl true
  def handle_info({task_ref,{:completed,{status,result_set_file,%{request_id: request_id}}}}, state) do
    Process.demonitor(task_ref,[:flush])
    {:ok,request} = get_request(request_id)
    request = if status == :ok do
      LogUtil.info("request_id #{request_id} completed successfully!")
      add_result_set(request_id,result_set_file)
      struct(request,%{status: :COMPLETED,end_time: DateTime.now!("Etc/UTC")})
    else
      LogUtil.error("request_id #{request_id} failed: #{result_set_file}!")
      struct(request,%{status: :FAILED,end_time: DateTime.now!("Etc/UTC"),error: result_set_file})
    end
    update_request(request_id,request)
    {:noreply,state}
  end
  @impl true
  def handle_info({:purge_old_results,result_set_expiry},state) do
    LogUtil.info("Purging old results...")
    purge_result_sets(result_set_expiry)
    LogUtil.info("Old results expired.")
    Process.send_after(self(),{:purge_old_results,result_set_expiry},result_set_expiry * 1000)
    {:noreply,state}
  end
  # No other handle_info callbacks are used currently
  @impl true
  def handle_info({:DOWN,_ref,_,_,_reason},state) do
    {:noreply,state}
  end
  def handle_info(_msg,state) do
    {:noreply,state}
  end
  # Converts an arbitrary map to a struct
  # Downcases and converts string keys to atoms
  # If called recursively, converts a nested map to a nested struct.
  defp map_to_struct(struct,map,recurse \\ false) do
    Enum.reduce(map,struct(struct),fn {key,val},acc ->
      atom_key = String.to_existing_atom(String.downcase(key))
      case Map.has_key?(acc,atom_key) do
        true -> %{acc|atom_key => if recurse and is_map(val) do map_to_struct(Map.get(acc,atom_key),val) else val end}
        false -> acc
      end
    end
    )
  end
  # handle functions all essentially work the same way:
  #   - Convert the incoming payload to the action specific struct
  #   - If applicable, uses `Vex` to validate the struct
  #   - Reply with either a successful payload, or a wrapped error
  #   - For add/update operations, the reply will be a the updated resource definition
  defp handle({{:model,:add},params},_from,state) do
    model_request = map_to_struct(DV.Requests.Model.Add,params)
    case Vex.valid?(model_request) do
      true -> add_model(model_request)
      {:reply,get_model(model_request.model),state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(model_request)}},state}
    end
  end
  defp handle({{:endpoint,:add},params},_from,state) do
    endpoint_request = map_to_struct(DV.Requests.Endpoint.Add,params)
    case Vex.valid?(endpoint_request) do
      true -> add_endpoint(endpoint_request)
      {:reply,get_endpoint(endpoint_request.endpoint),state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(endpoint_request)}},state}
    end
  end
  defp handle({{:acl,:get_all},nil},_from,state) do
    {:reply,{:ok,get_all_acls() |> Enum.into([])},state}
  end
  defp handle({{:data_source,:add},params},_from,state) do
    # Yes, the below validation logic is a hack
    case LogUtil.inspect(DataSources.get_connector_settings(params["type"],params["version"]),label: "get_connector_settings") do
      {:ok,connector} ->
          ds_class = connector.class
          with {:ok,struct_name} <- ds_class_to_struct(:add,ds_class) do
            ds_request = map_to_struct(struct_name,params)
            case Vex.valid?(ds_request) do
              true ->
                # If this is a `:file` data source, trigger extended validation of the file specific properties
                validate_file = if connector.class == :file do validate_file_props(params,connector) else :ok end
                case validate_file do
                  :ok -> add_data_source(ds_class,ds_request)
                    {:reply,get_data_source(ds_request.data_source),state}
                  {:error,msgs} -> {:reply,{:error,:validation_error,Map.new(msgs)},state}
                end
              false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(ds_request)}},state}
            end
          else
            {:error,msg} -> {:reply,{:error,:fatal_error,msg},state}
          end
      {:error,_msg} ->
        msg = ["Data Source connector does not exist."]
        {:reply,{:error,:validation_error,%{"type" => msg,"version" => msg}},state}
    end
  end
  defp handle({{:model,:update},params},_from,state) do
    model_request = map_to_struct(DV.Requests.Model.Update,params)
    case Vex.valid?(model_request) do
      true -> update_model(model_request)
      {:reply,get_model(model_request.model),state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(model_request)}},state}
    end
  end
  defp handle({{:endpoint,:update},params},_from,state) do
    endpoint_request = map_to_struct(DV.Requests.Endpoint.Update,params)
    case Vex.valid?(endpoint_request) do
      true -> update_endpoint(endpoint_request)
      {:reply,get_endpoint(endpoint_request.endpoint),state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(endpoint_request)}},state}
    end
  end
  defp handle({{:data_source,:update},params},_from,state) do
    # Yes, the below validation logic is a hack
    with {:ok,ds_props} <- LogUtil.inspect(get_data_source(params["data_source"]),label: "get_data_source") do
      with {:ok,struct_name} <- LogUtil.inspect(ds_class_to_struct(:update,ds_props._class),label: "ds_class_to_struct") do
        ds_request = LogUtil.inspect(map_to_struct(struct_name,params),label: "map_to_struct")
        case Vex.valid?(ds_request) do
          true ->
            validate_file = case ds_props._class do
              :file ->
                # If this is a `:file` data source, trigger extended validation of the file specific properties
                {:ok,connector} = DataSources.get_connector_settings(ds_props.type,ds_props.version)
                  validate_file_props(params,connector)
              _ -> :ok
            end
            case validate_file do
              {:error,msgs} -> {:reply,{:error,:validation_error,Map.new(msgs)},state}
              :ok ->
                update_data_source(ds_props._class,Map.merge(Map.from_struct(ds_props),Map.from_struct(ds_request)))
                {:reply,get_data_source(ds_request.data_source),state}
            end
          false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(ds_request)}},state}
        end
      else
        {:error,msg} -> {:reply,{:error,:fatal_error,msg},state}
      end
    else
      {:error,msg} -> {:reply,{:error,:fatal_error,msg},state}
    end
  end
  defp handle({{:acl,:update_all},params},_from,state) do
    acl_request = map_to_struct(DV.Requests.ACL.UpdateAll,params)
    case Vex.valid?(acl_request) do
      true -> update_all_acls(acl_request.acls)
      {:reply,{:ok,get_all_acls() |> Enum.into([])},state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(acl_request)}},state}
    end
  end
  defp handle({{:model,:delete},params},_from,state) do
    model_request = map_to_struct(DV.Requests.Model.Delete,params)
    case Vex.valid?(model_request) do
      true -> delete_model(model_request)
      {:reply,case get_model(model_request.model) do
        {:ok,_model} -> {:error,:delete_model_error,"Failed to delete model"}
        {:error,_msg} -> {:ok,"Deleted"}
      end,state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(model_request)}},state}
    end
  end
  defp handle({{:endpoint,:delete},params},_from,state) do
    endpoint_request = map_to_struct(DV.Requests.Endpoint.Delete,params)
    case Vex.valid?(endpoint_request) do
      true -> delete_endpoint(endpoint_request)
      {:reply,case get_endpoint(endpoint_request.endpoint) do
        {:ok,_endpoint} -> {:error,:delete_endpoint_error,"Failed to delete endpoint"}
        {:error,_msg} -> {:ok,"Deleted"}
      end,state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(endpoint_request)}},state}
    end
  end
  defp handle({{:data_source,:delete},params},_from,state) do
    ds_request = map_to_struct(DV.Requests.DataSource.Delete,params)
    case Vex.valid?(ds_request) do
      true -> delete_data_source(ds_request)
      {:reply,case get_data_source(ds_request.data_source) do
        {:ok,_endpoint} -> {:error,:delete_data_source_error,"Failed to delete data source"}
        {:error,_msg} -> {:ok,"Deleted"}
      end,state}
      false -> {:reply,{:error,:validation_error,%DV.Responses.VexResult{result: Vex.results(ds_request)}},state}
    end
  end
  defp handle({{:data_source,:get_all},nil},_from,state) do
    {:reply,{:ok,get_all_data_sources() |> Enum.into(%{})},state}
  end
  defp handle({{:data_source,:get},ds_name},_from,state) do
    {:reply,wrap_get_result(get_data_source(ds_name)),state}
  end
  defp handle({{:model,:get_all},nil},_from,state) do
    {:reply,{:ok,get_all_models() |> Enum.into(%{})},state}
  end
  defp handle({{:model,:get},model_name},_from,state) do
    {:reply,wrap_get_result(get_model(model_name)),state}
  end
  defp handle({{:endpoint,:get_all},nil},_from,state) do
    {:reply,{:ok,get_all_endpoints() |> Enum.into(%{})},state}
  end
  defp handle({{:endpoint,:get},endpoint_name},_from,state) do
    {:reply,wrap_get_result(get_endpoint(endpoint_name)),state}
  end
  defp handle({{:query_plan,:get_all},nil},_from,state) do
    {:reply,{:ok,get_query_plan_entries_for_type(:select)},state}
  end
  defp handle({{:query_plan,:get},request_id},_from,state) do
    {:reply,{:ok,get_query_plan(request_id)},state}
  end
  defp handle({{:request,:get},request_id},_from,state) do
    payload = wrap_get_result(get_request(request_id))
    {:reply,payload,state}
  end
  defp handle({{:request,:get_result},request_id},_from,state) do
    request_info = LogUtil.inspect(get_request(request_id),label: "get_result request_info")
    payload = case request_info do
      {:ok,%{status: :COMPLETED,expired: false}} ->
        wrap_get_result(get_result_set(request_id) |> LogUtil.inspect(label: "get_result_set"))
      _ -> {:error,:not_found,"Result set does not exist"}
    end
    {:reply,payload,state}
  end
  defp handle({{:request,:get_all},nil},_from,state) do
    {:reply,{:ok,get_all_requests()},state}
  end
  # These two handlers need the `request_context` for `spawn_query_mediator/4`.
  defp handle({{:endpoint,:run},endpoint},request_context,from,state) do
    case get_endpoint(endpoint) do
      {:ok,endpoint_cfg} ->
        # Endpoint exists, run the associated model
        LogUtil.debug("Endpoint Definition: #{inspect endpoint_cfg}")
        # Add the endpoint to the request context, so it can be included in `:poll_request`.
        request_context = Map.put(request_context,:endpoint,endpoint)
        run_model(endpoint_cfg.model,request_context,from,state)
      {:error,_msg} -> {:reply,{:error,:not_found,"Unknown Endpoint"},state}
    end
  end
  defp handle({{:query,:run},query_string},request_context,from,state) do
    # Add the query to the request context, so it can be included in `:poll_request`
    request_context = Map.put(request_context,:query,query_string)
    spawn_query_mediator({:query,query_string},request_context,from,state)
  end
  # Wraps the result of a `:get` operation
  # Translates an error into a `:not_found` to trigger a 404 error
  # Returns `:ok` tuples as-is
  defp wrap_get_result({:error,msg}) do
    {:error,:not_found,msg}
  end
  defp wrap_get_result({:ok,_payload} = result) do
    result
  end
  defp run_model(model,request_context,from,state) do
    LogUtil.debug("run_model: #{inspect model}")
    case get_model(model) do
      {:ok,model_cfg} ->
        # Model exists, add model and underlying query to request_context so it can be included in `:poll_request`
        request_context = Map.put(request_context,:model,model)
        request_context = Map.put(request_context,:query,model_cfg.query)
        LogUtil.log("Virtual model exists")
        spawn_query_mediator({:query,model_cfg.query},request_context,from,state)
      {:error,_msg} -> {:reply,{:error,:not_found,"Unknown Virtual Model"},state}
    end
  end
  @doc """
  Handles incoming API requests from other modules.

  Validates ACL based access for requesting user.

  Returns wrapped response payloads or errors.
  """
  @impl true
  def handle_call({{category,action} = request,params,%{username: username} = request_context},from,state) do
    with {:ok,_} <- AccessControl.check_access(category,
    case action do
      :get_result -> :get
      :get_all -> :get
      :update_all -> :update
      _ -> action
    end,username) do
      if action == :run do handle({request,params},request_context,from,state) else handle({request,params},from,state) end
    else
      {:error,msg} -> {:reply,{:error,:access_denied,msg},state}
    end
  end
  defp query_task(query_string,request_context) do
    LogUtil.info("validating query #{query_string}...")
    with {:ok,[{:parts,parsed_query}],_rest,_context,_line,_column} <- Parsec.sql(query_string) do
      LogUtil.inspect(parsed_query,label: "Pre-struct Parsed Query")
      case validate_data_sources(parsed_query) do
        {:ok} ->
          LogUtil.info("query validated, executing...")
          LogUtil.inspect(QueryEngine.parse(parsed_query,request_context),label: "Query Plan parse result")
        {:error,failed_data_sources} ->
          LogUtil.info("data source validation failed!")
          {:error,"query validation error: data source(s) do not exist: #{Enum.join(failed_data_sources,",")}",request_context}
      end
    else
      {:error,err,rest,_context,_line,_column} ->
        LogUtil.info("query parsing failed!")
      {:error,"query parse error: #{err} (remaining query segment: #{rest})",request_context}
    end
  end
  @doc """
  Validates data sources in segments of a parsed query containing resources.

  This is exposed to be available to `DV.ValidationUtils`.

  Returns `{:ok}` or `{:error,failed_data_sources}`.
  """
  def validate_data_sources(parts,failed_data_sources \\ [])
  # Covers QuerySegmentSelect and QuerySegmentJoin
  def validate_data_sources([%{resource: %QueryComponentResource{data_source: data_source}}|parts],failed_data_sources) do
    case DV.get_data_source(data_source) do
      {:ok,_ds_props} -> validate_data_sources(parts,failed_data_sources)
      {:error,_} -> validate_data_sources(parts,[data_source|failed_data_sources])
    end
  end
  # No need to validate non-resource segments
  def validate_data_sources([_part|parts],failed_data_sources) do
    validate_data_sources(parts,failed_data_sources)
  end
  def validate_data_sources([],failed_data_sources) do
    case failed_data_sources do
      [] -> {:ok}
      failed_data_sources -> {:error,failed_data_sources}
    end
  end
  defp spawn_query_mediator({:query,query_string},request_context,_from,state) do
    request_id = SharedUtil.gen_uuid()
    LogUtil.info("request_id #{request_id} started (context: #{inspect request_context}).")
    wrapped_request_context = struct(%QueryContext{request_id: request_id},request_context)
    LogUtil.debug("Spawning query mediator...")
    Task.Supervisor.async_nolink(DV.QMSupervisor,fn ->
      {msg,payload,request_context} = query_task(query_string,wrapped_request_context)
      {:completed,{msg,payload,request_context}}
      end)
    request = %{
      state: :IN_PROGRESS,
      start_time: DateTime.now!("Etc/UTC"),
    end_time: nil
    }
    request = struct(DV.Request,request)
    request = struct(request,request_context)
    add_request(request_id,request)
    LogUtil.debug("After query mediator spawn")
    {:reply,{:request_id,request_id},state}
  end
  # Extended validation for `:file` class data sources
  # Verifies the `:field_separator` or `:result_path`, as appropriate
  defp validate_file_props(ds_params,connector_props) do
    {_connector_module,connector_constants} = connector_props.connector
    result_type = Keyword.get(connector_constants,:result_type)
    case result_type do
      :csv ->
        cond do
          Map.has_key?(ds_params,"field_separator") and String.length(Map.get(ds_params,"field_separator")) == 0 ->
            {:error,[{"field_separator","Field separator must be at least one character."}]}
          true -> :ok
        end
      :json -> cond do
        Map.has_key?(ds_params,"result_path") and String.length(Map.get(ds_params,"result_path")) == 0 ->
          {:error,[{"result_path","Result path must be a JSONPath path of least one character."}]}
        true -> :ok
      end
    end
  end
  # Converts the `:class` of a Data Source connector into the appropriate struct for the action `struct_type`
  # e.g. If a request is submitted to add a REST data source, this function will return `{:ok,DV.Request.DataSource.AddWebAPI}`
  defp ds_class_to_struct(struct_type,class) do
    case class do
      :relational -> case struct_type do
        :add -> {:ok,DV.Requests.DataSource.AddRelational}
        :update -> {:ok,DV.Requests.DataSource.UpdateRelational}
        :delete -> {:ok,DV.Request.DataSource.Delete}
        _ -> {:error,"Invalid class request type #{Atom.to_string(struct_type)}"}
      end
      :web_api -> case struct_type do
        :add -> {:ok,DV.Requests.DataSource.AddWebAPI}
        :update -> {:ok,DV.Requests.DataSource.UpdateWebAPI}
        :delete -> {:ok,DV.Request.DataSource.Delete}
        _ -> {:error,"Invalid class request type #{Atom.to_string(struct_type)}"}
      end
      :file -> case struct_type do
        :add -> {:ok,DV.Requests.DataSource.AddFile}
        :update -> {:ok,DV.Requests.DataSource.UpdateFile}
        :delete -> {:ok,DV.Request.DataSource.Delete}
        _ -> {:error,"Invalid class request type #{Atom.to_string(struct_type)}"}
      end
      _ -> {:error,"Invalid data source class #{class}"}
    end
  end
  @impl true
  def terminate(_reason,_state) do
    :odbc.stop()
  end
end
