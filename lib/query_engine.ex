#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryEngine do
  @moduledoc """

  The query engine.

  Processes parsed queries from `Parsec` to perform required query operations.

  This the primary module for the core platform functionality.

  Primary Responsibilities:

    * Validating query instructions
    * Extracting fields and collating them by data source
    * Categorizing query functions according to handling requirements (e.g. platform-level execution or not)
    * Retrieving records from data sources
    * `JOIN`ing and filtering records
    * `GROUP BY`, `ORDER BY`, and `LIMIT` operations

  In general, changes made here will require an equivalent change in `Parsec`.

  """

  # Pre-validation - currently, this is just making sure the query starts with `SELECT`, which should always be true
  defp pre_validate(segments,validated \\ [])
  defp pre_validate([segment|segments],[] = validated) do
    case segment do
      %QuerySegmentSELECT{} -> pre_validate(segments,[segment|validated])
      _ -> {:error,"First segment MUST be a SELECT"}
    end
  end
  defp pre_validate(_segments,_validated) do
    {:ok}
  end
  # No GROUP BY clause
  # Validate that there are either no aggregate functions, or just an aggregate function
  defp validate_group_by(nil,extracted_fields,platform_funcs) do
    has_aggregate = Enum.any?(platform_funcs,fn func ->
      case func do
        %{type: :aggregate} -> true
        _ -> false
      end
    end)
    has_remaining = Enum.any?(extracted_fields,fn %{_drop: drop} -> not drop end)
    case has_aggregate do
      false -> {:ok}
      true -> case has_remaining do
        true -> {:error,"Using aggregate functions without GROUP BY, all fields must be used as function parameters."}
        false -> {:ok}
      end
    end
  end
  # Validates a `GROUP BY` clause
  # This makes sure that the `SELECT`ed fields are either aggregated, or part of the grouping
  defp validate_group_by(%{attr: group_by_attr},extracted_fields,platform_funcs) do
    attr_cmp_list = case group_by_attr do
      %QueryComponentAliasPlaceholder{alias: alias} -> [{nil,nil,alias}]
      %QueryComponentField{src: ds_alias,field: field} -> [{ds_alias,field,nil}]
    end
    attr_cmp_list = Enum.reduce(platform_funcs,attr_cmp_list,fn func,acc ->
      case func do
        %{type: :aggregate,params: params} -> Enum.reduce(params,acc,fn param,acc ->
          case param do
            %QueryComponentAllFields{src: ds_alias} -> [{ds_alias,nil,nil}|acc]
            %QueryComponentFuncField{src: ds_alias,field: field} -> [{ds_alias,field,nil}|acc]
            _ -> acc
          end
        end)
        _ -> acc
      end
    end) |> LogUtil.inspect(label: "attr_cmp_list")
    remaining_fields = Enum.reject(extracted_fields,fn cmp_field ->
      case cmp_field do
        %{_drop: true} -> true
        %QueryComponentAllFields{src: ds_alias} -> Enum.find_value(attr_cmp_list,false,fn search_field ->
        case search_field do
          {^ds_alias,nil,nil} -> true
          _ -> false
        end
        end)
        %QueryComponentField{src: ds_alias,field: field,alias: alias} ->
          Enum.find_value(attr_cmp_list,false,fn search_field ->
            case search_field do
              {^ds_alias,^field,nil} -> true
              {_,_,s_alias} -> if s_alias != nil and s_alias == alias do true else false end
              _ -> false
            end |> LogUtil.inspect(label: "Group by check for #{ds_alias}.#{field} (#{alias}) vs #{inspect search_field}")
          end)
       _ -> true

      end
    end) |> LogUtil.inspect(label: "Remaining Fields")
    if Enum.empty?(remaining_fields) do {:ok} else {:error,"When using GROUP BY, all fields must be either used for GROUP BY, or in an aggregate function"} end
  end
  # These functions handle the various query component structs, and add fields to the lists to be processed
  # This catches fields everywhere in the query that may be needed for processing
  # Fields that weren't explicitly selected have `_drop` set, for later purging
  # Recursively handles function calls, and also handles e.g. `*` and string literals.
  defp insert_clause_field(%QueryComponentAliasPlaceholder{},fields,alias_map) do
    {:ok,fields,alias_map}
  end
  defp insert_clause_field(%QueryComponentFuncField{} = field_struct,fields,alias_map) do
    insert_clause_field(struct(QueryComponentField,Map.from_struct(field_struct)),fields,alias_map)
  end
  defp insert_clause_field(%QueryComponentAllFields{src: s_src} = field_struct,fields,alias_map) do
    field_already_exists = Enum.find(fields,fn f ->
      case f do
        %QueryComponentAllFields{src: src} -> src == s_src
        _ -> false
      end
    end)
    {:ok,if field_already_exists do fields else [%{field_struct|_drop: true}|fields] end,alias_map}
  end
  defp insert_clause_field(%QueryComponentField{src: s_src,field: s_field} = field_struct,fields,alias_map) do
    field_already_exists = Enum.find(fields,fn f ->
      case f do
        %{src: src,field: field,alias: f_alias} -> src == s_src and field == s_field and f_alias == nil
        _ -> false
      end
    end)
    {:ok,if field_already_exists do fields else [%{field_struct|_drop: true}|fields] end,alias_map}
  end
  defp insert_clause_field(%QueryComponentQuotedString{},fields,alias_map) do
    {:ok,fields,alias_map}
  end
  defp insert_clause_field(field,_fields,_alias_map) do
    {:error,"Invalid clause field #{inspect field}"}
  end
  defp clauses_to_fields([],fields,alias_map) do
    {:ok,fields,alias_map}
  end
  defp clauses_to_fields([%QueryComponentBinaryClause{p1: p1,p2: p2}|_clauses],fields,alias_map) do
    case insert_clause_field(p1,fields,alias_map) do
      {:ok,fields,alias_map} -> insert_clause_field(p2,fields,alias_map)
      {:error,_msg} = error -> error
    end
  end
  defp clauses_to_fields([clause|_clauses],_fields,_alias_map) do
    {:error,"Invalid clause #{inspect clause}"}
  end
  defp extract_param_fields([],fields,alias_map,resources) do
    {:ok,fields,alias_map,resources}
  end
  defp extract_param_fields([%{src: _p_src} = full_field|params],fields,alias_map,resources) do
    case insert_clause_field(full_field,fields,alias_map) do
      {:ok,fields,alias_map} -> extract_param_fields(params,fields,alias_map,resources)
      {:error,_msg} = error -> error
    end
  end
  defp extract_param_fields([%{}|params],fields,alias_map,resources) do
    extract_param_fields(params,fields,alias_map,resources)
  end
  defp extract_func_fields([],fields,alias_map,resources) do
    {:ok,fields,alias_map,resources}
  end
  defp extract_func_fields([%QueryComponentFunc{params: params}|funcs],fields,alias_map,resources) do
    case extract_param_fields(params,fields,alias_map,resources) do
      {:ok,fields,alias_map,resources} -> extract_func_fields(funcs,fields,alias_map,resources)
      {:error,_msg} = error -> error
    end
  end
  defp extract_func_fields([func|_funcs],_fields,_alias_map,_resources) do
    {:error,"Invalid function #{inspect func}"}
  end
  defp extract_segment_fields([],fields,alias_map,resources) do
    {:ok,fields,alias_map,resources}
  end
  defp extract_segment_fields([%QuerySegmentJOIN{clauses: clauses,resource: %QueryComponentResource{data_source: ds_source,src: ds_src,alias: ds_alias}}|segments],fields,alias_map,resources) do
    case clauses_to_fields(clauses,fields,alias_map) do
      {:ok,fields,alias_map} -> extract_segment_fields(segments,fields,alias_map,Map.put(resources,ds_alias,{ds_source,ds_src}))
      {:error,_message} = error -> error
    end
  end
  defp extract_segment_fields([%QuerySegmentFilter{clauses: clauses}|segments],fields,alias_map,resources) do
    case clauses_to_fields(clauses,fields,alias_map) do
      {:ok,fields,alias_map} -> extract_segment_fields(segments,fields,alias_map,resources)
      {:error,_message} = error -> error
    end
  end
  defp extract_segment_fields([%QuerySegmentGroupBy{attr: attr}|segments],fields,alias_map,resources) do
    case insert_clause_field(attr,fields,alias_map) do
      {:ok,fields,alias_map} -> extract_segment_fields(segments,fields,alias_map,resources)
      {:error,_msg} = error -> error
    end
  end
  defp extract_segment_fields([%QuerySegmentOrderBy{attr: attr}|segments],fields,alias_map,resources) do
    case insert_clause_field(attr,fields,alias_map) do
      {:ok,fields,alias_map} -> extract_segment_fields(segments,fields,alias_map,resources)
      {:error,_msg} = error -> error
    end
  end
  defp extract_segment_fields([%QuerySegmentLimit{}|segments],fields,alias_map,resources) do
    extract_segment_fields(segments,fields,alias_map,resources)
  end
  defp extract_segment_fields([segment|_segments],_fields,_field_map,_resources) do
    {:error,"Invalid segment #{inspect segment}"}
  end
  # When extracting fields from `SELECT`, also keeps a map of the field alias to it's actual underlying field (i.e. in `data_source.field AS alias`, mapping of alias -> data_source.field)
  defp extract_select_fields(%QuerySegmentSELECT{fields: fields,resource: %QueryComponentResource{data_source: ds_source,src: ds_src,alias: ds_alias}}) do
    {fields,funcs,aliases} = Enum.reduce(fields,{[],[],%{}},fn f,{field_acc,func_acc,alias_acc} ->
      case f do
        %{src: f_src, field: f_field, alias: f_alias} = full_field ->
          {[full_field|field_acc],func_acc,if f_alias == nil do alias_acc else Map.put(alias_acc,f_alias,{f_src,f_field}) end}
        %QueryComponentFunc{} = func ->
          {field_acc,[func|func_acc],alias_acc}
        %QueryComponentAllFields{} = all_fields ->
          {[all_fields|field_acc],func_acc,alias_acc}
          _ ->
            LogUtil.log("Unmatched select field #{inspect f}")
            {field_acc,func_acc,alias_acc}
      end
    end)
    {:ok,fields,funcs,aliases,Map.put(Map.new(),ds_alias,{ds_source,ds_src})}
  end
  # Processes functions used in the query to categorize them as platform or data source-level execution
  #   - Checks the function type (non-`:scalar` always go to platform)
  #   - Checks # of data sources involved (Any number other than 1 = to platform)
  #   - Tags platform functions as `_platform`, tags data source functions with the function translation function `_func`.
  defp classify_func(%QueryComponentFunc{type: func_type,params: func_params} = full_func,resources) do
    with false <- func_type == :aggregate do
      # Not an aggregate function, check for # of unique param sources
      params_with_src = Enum.filter(func_params,fn param -> Map.has_key?(param,:src) end) # Filtering out e.g. QueryComponentQuotedString
      uniq_src = params_with_src |> Enum.map(fn param -> param.src end) |> Enum.uniq()
      with true <- length(uniq_src) == 1 do
        # 1 unique source, check for data_source support
        ds_alias = hd(uniq_src)
        case Map.get(resources,ds_alias) do
          nil -> {:error,"Could not find data source #{inspect ds_alias}"}
          {ds_source,_ds_src} ->
            with {:ok,datasource_funcs} <- DataSources.get_ds_func_module(ds_source) do
              case datasource_funcs.check_func_support(full_func) do
                # check_func_support returned an error, force to platform
                {:error,_msg} -> {:ok,%{full_func|_platform: true}}
                # check_func_support returned func
                {:ok,func_ref} -> {:ok,%{full_func|src: ds_alias,_func: func_ref}}
              end
            else
              {:error,_msg} = error -> error
            end
        end
      else
        # Too few/many unique sources, force to platform
        _ -> {:ok,%{full_func|_platform: true}}
      end
    else
      # Aggregate function, force to platform
      _ -> {:ok,%{full_func|_platform: true}}
    end
  end
  defp classify_funcs(funcs,resources,local_funcs \\ [],platform_funcs \\ [])
  defp classify_funcs([],_resources,local_funcs,platform_funcs) do
    {:ok,local_funcs,platform_funcs}
  end
  defp classify_funcs([func|funcs],resources,local_funcs,platform_funcs) do
    case classify_func(func,resources) do
      {:ok,%{_platform: true} = new_func} -> classify_funcs(funcs,resources,local_funcs,[new_func|platform_funcs])
      {:ok,%{} = new_func} -> classify_funcs(funcs,resources,[new_func|local_funcs],platform_funcs)
      {:error,_msg} = error -> error
    end
  end
  # Prepares segments for data retrieval
  #   - Associates identified data source fields
  #   - Notes `JOIN` actions, if required
  # Only relevant for segments that actually retrieve data from the data sources (i.e. `SELECT` and `JOIN` operations)
  defp prepare_segments(segments,grouped_attrs,new_segments \\ [],post_gets \\ [])
  defp prepare_segments([],_grouped_attrs,new_segments,post_gets) do
    {:ok,new_segments,post_gets}
  end
  defp prepare_segments([%QuerySegmentLimit{} = full_segment|segments],grouped_attrs,new_segments,post_gets) do
    prepare_segments(segments,grouped_attrs,new_segments,[full_segment|post_gets])
  end
  defp prepare_segments([%QuerySegmentFilter{} = full_segment|segments],grouped_attrs,new_segments,post_gets) do
    prepare_segments(segments,grouped_attrs,new_segments,[full_segment|post_gets])
  end
  defp prepare_segments([%QuerySegmentOrderBy{} = full_segment|segments],grouped_attrs,new_segments,post_gets) do
    prepare_segments(segments,grouped_attrs,new_segments,[full_segment|post_gets])
  end
  defp prepare_segments([%QuerySegmentGroupBy{} = full_segment|segments],grouped_attrs,new_segments,post_gets) do
    prepare_segments(segments,grouped_attrs,new_segments,[full_segment|post_gets])
  end
  defp prepare_segments([%{resource: %QueryComponentResource{alias: ds_alias} = resource} = full_segment|segments],grouped_attrs,new_segments,post_gets) do
    case Map.get(grouped_attrs,ds_alias) do
      [_|_] = attr_list -> new_segment = %{
        resource: resource,
        fields: attr_list,
        merge_action: case full_segment do
          %QuerySegmentJOIN{type: join_type,clauses: clauses} -> %QueryFilterJoin{
            clauses: clauses,
            type: join_type
          }
        _ -> nil
        end
      }
      prepare_segments(segments,grouped_attrs,[new_segment|new_segments],post_gets)
      nil -> {:error,"No attributes found for #{ds_alias}"}
    end
  end
  defp prepare_segments([full_segment|_segments],_grouped_attrs,_new_segments,_post_gets) do
    {:error,"Invalid segment found during preparation: #{inspect full_segment}"}
  end
  # Retrieves data for prepared segments from the underlying data sources
  # Underlying data sources return streams, which are tracked in the segment map
  defp get_segment_streams(segments,request_context,new_segments \\ [])
  defp get_segment_streams([],_request_context,new_segments) do
    {:ok,new_segments}
  end
  defp get_segment_streams([%{resource: %QueryComponentResource{data_source: ds_source,src: ds_src,alias: ds_alias} = resource} = segment|segments],%{request_id: request_id} = request_context,new_segments) do
    segment_stream_qp_step = QP.start_step(request_id,:segment_stream,3,%{resource: Map.from_struct(resource)})
    with {:ok,{conn,ds_module}} <- connect(ds_source) do
      with {:ok,result} <- ds_module.get(conn,segment) do
        QP.end_step(segment_stream_qp_step)
        get_segment_streams(segments,request_context,[%{segment: segment, result: result}|new_segments]) |> LogUtil.inspect(label: "Segment stream for #{ds_source}.#{ds_src} (#{ds_alias})")
      else
        {:error,msg} ->
          QP.end_step(segment_stream_qp_step,:failed,%{error: msg})
          {:error,"Failed to get data for segment #{inspect segment}: #{msg}"}
      end
    else
      {:error,msg} ->
        QP.end_step(segment_stream_qp_step,:failed,%{error: msg})
        {:error,"Failed to connect to #{ds_source}: #{msg}"}
    end
  end
  # Cast comparison values
  # Boolean to not boolean - presume string comparison
  defp cast_comparison_values(val,cmp) when (is_boolean(cmp) and not is_boolean(val) or not is_boolean(cmp) and is_boolean(val)) do
#    LogUtil.debug("Comparing boolean as string #{inspect val}:#{inspect cmp}")
    {to_string(val),to_string(cmp)}
  end
  # Float to Binary (String) - attempt conversion
  defp cast_comparison_values(val,cmp) when is_binary(val) and is_float(cmp) do
 #   LogUtil.debug("Comparing string as float #{inspect val}:#{inspect cmp}")
    {String.to_float(val),cmp}
  end
  defp cast_comparison_values(val,cmp) when is_float(val) and is_binary(cmp) do
  #  LogUtil.debug("Comparing string as float #{inspect val}:#{inspect cmp}")
    {val,String.to_float(cmp)}
  end
  # Integer to Binary (String) - attempt conversion
  defp cast_comparison_values(val,cmp) when is_binary(val) and is_integer(cmp) do
  #  LogUtil.debug("Comparing string as integer #{inspect val}:#{inspect cmp}")
    {String.to_integer(val),cmp}
  end
  defp cast_comparison_values(val,cmp) when is_integer(val) and is_binary(cmp) do
  #  LogUtil.debug("Comparing string as integer #{inspect val}:#{inspect cmp}")
    {val,String.to_integer(cmp)}
  end
  # Other types - compare as-is - this covers e.g. Float to Integer
  defp cast_comparison_values(val,cmp) do
  #  LogUtil.debug("Comparing as-is #{inspect val}:#{inspect cmp}")
    {val,cmp}
  end
  defp binary_compare(v1,v2,operator) do
    {v1,v2} = try do
      cast_comparison_values(v1,v2)
    rescue
      e -> "Failed to cast values for comparison: #{Exception.message(e)}"
    end
    case operator do
      # =
      :equals -> v1 == v2
      # !=, <>
      :not_equals -> v1 != v2
      # <=
      :less_equals -> v1 <= v2
      # >=
      :greater_equals -> v1 >= v2
      # >
      :greater -> v1 > v2
      # <
      :less -> v1 < v2
      _ -> throw("Invalid comparison operator (#{operator})")
    end
  end
  # Stream processor that will throw if an error is encountered
  # Specifically used for processing the data from a base `SELECT` operation with no `JOIN`s.
  defp throwable_stream(stream) do
    stream |> Stream.each(fn row_result ->
      case row_result do
        {:error,err} -> throw(err)
        _ -> nil
      end
    end)
  end
  defp to_throwable_list(stream) do
    throwable_stream(stream) |> Enum.into([])
  end
  defp to_throwable_list(stream,reducer,acc) do
    throwable_stream(stream) |> Enum.reduce(acc,reducer)
  end
  # Based on the `JOIN` clause, determines which half of the `JOIN` is "left" or "right" for binary comparison purposes.
  defp choose_join_sides(%QueryComponentBinaryClause{p1: %{src: p1_ds_alias,field: p1_field},operator: _operator,p2: %{src: p2_ds_alias,field: p2_field}},base_ds_alias,join_ds_alias) do
    case base_ds_alias do
      ^p1_ds_alias -> if join_ds_alias == p2_ds_alias do {:ok,p1_ds_alias,p1_field,p2_ds_alias,p2_field} end
      ^p2_ds_alias -> if join_ds_alias == p1_ds_alias do {:ok,p2_ds_alias,p2_field,p1_ds_alias,p1_field} end
    end
  end
  # Reverses a binary comparison operator
  # Used for `RIGHT` and `INNER` joins
  defp reverse_operator(operator) do
    case operator do
      # =
      :equals -> :equals
      # !=
      :not_equals -> :not_equals
      # <=
      :less_equals -> :greater_equals
      # >=
      :greater_equals -> :less_equals
      # >
      :greater -> :less
      # <
      :less -> :greater
    end
  end
  defp do_find_indexes_for_alias(key_ds_alias,column_indexes) do
    Enum.reduce(column_indexes,[],fn {{dsa,_df,_fa},pos},acc -> if dsa == key_ds_alias do [pos|acc] else acc end end) |> Enum.reverse()
  end
  defp do_find_key_index({nil,nil,key_f_alias},column_indexes,_ignore_alias) do
    Enum.find_value(column_indexes,:not_found,fn {{_dsa,_df,fa},pos} -> if fa == key_f_alias do pos end end)
  end
  defp do_find_key_index({key_ds_alias,key_ds_field,_key_f_alias} = key,column_indexes,ignore_alias) do
    if ignore_alias do
      Enum.find_value(column_indexes,:not_found,fn {{dsa,df,_fa},pos} -> if dsa == key_ds_alias and key_ds_field == df do pos end end)
    else
      Map.get(column_indexes,key,:not_found)
    end
  end
  defp do_find_key_index({key_ds_alias,key_ds_field},column_indexes,ignore_alias) do
    do_find_key_index({key_ds_alias,key_ds_field,nil},column_indexes,ignore_alias)
  end
  defp find_key_index(key,column_indexes,ignore_alias)  do
    index = do_find_key_index(key,column_indexes,ignore_alias)
    if index == :not_found do
      throw("Key #{inspect key} not found")
    else
      index
    end
  end
  # Finds and returns the value corresponding to the specific aliased attribute.
  # At this point, the value should always exist, so uses `Enum.fetch!/2`.
  defp find_key_value({key_ds_alias,key_ds_field,key_f_alias} = search,row) do
    val = Enum.find_value(row,:not_found,fn col ->
      case col do
        {{dsa,dsf,fa},value} -> if key_ds_alias == dsa and key_ds_field == dsf and key_f_alias == fa do value else nil end
        _ -> nil
      end
    end)
    if val == :not_found do
          throw("Value not found for #{inspect search}")
    else
      val
    end
  end
  defp find_key_value({key_ds_alias,key_ds_field},row) do
    find_key_value({key_ds_alias,key_ds_field,nil},row)
  end
  defp find_key_value(key,row) do
    val = Enum.at(row,key,:not_found)
    if val == :not_found do
      throw("Value not found at index #{key}")
    else
      val
    end
  end
  # Actually joins the individual rows of a `JOIN` operation
  #   - Binary comparison using the required operator
  #   - build accumulator of row
  defp join_row(source_match,source_row,join_rows,join_key,operator,accum \\ [])
  defp join_row(_source_match,_source_row,[],_join_key,_operator,accum) do
    accum
  end
  defp join_row(source_match,source_row,[join_row|join_rows],join_key,operator,accum) do
    join_match = find_key_value(join_key,join_row)
    accum = if binary_compare(source_match,join_match,operator) do
      [source_row ++ join_row|accum]
    else
      accum
    end
    join_row(source_match,source_row,join_rows,join_key,operator,accum)
  end
  # `JOIN`s two result sets together
  #    Takes the following parameters:
  #   - the `JOIN` type (`:INNER`,`:RIGHT`,`:LEFT`)
  #   - Two sets of rows: `source_rows` and `join_rows`
  #   - Two attribute keys: `source_key` and `join_key`
  #   - Two "empty results": `source_empty`, `join_empty` (used for `LEFT` and `RIGHT` joins that show empty versions of the other side of the `JOIN`)
  #   - One binary comparison `operator`

  defp join_ds(type,source_rows,join_rows,source_key,join_key,source_empty,join_empty,operator)
  # `INNER JOIN` - essentially the unique matching subset of a `LEFT JOIN and a RIGHT JOIN` together,
  defp join_ds(:INNER,source_rows,join_rows,source_key,join_key,_source_empty,_join_empty,operator) do
    # `lhs_index` and `rhs_index` are assigned in `process_joins/3` to help deduplication
    # they are incremented indexes for each row from the source result sets (i.e. roughly equivalent to ROW_NUMBER()).
    # Result is de-duplicated by the tuple of `{lhs_index,rhs_index}`
    Enum.uniq_by(do_join_ds(source_rows,join_rows,source_key,join_key,operator) ++ do_join_ds(join_rows,source_rows,join_key,source_key,reverse_operator(operator)),fn row ->
      lhs_key = find_key_value({nil,nil,"lhs_index"},row)
      rhs_key = find_key_value({nil,nil,"rhs_index"},row)
      {lhs_key,rhs_key}
    end ) |> LogUtil.inspect(label: "Uniqued result set") |> Enum.reduce([],fn row,acc ->
      [Enum.reject(row,fn key ->
        case key do
          {{nil,nil,"lhs_index"},_val} -> true
          {{nil,nil,"rhs_index"},_val} -> true
          _ -> false
        end
      end)
      |acc]
    end
    )
  end
  # `RIGHT JOIN`
  defp join_ds(:RIGHT,source_rows,join_rows,source_key,join_key,source_empty,_join_empty,operator) do
    do_join_ds(join_rows,source_rows,join_key,source_key,reverse_operator(operator),source_empty)
  end
  # `LEFT JOIN`
  defp join_ds(:LEFT,source_rows,join_rows,source_key,join_key,_source_empty,join_empty,operator) do
    do_join_ds(source_rows,join_rows,source_key,join_key,operator,join_empty)
  end
  # Actually execute the JOIN operation
  defp do_join_ds(source_rows,join_rows,source_key,join_key,operator,append_empty \\ [],accum \\ [])
  defp do_join_ds([],_join_rows,_source_key,_join_key,_operator,_append_empty,accum) do
    accum
  end
  defp do_join_ds([source_row|source_rows],join_rows,source_key,join_key,operator,append_empty,accum) do
    LogUtil.log("source_row: #{inspect source_row}")
    source_match = find_key_value(source_key,source_row)
    join_row = join_row(source_match,source_row,join_rows,join_key,operator)
    accum = if length(join_row) == 0 do
      # CHECK THIS
       if length(append_empty) > 0 do
        tmp_empty = source_row ++ append_empty
        [tmp_empty|accum]
      else
        accum
      end
    else
      join_row ++ accum
    end |> LogUtil.inspect(label: "accum")
    do_join_ds(source_rows,join_rows,source_key,join_key,operator,append_empty,accum)
  end
  # Handles a base `SELECT` with no `JOIN` clause.
  defp process_joins(%{segment: %{merge_action: nil,resource: resource},result: base_result},[],%{request_id: request_id}) do
    process_join_qp_step = QP.start_step(request_id,:process_no_join,%{resource: Map.from_struct(resource)})
    with {:ok,base_stream,base_result} <- LogUtil.inspect(ResultSet.stream(base_result),label: "Result Stream") do
      try do
        {:ok,base_stream |> to_throwable_list,base_result.columns,base_result.column_indexes}
      catch
        e ->
          msg = "Error enumerating stream: #{e}"
          QP.end_step(process_join_qp_step,:failed,%{error: msg})
          {:error,msg}
      else
        ret ->
          QP.end_step(process_join_qp_step)
          ret
      end
    else
      {:error,msg} ->
        msg = "Error performing base SELECT: #{msg}"
        QP.end_step(process_join_qp_step,:failed,%{error: msg})
        {:error,msg}
    end
  end
  # Processes a `JOIN`ed query - only one `JOIN` supported currently
  #   - Processes both result set streams (TODO: make this more efficient for larger result sets)
  #   - Assigns `lhs_index` and `rhs_index`
  #   - Prepares "empty results"
  #   - Identifes source and join sides
  #   - Executes `JOIN` via `join_ds`
  defp process_joins(%{segment: %{merge_action: nil,resource: %{alias: base_ds_alias} = base_resource},result: base_result},[%{segment: %{resource: %{alias: join_ds_alias} = join_resource,merge_action: %QueryFilterJoin{type: join_type,clauses: [%QueryComponentBinaryClause{p1: %{src: _p1_ds_alias,field: _p1_field},operator: operator,p2: %{src: _p2_ds_alias,field: _p2_field}} = join_clause|_]}},result: join_result}|_],%{request_id: request_id}) when join_type == :LEFT or join_type == :INNER or join_type == :RIGHT do
    process_join_qp_step = QP.start_step(request_id,:process_join,%{resources: [join_resource,base_resource],join_type: join_type})
    try do
      with {:ok,lhs_stream,lhs_result} <- ResultSet.stream(base_result),{:ok,rhs_stream,rhs_result} <- ResultSet.stream(join_result) do
        lhs_columns = lhs_result.columns
        lhs_column_indexes = lhs_result.column_indexes
        rhs_columns = rhs_result.columns
        rhs_column_indexes = rhs_result.column_indexes
        default_reducer = fn row,{acc,_idx} -> {[row|acc],nil} end
        lhs_reducer = if join_type == :INNER do fn row,{acc,idx} -> {[[{{nil,nil,"lhs_index"},idx}|row]|acc],idx+1} end else default_reducer end
        rhs_reducer = if join_type == :INNER do fn row,{acc,idx} -> {[[{{nil,nil,"rhs_index"},idx}|row]|acc],idx+1} end else default_reducer end
        {lhs,_max_idx} = lhs_stream |> to_throwable_list(lhs_reducer,{[],0}) |> LogUtil.inspect(label: "lhs")
        {rhs,_max_idx} = rhs_stream |> to_throwable_list(rhs_reducer,{[],0}) |> LogUtil.inspect(label: "rhs")
        with [_lhh|_lht] <- lhs do
          rh_empty = Enum.map(rhs_columns,fn _col -> nil end)
          lh_empty = Enum.map(lhs_columns,fn _col -> nil end)
          with {:ok,lh_ds_alias,lh_ds_field,rh_ds_alias,rh_ds_field} <- choose_join_sides(join_clause,base_ds_alias,join_ds_alias) do
              lhs_idx = find_key_index({lh_ds_alias,lh_ds_field},lhs_column_indexes,true)
              rhs_idx = find_key_index({rh_ds_alias,rh_ds_field},rhs_column_indexes,true)
              try do
                combined_columns = lhs_columns ++ rhs_columns
                lhs_col_count = length(lhs_columns)
                LogUtil.inspect(lhs_col_count,label: "lhs_col_count")
                combined_column_indexes = Enum.reduce(rhs_column_indexes,lhs_column_indexes,fn {key,val},acc ->
                  Map.put(acc,key,val + lhs_col_count) |> LogUtil.inspect(label: "combined column")
                end)
                {:ok,join_ds(join_type,lhs,rhs,lhs_idx,rhs_idx,lh_empty,rh_empty,operator),combined_columns,combined_column_indexes}
              catch
                e ->
                  msg = "Error during join operation: #{e}"
                  QP.end_step(process_join_qp_step,:failed,%{error: msg})
                  {:error,msg}
              else
                ret -> QP.end_step(process_join_qp_step)
                ret
              end
          else
            _ ->
              msg = "Invalid join clause: #{inspect join_clause}"
              QP.end_step(process_join_qp_step,:failed,%{error: msg})
              {:error,msg}
          end
        else
          _ ->
            QP.end_step(process_join_qp_step)
            {:ok,[]} # No source rows, treating as empty result set
        end
      else
        {:error,msg} ->
          QP.end_step(process_join_qp_step,:failed,%{error: msg})
          {:error,"Error joining result sets: #{msg}"}
      end
    catch
      e ->
        msg = "Error enumerating stream: #{e}"
        QP.end_step(process_join_qp_step,:failed,%{error: msg})
        {:error,msg}
    end
  end
  defp process_joins(_base_segment,[%{segment: %{resource: %{alias: join_ds_alias},merge_action: %QueryFilterJoin{type: join_type}}}|_],_request_context) do
    {:error,"Invalid join type: #{inspect join_type} for data source #{inspect join_ds_alias}"}
  end
  # Processes filter operations (i.e. `WHERE` clause (would also likely be used for `HAVING`, if it was supported)) against the combined data set
  defp choose_filter_param(param,column_indexes) do
    case param do
      %QueryComponentField{src: ds_alias,field: ds_field} -> {:col,find_key_index({ds_alias,ds_field},column_indexes,true)}
      %QueryComponentQuotedString{unquoted: unquoted_string} -> {:str,unquoted_string}
      _ -> throw("Invalid filter criteria (#{inspect param})")
    end
  end
  # No filtering, return result set as-is
  defp filter_result(result_set,nil,_column_indexes) do
    {:ok,result_set}
  end
  # Currently `WHERE` is the only type of `QuerySegmentFilter`. Limited to one binary clause.
  # Uses `throw` to break out of an `Enum.filter/2` when a failure occurs - the error is caught and returned as a tuple.
  defp filter_result(result_set,%QuerySegmentFilter{clauses: [%QueryComponentBinaryClause{p1: p1_param,operator: operator,p2: p2_param}|_]},column_indexes) do
    try do
      p1_param = choose_filter_param(p1_param,column_indexes)
      p2_param = choose_filter_param(p2_param,column_indexes)
      {:ok,Enum.filter(result_set,fn row ->
        p1_value = case p1_param do
          {:col,idx} -> Enum.at(row,idx)
          {:str,unquoted_string} -> unquoted_string
        end
        p2_value = case p2_param do
          {:col,idx} -> Enum.at(row,idx)
          {:str,unquoted_string} -> unquoted_string
        end
        binary_compare(p1_value,p2_value,operator)
      end
      )}
    catch
      e -> {:error,"Error during filter operation: #{e}"}
    end
  end

  # Executes aggregate platform functions
  #   - Extracts all relevant values from the combined result set
  #   - Executes the relevant platform function
  #   - `throw`s any function error to be caught in `apply_aggr_funcs/2`.
  defp exec_aggr_funcs(funcs,result_set,new_result_set \\ [],cur_offset \\ 0)
  defp exec_aggr_funcs([],_result_set,new_result_set,_cur_offset) do
    new_result_set
  end
  defp exec_aggr_funcs([%QueryComponentFunc{name: func_name,alias: func_alias,params: params} = func|funcs],result_set,new_result_set,cur_offset) do
    params = Enum.reduce(params,[],fn param,acc -> case param do
      %QueryComponentFuncField{_index: index} ->
        [Enum.map(result_set,fn row -> Enum.at(row,index+cur_offset) end)|acc]
      %QueryComponentAllFields{_index: index} -> [Enum.map(result_set,fn row -> Enum.map(index,fn idx -> Enum.at(row,idx+cur_offset) end) end)|[:all_fields|acc]]
      _ -> case convert_param(param) do
         conv -> [conv|acc]
      end
    end end) |> Enum.reverse()
    case call_platform_func(func,params) do
      {:ok,func_result} -> exec_aggr_funcs(funcs,result_set,[{{:func,func_name,func_alias},func_result}|new_result_set],cur_offset+1)
      {:error,msg} -> throw("Error applying aggregate function #{func_name}: #{msg}")
    end
  end
  # Sets indexes on function parameters, required for gathering correct values for processing
  defp set_func_field_indexes(funcs,column_indexes) do
    Enum.map(funcs,fn func ->
      %{func|params: Enum.map(func.params,fn param ->
        case param do
          %QueryComponentFuncField{src: psrc,field: pfield} -> %{param|_index: find_key_index({psrc,pfield},column_indexes,true)}
          %QueryComponentAllFields{src: psrc} -> %{param|_index: do_find_indexes_for_alias(psrc,column_indexes)}
          _ -> param
        end
      end)}
    end)
  end
  
  # Applies aggregate functions
  # These functions behave differently for a grouped result set (a map) or a non-grouped result set (a list)

  # Empty grouped result set, with functions - return an empty list (de-grouping the result set)
  defp apply_aggr_funcs(grouped_result_set,_funcs,_group_key,column_indexes) when is_map(grouped_result_set) and map_size(grouped_result_set) == 0 do
    {:ok,[],column_indexes}
  end
  # Empty non-grouped result set - return an empty list
  defp apply_aggr_funcs([],_funcs,_group_key,column_indexes) do
    {:ok,[],column_indexes}
  end  
  # Grouped result set, no functions - de-group the result set and return
  defp apply_aggr_funcs(grouped_result_set,[],_group_key,column_indexes) when is_map(grouped_result_set) do
    {:ok,Enum.reduce(grouped_result_set,[],fn {_key,val},acc -> [val|acc] end),column_indexes}
  end
  # Non-grouped result set, no functions - return result set as-is
  defp apply_aggr_funcs(result_set,[],_group_key,column_indexes) do
    {:ok,result_set,column_indexes}
  end    
  # Non-empty results with functions
  # For grouped results - Execute each function against the grouped result set, and return a flat mapped list with rows consisting of the group key (with value), and the aggregations
  # For non-grouped results - Execute function against entire result set, and return result
  defp apply_aggr_funcs(grouped_result_set,funcs,group_key,column_indexes) do
    try do
      funcs = set_func_field_indexes(funcs,column_indexes)
      is_grouped = is_map(grouped_result_set)
      initial_offset = if is_grouped do 1 else 0 end

      {n_column_indexes,_acc} = Enum.reverse(funcs) |> Enum.map_reduce(initial_offset,fn %QueryComponentFunc{name: func_name,alias: func_alias},acc -> {{{:func,func_name,func_alias},acc},acc+1} end)
      column_indexes = if is_grouped do Map.put(Map.new(n_column_indexes),group_key,0) else Map.new(n_column_indexes) end
      result_set = if is_grouped do LogUtil.inspect(Enum.map(grouped_result_set,fn {key,val} -> [key|exec_aggr_funcs(funcs,val)] end),label: "Flat mapped apply_aggr_funcs") else LogUtil.inspect([exec_aggr_funcs(funcs,grouped_result_set)],label: "Non-grouped exec_aggr_funcs") end
      {:ok,result_set,column_indexes}
    catch
      e -> {:error,"Error while applying aggregate functions: #{e}"}
    end
  end

  # Converts `parsec` Query Components into atom values that can be used by dats source functions
  defp convert_param(param) do
    case param do
      %QueryComponentAtomLiteral{atom: atom} -> atom
      %QueryComponentQuotedString{unquoted: unquoted} -> unquoted
      %QueryComponentAllFields{} -> :all_fields
      _ -> throw("Unknown param type #{inspect param}")
    end
  end
  defp call_platform_func(%{type: func_type,name: func_name},params) do
    apply(PlatformFuncs,func_name,if func_type == :scalar_vararg do [params] else params end)
  end
  # Executes scalar platform functions
  #   - Extracts all relevant values from the combined result set
  #   - Executes the relevant platform function
  #   - `throw`s any function error to be caught in `apply_scalar_funcs/2`.

  # Reduces over the list of functions against a specified result set row
  # Returns the modified row
  defp exec_scalar_funcs(funcs,row,cur_offset \\ 0)
  defp exec_scalar_funcs([],row,_cur_offset) do
    row
  end
  defp exec_scalar_funcs([%QueryComponentFunc{name: func_name,alias: func_alias,params: params} = func|funcs],row,cur_offset) do
    params = Enum.reduce(params,[],fn param,acc -> case param do
    %QueryComponentFuncField{_index: index} -> [Enum.at(row,index+cur_offset)|acc]
    _ -> [convert_param(param)|acc]
  end end) |> Enum.reverse()
    case call_platform_func(func,params) do
      {:ok,func_result} -> exec_scalar_funcs(funcs,[{{:func,func_name,func_alias},func_result}|row],cur_offset+1) |> LogUtil.inspect(label: "Func Result")
      {:error,msg} -> throw("Error applying scalar function #{func_name}: #{msg}")
    end
  end
  # Applies scalar functions

  # Empty result set - return empty list
  defp apply_scalar_funcs([],_funcs,columns,column_indexes) do
    {:ok,[],columns,column_indexes}
  end
  # No functions - return result set as-is
  defp apply_scalar_funcs(result_set,[],columns,column_indexes) do
    {:ok,result_set,columns,column_indexes}
  end
  # Result set with functions - map over result set and apply the function list using `exec_scalar_funcs/2` as a reducer.
  defp apply_scalar_funcs(result_set,funcs,columns,column_indexes) do
    try do
      funcs = Enum.map(funcs,fn func ->
        %{func|params: Enum.map(func.params,fn param ->
          case param do
            %QueryComponentFuncField{src: psrc,field: pfield} -> %{param|_index: find_key_index({psrc,pfield},column_indexes,true)}
            _ -> param
          end
      end)}
      end)
      n_columns = Enum.map(funcs,fn %QueryComponentFunc{name: func_name,alias: func_alias} ->
      {:func,func_name,func_alias}
    end)
      columns = n_columns ++ columns
      num_funcs = length(funcs)
      {n_column_indexes,_acc} = Enum.reverse(funcs) |> Enum.map_reduce(0,fn %QueryComponentFunc{name: func_name,alias: func_alias},acc -> {{{:func,func_name,func_alias},acc},acc+1} end)
      column_indexes = Enum.reduce(column_indexes,n_column_indexes,fn {col,idx},acc -> [{col,idx+num_funcs}|acc] end) |> Map.new() |> LogUtil.inspect(label: "Updated column indexes")
      result_set = Enum.map(result_set,fn row -> exec_scalar_funcs(funcs,row) end) |> LogUtil.inspect(label: "apply_scalar_funcs result set")
      {:ok,result_set,columns,column_indexes}
    catch
      e -> {:error,"Error while applying scalar functions: #{e}"}
    end
  end
  defp connect(ds_name) do
    DataSources.connect(ds_name)
  end
  defp write_result_set(request_id,sorted_cols \\ [],result_set \\ []) do
    result_set_file = Path.join(Application.get_env(:DV,:result_tmp_dir,"/var/tmp"),"#{request_id}.json")
    File.write!(result_set_file,"""
      {
        "data": {
         "columns": [#{sorted_cols}],
         "rows": [
      """,[:append])
      result_set |> Stream.map(fn row -> Jason.encode_to_iodata!(row) end) |> Stream.intersperse(",") |> Stream.into(File.stream!(result_set_file,[:append])) |> Stream.run()
      File.write!(result_set_file,"""

          ]
        }
      }
      """,[:append])
    {:ok,result_set_file}
  end
  @doc """
  Executes a `Parser` result to perform a query operation.

  Returns either a wrapped nested list of [{key,value}...] records, or a wrapped error message.
  """
  def parse(segments,request_context) do
    try do
      do_parse(segments,request_context)
    rescue
      e -> {:error,Exception.message(e),request_context}
    end
  end
  defp do_parse(segments,%{request_id: request_id} = request_context) do
    select_qp_step = QP.start_step(request_id,:select)
    LogUtil.inspect(segments,label: "Segments")
    pre_validate_qp_step = QP.start_step(request_id,:pre_validate,2)
    with {:ok} <- LogUtil.inspect(pre_validate(segments),label: "Pre-validate") do
      # Pre-Validate
      QP.end_step(pre_validate_qp_step)
      [select_segment|remaining_segments] = segments
      extract_fields_qp_step = QP.start_step(request_id,:extract_fields,2)
      extract_select_fields_qp_step = QP.start_step(request_id,:extract_select_fields,3)
      with {:ok,extracted_fields,extracted_funcs,extracted_aliases,extracted_resources} <- LogUtil.inspect(extract_select_fields(select_segment),label: "Extract Select Fields") do
      # Extract Select Fields
        QP.end_step(extract_select_fields_qp_step)
        extract_segment_fields_qp_step = QP.start_step(request_id,:extract_segment_fields,3)
        with {:ok,extracted_fields,extracted_aliases,extracted_resources} <- LogUtil.inspect(extract_segment_fields(remaining_segments,extracted_fields,extracted_aliases,extracted_resources),label: "Extract Segment Fields") do
          # Extract Segment Fields
          QP.end_step(extract_segment_fields_qp_step)
          classify_funcs_qp_step = QP.start_step(request_id,:classify_funcs,3)
          with {:ok,local_funcs,platform_funcs} <- LogUtil.inspect(classify_funcs(extracted_funcs,extracted_resources),label: "Classify funcs") do
            # Classify Funcs
            QP.end_step(classify_funcs_qp_step)
            validate_group_by_qp_step = QP.start_step(request_id,:validate_group_by,3)
            with {:ok} <- LogUtil.inspect(validate_group_by(Enum.find_value(remaining_segments,fn segment ->
              case segment do
                %QuerySegmentGroupBy{} -> segment
                _ -> nil
              end
            end),extracted_fields,platform_funcs),label: "Validate Group By") do
              # Validate Group By
              QP.end_step(validate_group_by_qp_step)
              extract_func_fields_qp_step = QP.start_step(request_id,:extract_func_fields,3)
              with {:ok,extracted_fields,_extracted_aliases,extracted_resources} <- LogUtil.inspect(extract_func_fields(platform_funcs,extracted_fields,extracted_aliases,extracted_resources),label: "Extracted func fields") do
                # Extract Func Fields
                QP.end_step(extract_func_fields_qp_step)
                QP.end_step(extract_fields_qp_step)
                merged_local_attrs = LogUtil.inspect(local_funcs ++ extracted_fields,label: "Merged local attrs")
                grouped_local_attrs = LogUtil.inspect(Enum.group_by(merged_local_attrs,fn attr ->
                  case attr do
                    %{src: attr_src} -> if Map.has_key?(extracted_resources,attr_src) do attr_src else nil end
                    %{} -> if Map.has_key?(extracted_resources,select_segment.resource.alias) do select_segment.resource.alias else nil end
                  end
                end),label: "Grouped local attrs")
                prepare_segments_qp_step = QP.start_step(request_id,:prepare_segments,2)
                with false <- Map.has_key?(grouped_local_attrs,nil) do
                  # Grouped Local Attrs
                  with {:ok,new_segments,post_gets} <- LogUtil.inspect(prepare_segments(segments,grouped_local_attrs),label: "Prepare Statements") do
                    # Prepare Gets
                    QP.end_step(prepare_segments_qp_step)
                    get_segment_streams_qp_step = QP.start_step(request_id,:get_segment_streams,2)
                    with {:ok,new_segments} <- LogUtil.inspect(get_segment_streams(new_segments,request_context),label: "Get Segment Data") do
                      QP.end_step(get_segment_streams_qp_step)
                      # Get Segment Streams
                      {base_segment,join_segments} = Enum.reduce(new_segments,{nil,[]},fn segment,{base,acc} -> case LogUtil.inspect(segment.segment,label: "reduce segment") do
                        %{merge_action: nil} -> LogUtil.log("Nil segment: #{inspect segment}")
                        {segment,acc}
                        _ ->
                          LogUtil.log("Default segment: #{inspect segment}")
                          {base,[segment|acc]}
                        end
                      end) |> LogUtil.inspect(label: "Split segments")
                      process_joins_qp_step = QP.start_step(request_id,:process_joins,2)
                      with {:ok,result_set,combined_columns,combined_column_indexes} <- LogUtil.inspect(process_joins(base_segment,join_segments,request_context),label: "Process joins") do
                        # Process Joins
                        QP.end_step(process_joins_qp_step)
                        {where_clause,group_by_clause,order_by_clause,limit_clause} = LogUtil.inspect(Enum.reduce(post_gets,{nil,nil,nil,nil},
                        fn segment,{where_clause,group_by_clause,order_by_clause,limit_clause} ->
                          case segment do
                            %QuerySegmentFilter{} ->
                              {segment,group_by_clause,order_by_clause,limit_clause}
                            %QuerySegmentGroupBy{} ->
                              {where_clause,segment,order_by_clause,limit_clause}
                            %QuerySegmentOrderBy{} ->
                              {where_clause,group_by_clause,segment,limit_clause}
                              %QuerySegmentLimit{} ->
                                {where_clause,group_by_clause,order_by_clause,segment}
                          end
                        end
                        ),label: "Post get tuple")
                        filter_result_qp_step = QP.start_step(request_id,:filter_result,2)
                        with {:ok,result_set} <- LogUtil.inspect(filter_result(result_set,where_clause,combined_column_indexes),label: "Filtered Result") do
                          # Filtered Result
                          QP.end_step(filter_result_qp_step)
                          divided_funcs = Enum.group_by(platform_funcs,fn func ->
                            case func do
                              %QueryComponentFunc{_platform: true,type: :aggregate} -> :aggr
                              %QueryComponentFunc{_platform: true} -> :scalar
                            end
                          end)
                          LogUtil.log("Divided platform funcs: #{inspect divided_funcs}")
                          apply_scalar_funcs_qp_step = QP.start_step(request_id,:apply_scalar_funcs,2)
                          with {:ok,result_set,combined_columns,combined_column_indexes} <- LogUtil.inspect(apply_scalar_funcs(result_set,Map.get(divided_funcs,:scalar,[]),combined_columns,combined_column_indexes),label: "Non-Aggregate Platform Func Result") do
                            # Non-aggregate Platform Functions
                            QP.end_step(apply_scalar_funcs_qp_step)
                            group_by_qp_step = QP.start_step(request_id,:group_result,2)
                            group_index = try do
                              if group_by_clause != nil do
                                case LogUtil.inspect(group_by_clause.attr,label: "Group By attr") do
                                 %QueryComponentAliasPlaceholder{alias: alias} -> find_key_index({nil,nil,alias},combined_column_indexes,false)
                                 %QueryComponentField{src: src,field: field} -> find_key_index({src,field,nil},combined_column_indexes,true)
                                end
                              else
                                nil
                              end
                            catch
                              e ->
                              msg = "Error parsing GROUP BY clause: #{e}"
                              raise(msg)
                            end
                            LogUtil.inspect(combined_columns,label: "Combined columns")
                            LogUtil.inspect(group_index,label: "Group index")
                            group_key = if group_index != nil do Enum.at(combined_columns,group_index) end
                            result_set = if group_by_clause != nil do
                              grouped = Enum.group_by(result_set,fn row ->
                                Enum.at(row,group_index)
                              end,fn row -> row end)
                              QP.end_step(group_by_qp_step)
                              grouped
                            else
                              result_set
                            end
                            LogUtil.log("Grouped result set: #{inspect result_set}")
                            apply_aggr_funcs_qp_step = QP.start_step(request_id,:apply_aggregate_funcs,2)
                            with {:ok,result_set,combined_column_indexes} <- LogUtil.inspect(apply_aggr_funcs(result_set,Map.get(divided_funcs,:aggr,[]),group_key,combined_column_indexes),label: "Aggregate Platform Func Result") do
                              # Agregate Platform Functions
                              QP.end_step(apply_aggr_funcs_qp_step)
                              result_set = if order_by_clause != nil do
                                order_by_qp_step = QP.start_step(request_id,:order_result,2)
                                order_index = try do
                                      case order_by_clause.attr do
                                        %QueryComponentAliasPlaceholder{alias: alias} -> find_key_index({nil,nil,alias},combined_column_indexes,false)
                                        %QueryComponentField{src: src,field: field} -> find_key_index({src,field,nil},combined_column_indexes,true)
                                      end
                                    catch
                                      e ->
                                      msg = "Error parsing ORDER BY clause: #{e}"
                                      raise(msg)
                                    end
                                # Custom sorter - nil safe sorting
                                # Required because of Erlang term order https://www.erlang.org/doc/reference_manual/expressions#term-comparisons conflicting with expected behavior
                                # May need to be moved elsewhere for future platform funcs
                                sorter = fn dir ->
                                  case dir do
                                  :asc ->
                                    fn left,right ->
                                      LogUtil.log("left: #{inspect left},right: #{inspect right}")
                                    case {left,right} do
                                      # both nil, equal
                                      {nil,nil} ->
                                        LogUtil.log("equal")
                                        true
                                      # in ASC - nil is always greater than not-nil
                                      {nil,_} ->
                                        LogUtil.log("left hand nil")
                                        false
                                      {_,nil} ->
                                        LogUtil.log("right hand nil")
                                        true
                                      {_,_} ->
                                        LogUtil.log("default")
                                        left <= right
                                    end
                                  end
                                  :desc ->
                                    fn left,right ->
                                      case {left,right} do
                                        # both nil, equal
                                        {nil,nil} -> true
                                        # in DESC - nil is always greater than or equal to not-nil
                                        {nil,_} -> true
                                        {_,nil} -> false
                                        {_,_} -> left >= right
                                      end
                                    end
                                  end
                                end
                                ordered = Enum.sort_by(result_set,fn row -> Enum.at(row,order_index) end,sorter.(order_by_clause.dir))
                                QP.end_step(order_by_qp_step)
                                ordered
                              else
                                result_set
                              end
                              LogUtil.log("Ordered result set: #{inspect result_set}")
                              result_set = if limit_clause != nil do
                                limit_result_qp_step = QP.start_step(request_id,:limit_result,2)
                                limited = Enum.take(result_set,limit_clause.limit)
                                QP.end_step(limit_result_qp_step)
                                limited
                              else
                                result_set
                              end
                              LogUtil.log("Limited result set: #{inspect result_set}")

                              # Sort row columns and drop droppables, also rename fields to aliases where applicable
                              # Three variants of column names at this point:
                                # local func: {"alias", :upper, "up"}
                                # platform func: {:func, :count, "up"}
                                # field: {"alias","usename","username"}
                              # third element (attr alias) may be nil for any of these.

                              finalize_result_qp_step = QP.start_step(request_id,:finalize_result,2)
                              local_attr_sort_map = Enum.reduce(LogUtil.inspect(merged_local_attrs,label: "merged_local_attrs pre sort map"),%{},fn attr,sort_map ->
                                case attr do
                                  %QueryComponentFunc{type: nil,src: ds_alias,_ident: ident,alias: f_alias,_index: index,_drop: drop} ->
                                    map_key = {ds_alias,ident,f_alias}
                                    if not drop do Map.put(sort_map,map_key,index) else sort_map end
                                  %{src: ds_alias,field: ds_field,alias: f_alias,_index: index,_drop: drop} ->
                                    map_key = {ds_alias,ds_field,f_alias}
                                    if not drop do Map.put(sort_map,map_key,index) else sort_map end
                                  %QueryComponentAllFields{src: ds_alias,_index: index,_drop: drop} ->
                                    map_key = {ds_alias,nil,nil}
                                    if not drop do Map.put(sort_map,map_key,index) else sort_map end
                                  _ -> sort_map
                                end
                            end) |> LogUtil.inspect(label: "local_attr_sort_map")
                            with [_first_result|_remaining_results] <- result_set do
                              full_sort_map = LogUtil.inspect(Enum.reduce(LogUtil.inspect(platform_funcs,label: "platform_funcs param to full_sort_map"),local_attr_sort_map,fn
                                %{_index: index,_drop: drop,name: func_name,alias: func_alias},sort_map ->
                                map_key = {:func,func_name,func_alias}
                                if not drop do
                                  Map.put(sort_map,map_key,index)
                                else
                                  sort_map
                                end
                              end),label: "full_sort_map")
                              LogUtil.inspect(combined_columns,label: "Combined columns")
                              LogUtil.inspect(combined_column_indexes,label: "Combined column indexes")
                              kept_col_indexes = Enum.reduce(full_sort_map,%{},fn {key,target_idx},acc ->
                                  case key do
                                    {dsa,nil,nil} ->
                                      Enum.flat_map(combined_column_indexes,fn {key,idx} ->
                                        case key do
                                          {^dsa,_dsf,_fa} -> [{idx,{Map.get(full_sort_map,key,target_idx),key}}]
                                          _ -> []
                                        end
                                      end) |> Enum.into(acc)
                                    {_dsa_,_dsf,_fa} ->
                                      Map.put(acc,Map.fetch!(combined_column_indexes,key),{target_idx,key})
                                  end
                                end)
                              result_set = Enum.map(result_set,fn row -> Enum.with_index(row) |> Enum.flat_map(fn {col,idx} ->
                                case Map.get(kept_col_indexes,idx,nil) do
                                  nil -> []
                                  {idx,{:func,_func_name,_func_alias}} = tmp ->
                                    LogUtil.inspect(col,label: "col")
                                    LogUtil.inspect(tmp,label: "tmp")
                                    [{idx,elem(col,1)}]
                                  {idx,_key} -> [{idx,col}]
                                end
                              end) |> Enum.sort_by(fn {idx,_val} -> idx end) |> Enum.map(fn {_idx,val} -> val end) end)
                              sorted_cols = Enum.to_list(kept_col_indexes) |> Enum.sort_by(fn {_idx,{final_idx,_col}} -> final_idx end)
                              |> Enum.map(fn {_idx,{_final_idx,{_dsa,dsf,fa}}} -> if fa != nil do "\"#{fa}\"" else "\"#{dsf}\"" end end)
                              |> Enum.intersperse(",")
                              LogUtil.inspect(result_set,label: "Final result set")
                              {:ok,result_set_file} = write_result_set(request_id,sorted_cols,result_set)
                              QP.end_step(finalize_result_qp_step)
                              QP.end_step(select_qp_step)
                              {:ok,result_set_file,request_context}
                            else
                              [] ->
                                QP.end_step(select_qp_step)
                                {:ok,result_set_file} = write_result_set(request_id)
                                {:ok,result_set_file,request_context}
                            end
                              # End Aggregate Platform Functions
                            else
                              # End Aggregate Platform Functions Error
                              {:error,msg} ->
                                QP.end_step(apply_aggr_funcs_qp_step,:failed,%{error: msg})
                                QP.end_step(select_qp_step,:failed,%{error: msg})
                                {:error,msg,request_context}
                              # End Aggregate Platform Functions Error
                            end
                            # End Non-aggregate Platform Functions
                          else
                            # Non-aggregate Platform Functions Error
                            {:error,msg} ->
                              QP.end_step(apply_scalar_funcs_qp_step,:failed,%{error: msg})
                              QP.end_step(select_qp_step,:failed,%{error: msg})
                              {:error,msg,request_context}
                            # Non-aggregate Platform Functions Error
                          end
                          # End Filtered Result
                        else
                          # Filtered Result Error
                          {:error,msg} ->
                            QP.end_step(filter_result_qp_step,:failed,%{error: msg})
                            QP.end_step(select_qp_step,:failed,%{error: msg})
                            {:error,msg,request_context}
                          # End Filtered Result Error
                        end
                        # End Process Joins
                      else
                        # Process Joins Error
                        {:error,msg} ->
                          QP.end_step(process_joins_qp_step,:failed,%{error: msg})
                          QP.end_step(select_qp_step,:failed,%{error: msg})
                          {:error,msg,request_context}
                        # End Process Joins Error
                      end
                      # End Get Segment Streams
                    else
                      # Get Segment Streams Error
                      {:error,msg} ->
                        QP.end_step(get_segment_streams_qp_step,:failed,%{error: msg})
                        QP.end_step(select_qp_step,:failed,%{error: msg})
                        {:error,msg,request_context}
                      # End Get Segment Streams Error
                    end
                    # End Prepare Gets
                  else
                    # Prepare Gets Error
                    {:error,msg} ->
                      QP.end_step(prepare_segments_qp_step,:failed,%{error: msg})
                      QP.end_step(select_qp_step,:failed,%{error: msg})
                      {:error,msg,request_context}
                    # End Prepare Gets Error
                  end
                  # End Grouped Local Attrs
                else
                  # Grouped Local Attrs Error
                  _ ->
                    msg = "Invalid source in query attrs: #{inspect merged_local_attrs}"
                    QP.end_step(prepare_segments_qp_step,:failed,%{error: msg})
                    QP.end_step(select_qp_step,:failed,%{error: msg})
                    {:error,msg,request_context}
                  # Grouped Local Attrs Error
                end
                # End Extract Func Fields
              else
                # Extract Func Fields Error
                {:error,msg} ->
                  QP.end_step(extract_fields_qp_step,:failed,%{error: msg})
                  QP.end_step(extract_func_fields_qp_step,:failed,%{error: msg})
                  QP.end_step(select_qp_step,:failed,%{error: msg})
                  {:error,msg,request_context}
                # End Extract Func Fields Error
              end
            # End Validate Group By
            else
              # Validate Group By Error
              {:error,msg} ->
                QP.end_step(extract_fields_qp_step,:failed,%{error: msg})
                QP.end_step(validate_group_by_qp_step,:failed,%{error: msg})
                QP.end_step(select_qp_step,:failed,%{error: msg})
                {:error,msg,request_context}
              # End Validate Group By Error
            end
            # End Classify Funcs
          else
            # Classify Funcs Error
            {:error,msg} ->
              QP.end_step(extract_fields_qp_step,:failed,%{error: msg})
              QP.end_step(classify_funcs_qp_step,:failed,%{error: msg})
              QP.end_step(select_qp_step,:failed,%{error: msg})
              {:error,msg,request_context}
            # End Classify Funcs Error
          end
          # End Extract Segment Fields
        else
          # Extract Segment Fields Error
          {:error,msg} ->
            QP.end_step(extract_fields_qp_step,:failed,%{error: msg})
            QP.end_step(extract_segment_fields_qp_step,:failed,%{error: msg})
            QP.end_step(select_qp_step,:failed,%{error: msg})
            {:error,msg,request_context}
          # End Extract Segment Fields Error
        end
      # End Extract Select Fields
      else
        # Extract Select Fields Error
        {:error,msg} ->
          QP.end_step(extract_fields_qp_step,:failed,%{error: msg})
          QP.end_step(extract_select_fields_qp_step,:failed,%{error: msg})
          QP.end_step(select_qp_step,:failed,%{error: msg})
          {:error,msg,request_context}
        # Extract Select Fields Error
      end
      # End Pre-Validate
    else
      # Pre-Validate Error
      {:error,msg} ->
        QP.end_step(pre_validate_qp_step,:failed,%{error: msg})
        QP.end_step(select_qp_step,:failed,%{error: msg})
        {:error,msg,request_context}
      # End Pre-Validate Error
    end
  end
end
