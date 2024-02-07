#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule LDAP do
  @moduledoc """
  Wrapper for erlang erldap library.

  Implements only the functionality necessary for the `AccessControl` related features (i.e. checking user LDAP group membership).
  """

  # This module attempts compliance with the text-based LDAP query standard: https://datatracker.ietf.org/doc/html/rfc4515

  @ldap_server_hostname String.to_charlist(Application.compile_env!(:DV,:ldap_server_hostname))
  @ldap_query_base Application.compile_env!(:DV,:ldap_query_base)
  defp result_to_map(search_result) do
    Map.new(search_result,
    fn {:eldap_entry,_key,val} ->
      val = Enum.reduce(val,%{},fn {key2,val2},acc ->
        converted_val = Enum.map(val2,fn val3 -> to_string(val3) end)
        str_key = to_string(key2)
        converted_val = if length(converted_val) < 2 and str_key != "memberOf" do
          to_string(converted_val)
        else
          converted_val
        end
        Map.put(acc,str_key,converted_val)
      end)
      {val["cn"],Map.drop(val,["cn"])}
    end
    )
  end
  defp ldap_query(query) do
    with {:ok,conn} <- :eldap.open([@ldap_server_hostname]) do
      with {:ok,filter} <- EldapStringFilters.parse(query) do
        with {:ok,{:eldap_search_result,results,_,_}} <- :eldap.search(conn,[{:base, @ldap_query_base},{:filter,filter}]) do
          :eldap.close(conn)
          {:ok,result_to_map(results)}
        else
          {:error,msg} -> {:error,"Error executing LDAP query: #{inspect msg}"}
        end
      else
        {:error,msg} -> {:error,"Error parsing LDAP query: #{inspect msg}"}
      end
    else
      {:error,msg} -> {:error,"Error connecting to LDAP server: #{inspect msg}"}
    end
  end
  # Converts LDAP errors into either an {:ok,_} or {:error,_} tuple
  defp wrap_result(ldap_result,error_message,desired_key \\ nil)
  defp wrap_result({:error,error},_error,_key) do
    {:error,error}
  end
  defp wrap_result({:ok,result},error,nil) when map_size(result) == 0 do
    {:error,error}
  end
  defp wrap_result({:ok,result},_error,nil) do
    {:ok,result}
  end
  defp wrap_result({:ok,result},error,key) do
    wrap_result({:ok,Map.get(result,key,%{})},error)
  end
  @doc """
  Queries user record.
  """
  def get_user(username) do
    ldap_query("(cn=#{username})") |> wrap_result("User not found",username)
  end
  @doc """
  Queries user group memberships.
  """
  def get_user_groups(username) do
    ldap_query("(member=uid=#{username},ou=people,#{@ldap_query_base})") |> wrap_result("User groups not found")
  end
  @doc """
  Queries all groups.
  """
  def get_groups() do
    ldap_query("(objectClass=groupOfNames)") |> wrap_result("Groups not found")
  end
  @doc """
  Queries a specific group. Accepts either a full LDAP query, or a bare group name.
  """
  def get_group(group_name) do
    if String.starts_with?(group_name,"cn=") do ldap_query("(#{group_name})") else ldap_query("(cn=#{group_name},ou=groups,#{@ldap_query_base})") end |> wrap_result("Group not found",group_name)
  end
end

defmodule PermACL do
  @moduledoc """
  Represents an Access Control List (ACL) entry. Exact semantic meaning will vary based on associated API, but, generally:

  * `:add` - add new record of type (e.g. create a new Data Source)
  * `:update` - Update existing record of type (e.g. update existing Data Source)
  * `:delete` - Delete existing record of type (e.g. delete existing Data Source)
  * `:get` - List all records of type, or details of an individual record (e.g. list all defined Data Sources, get individual Data Source properties)
  * `:run` - Execute the action associated with the record or API call (e.g. run an Endpoint, or an ad-hoc Query)

  """
  @derive {Jason.Encoder,only: [:add,:update,:delete,:get,:run]}
  defstruct [add: false,update: false,delete: false,get: false,run: false]
end
defmodule PermACLGroup do
  @moduledoc """
  Combines Access Control Lists (ACLs) into a collection of privlieges for a specific user or group.

  `:disabled` indicates that _ALL_ access for the user or group is prevented (overrides individual ACLs).

  All other fields are `PermACL` entries for the respective API categories.

  """
  @derive {Jason.Encoder,only: [:disabled,:data_source,:endpoint,:model,:query,:acl,:query_plan,:request]}
  defstruct [disabled: false,data_source: %PermACL{},endpoint: %PermACL{},model: %PermACL{},query: %PermACL{},acl: %PermACL{},query_plan: %PermACL{},request: %PermACL{}]
end

defmodule PermIdent do
  @moduledoc """
  Represents a user or group identity.

  Definitions:

  * `:type`: either `:user` or `:group`.
  * `:subtype`: currently always `:ldap`.
  * `:id`: the textual identifier for the identity (i.e. the username or group name).
  """
  @enforce_keys [:type,:subtype,:id]
  @derive {Jason.Encoder,only: [:type,:subtype,:id]}
  defstruct [:type,:subtype,:id]
end

defmodule PermPair do
  @moduledoc """
  Represents an association between a `PermIdent` and an `PermACLGroup`.

  This is used as the primary representation of privliege information within the system.

  Definitions:

  * `:ident`: `PermIdent` of the user/group.
  * `:acls`: `PermACLGroup` of the user/group.
  """
  @enforce_keys [:ident,:acls]
  @derive {Jason.Encoder,only: [:ident,:acls]}
  defstruct [:ident,acls: %PermACLGroup{}]
end

defmodule AccessControl do
  @moduledoc """
  Provides functionality required for the system to verify LDAP based user authorization.

  This module presumes that the user has already been authenticated (i.e. by Kerberos).
  """
  defp check_acls(category,action,acls,result \\ false)
  defp check_acls(_category,_action,[],false) do
    {:error,"Access Denied"}
  end
  defp check_acls(_category,_action,_,true) do
    {:ok,true}
  end
  defp check_acls(category,action,[acl|acls],result) do
    case acl do
      %PermACLGroup{} ->
        check = get_in(acl,[Access.key(category),Access.key(action)])
        check_acls(category,action,acls,if not acl.disabled and check do check else result end)
      nil ->
        check_acls(category,action,acls,result)
    end
  end
  @doc """
  Checks user access to execute a specific API call.

  * Verifies `username` exists in LDAP
  * Verifies user/group access is not disabled
  * Verifies at least one ACL permits the requested action

  """
  def check_access(category,action,username) do
    ldap_search = LogUtil.inspect(LDAP.get_user(username),label: "get_user")
    with {:ok,user_ldap_result} <- ldap_search do
      LogUtil.debug("User exists, checking ACL")
      {:ok,user_acl} = LogUtil.inspect(Metadata.get_or_default(:dv_user_acls,{:ldap,username}),label: "Get ACLs")
      with {:ok,_} <- check_acls(category,action,[user_acl]) do
        LogUtil.debug("Access permitted by user ACL")
        {:ok,true}
      else
          _ -> LogUtil.debug("User not permitted by user ACL")
          permissioned_groups = Enum.reduce(Metadata.get_all(:dv_group_acls),[],fn {{:ldap,group_name},acl},acc ->
              LogUtil.inspect(acl,label: "acl")
              case check_acls(category,action,[acl]) do
                {:ok,_} -> [group_name|acc]
                _ -> acc
              end
          end) |> LogUtil.inspect(label: "Permissioned groups")
            user_ldap_groups = Enum.reduce(Map.get(user_ldap_result,"memberOf",[]),[],
            fn group_cn,acc->
                    group_name = String.split(group_cn,",") |> Enum.find(fn str -> String.starts_with?(str,"cn=") end) |> String.replace("cn=","")
                    [String.downcase(group_name)|acc]
            end
            ) |> LogUtil.inspect(label: "User LDAP Groups")
            cond do
              (length(user_ldap_groups) > 0 and Enum.find(permissioned_groups,fn group_name -> Enum.member?(user_ldap_groups,group_name) end)) ->
                LogUtil.debug("User found in LDAP group")
                {:ok,true}
              true ->
                LogUtil.debug("Not found in LDAP group")
                {:error,"Access Denied"}
            end
      end
    else
      {:error,_msg} ->
        LogUtil.debug("User doesn't exist in LDAP")
        {:error,"Access Denied"}
    end
  end
end
