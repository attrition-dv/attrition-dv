#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QPStep do
  @moduledoc """
  Represents a step in a query plan tracked by `QP`.

  Definitions:

  * `:start_time`: Start time of the step in `QueryEngine`.
  * `:end_time`: Etart time of the step in `QueryEngine`.
  * `:type`: Type of the step, used for standardized output.
  * `:status`: Status of the step (`:started`,`:completed`,`:failed`)
  * `:details`: `Map` of details for the step. Arbitrary.
  * `:indent`: Level of indentation of the step, used for arbitrary nesting in output.
  * `:summary`: Populated during retrieval. Used by `QP` to store the result of generating `:type`-specific standardized output.
  """
  @derive {Jason.Encoder,only: [:start_time,:end_time,:type,:status,:details,:indent,:duration,:summary]}
  defstruct [:start_time,:end_time,:type,:status,details: %{},indent: 1,duration: 0,summary: ""]
end
defmodule QP do
  @moduledoc """
  Manages query plan tracking for requests:
  * Owns an ETS table to store query plans
  * Contains functions for manipulation and retrival of query plans
  """
  use GenServer
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__,state,name: __MODULE__)
  end
  @impl true
  def init(_init_arg) do
    :ets.new(:query_plans,[:set,:public,:named_table])
    {:ok,%{},:infinity}
  end
  defp get_timestamp() do
    {:ok,ts} = DateTime.now("Etc/UTC")
    ts
  end
  @doc """
  Begin a new query plan step step of `type` for `request_id`. Accepts optional `indent` level and step specific `details`.

  Returns an (INTERNAL only) unique identifier for the step.
  """
  def start_step(request_id,type,indent \\ 1,details \\ %{}) do
    start_timestamp = get_timestamp()
    ident = {request_id,indent,start_timestamp,type}
    :ets.insert(:query_plans,{ident,%QPStep{start_time: start_timestamp,type: type,status: :started,indent: indent,details: details}})
    ident
  end
  @doc """
  Ends the query plan step identified by `ident`. Sets the step to `status`, and merges additional `details` with any provided during `start_step/4`.
  """
  def end_step({_request_id,_indent,start_timestamp,_type} = ident,status \\ :completed,details \\ %{}) do
    case :ets.lookup_element(:query_plans,ident,2) do
      %QPStep{} = step ->
        end_timestamp = get_timestamp()
        new_step = Map.put(step,:end_time,end_timestamp)
        |> Map.put(:duration,DateTime.diff(end_timestamp,start_timestamp,:nanosecond))
        |> Map.put(:status,status)
        |> Map.put(:details,Map.merge(Map.get(step,:details),details))
        :ets.insert(:query_plans,{ident,new_step})
        ident
    end
  end
  @doc """
  Retrieves and formats the query plan for `request_id`.
  """
  def get_query_plan(request_id) do
    :ets.match_object(:query_plans,{{request_id,:_,:_,:_},:_}) |> format_query_plan_entries |> Enum.sort(&(case Date.compare(&1.start_time,&2.start_time) do
      :eq -> true
      :lt -> true
      _ -> false
    end))
  end
  @doc """
  Retrieves and formats all query plan steps of a given `type`. Intended to be used for e.g. UI population.
  """
  def get_query_plan_entries_for_type(type \\ :select) do
    :ets.match_object(:query_plans,{{:_,:_,:_,type},:_})
    |> LogUtil.inspect(label: "Matches for type")
    |> Enum.map(fn {{request_id,_indent,_start_timestamp,_a_type},entry} -> {request_id,format_query_plan_step(entry) |> LogUtil.inspect(label: "Formatted step")} end)
    |> Enum.into(%{})
    |> LogUtil.inspect(label: "Mapped entries for type")
  end
  @doc """
  Retrieves and formats steps of a specific `type` for the `request_id`.
  """
  def get_query_plan_entry_for_type(request_id,type \\ :select) do
    {_key,step} = :ets.match_object(:query_plans,{{request_id,:_,:_,type},:_})
    format_query_plan_step(step)
  end
  defp format_query_plan_entries(entries) do
   entries |> Enum.sort(fn {{_a_request_id,a_indent,a_start_timestamp,_a_type},_a_step},{{_b_request_id,b_indent,b_start_timestamp,_b_type},_b_step} ->
      ts_lt_equal = a_start_timestamp <= b_start_timestamp
      indent_lt_equal = a_indent <= b_indent
      cond do
        (not ts_lt_equal) -> false
        (ts_lt_equal and indent_lt_equal) -> true
        (ts_lt_equal and not indent_lt_equal) -> false
      end
    end) |> LogUtil.inspect(label: "Sorted query plan entries")
    |>
    Enum.map(fn {_key,step} ->
      format_query_plan_step(step)
    end) |> LogUtil.inspect(label: "Mapped query plan entries")
  end
  defp format_query_plan_step(step) do
    Map.put(step,:summary,get_type_translation(step.type))
  end
  @doc """
  Returns the `:summary` translation for a given `:type`.
  """
  def get_type_translation(key) do
     translations = get_type_translations()
     Map.get(translations,key)
  end
  @doc """
  Returns a map of query plan step `:type`s to their `:summary`.
  """
  def get_type_translations() do
    %{
      :apply_aggregate_funcs => "Apply aggregate platform functions",
      :apply_scalar_funcs => "Apply scalar platform functions",
      :classify_funcs => "Classify platform functions",
      :extract_fields => "Extract query attributes",
      :extract_func_fields => "...from function calls",
      :extract_segment_fields => "...from query segments",
      :extract_select_fields => "...from base SELECT query",
      :filter_result => "Filter result set",
      :finalize_result => "Finalize and cleanup result set",
      :get_segment_streams => "Fetch data from data source(s)",
      :group_result => "GROUP result set",
      :limit_result => "LIMIT result set",
      :order_result => "ORDER result set",
      :prepare_segments => "Pre-process query segments",
      :pre_validate => "Initial query validation",
      :process_join => "...process join",
      :process_joins => "Process JOIN segments",
      :process_no_join => "Process standalone SELECT (no-JOINs) query",
      :segment_stream => "...fetch from data source...",
      :select => "Virtual model SELECT query",
      :validate_group_by => "Validate GROUP criteria",
    }
  end
end
