#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule Parsec do
  @moduledoc """
  Structured Query Language (SQL) parser. Used to parse all queries either submitted directly, or executed via a Model definition.

  Supported Syntax:

  * `SELECT` - \\*, supported function calls, and individual field names only (e.g. `SELECT *, SELECT
field1,field2`)
  * Data source name aliasing (e.g. `SELECT * FROM source1 alias`)
  * Field aliasing (e.g. `SELECT field1 AS alias FROM source1`)
  * `LEFT JOIN` - single field only (e.g. `SELECT alias.*,alias2.* FROM
source alias LEFT JOIN source alias2 ON(alias.id = alias2.id)`)
  * `RIGHT JOIN` - single field only
  * `INNER JOIN` - single field only
  * `WHERE` - single field only (e.g. `SELECT * FROM source1 WHERE field1
= 'value'`)
  * `LIMIT` - single numeric limit only (e.g. `SELECT * FROM source1 LIMIT
10`)
  * `GROUP BY` - single field only (e.g. `SELECT field,COUNT(field2)
AS count FROM source1 GROUP BY field`)
  * `ORDER BY` - single field only (e.g. `SELECT * FROM source1 ORDER
BY field DESC`)

Supported Functions:

  * `LOWER`
  * `UPPER`
  * `COUNT` \\*
  * `AVG` \\*
  * `SUM` \\*
  * `CONCAT` \\*
  * `CONCAT_WS` \\*
  * `MIN` \\*
  * `MAX` \\*

  \\* Indicates platform-only support (no Data Source support capability).

Supported comparison operators:

  * `=`
  * `!=`
  * `<>`
  * `<=`
  * `>=`
  * `>`
  * `<`

  Comparisons are performed in-platform, using standard Elixir comparison operators.

"""

  # These hardcoded atoms are used in conversion functions further down
  # If updating the function or literal support, make the equivalent change here
  @aggregate_functions [
    :count,
    :min,
    :max,
    :avg,
    :sum
  ]

  @scalar_vararg_functions [
    :concat,
    :concat_ws
  ]

  @atom_literals [
    :distinct
  ]

  # This is the part of the query between the data source and the requested resource (e.g. if @query_resource_separator is ".", SELECT data_source.resource)
  # Changing this WILL BREAK any existing models that are saved with the old separator
  # While there is no hierarchy support in this version, you can expect that any future hierarchy support will use a different attribute
  @query_resource_separator "."

  import NimbleParsec

  # TODO - Currently, the SQL support here is CASE SENSITIVE and sensitive to extraneous whitespace
  # I will remove this comment if I have time to fix this - if not, this is likely priority #1 after release

  select = ignore(string("SELECT "))
  distinct = string("DISTINCT")

  field_label_part = ascii_string([?a..?z,?A..?Z,?_,?0..?9],min: 1) # TODO - this is not to spec.
  field_label_with_alias = field_label_part
  |> unwrap_and_tag(:src)
  |> ignore(string("."))
  |> concat(field_label_part |> unwrap_and_tag(:field))

  field_label_noalias = field_label_part |> unwrap_and_tag(:field)
  field_label = choice([
    field_label_with_alias,
    field_label_noalias
  ])
  as = ignore(string(" AS ")) |> concat(field_label_part |> unwrap_and_tag(:alias))
  alias_placeholder = field_label_part |> unwrap_and_tag(:alias)

  single_quote = string("'")
  single_quote_doubled = string("\'\'")

  single_quoted_string_bare = concat(single_quote,repeat(
    choice([
      single_quote_doubled,
      utf8_string([{:not,?'}],min: 1)
    ])
  )) |> concat(single_quote) |> reduce({Enum,:join,[]}) |> unwrap_and_tag(:field)

  single_quoted_string = single_quoted_string_bare |> reduce({:quoted_string_to_struct,[]})

  star = field_label_part
  |> unwrap_and_tag(:src)
  |> ignore(string("."))
  |> concat(ignore(string("*"))) |> reduce({:to_struct,[QueryComponentAllFields]})

  func_label = field_label_part |> ignore(string("("))
  func_close = ignore(string(")"))
  func_field = choice([
    star,
    single_quoted_string,
    field_label_with_alias |> reduce({:to_struct,[QueryComponentFuncField]}),
    alias_placeholder |> reduce({:to_struct,[QueryComponentAliasPlaceholder]})
  ])
  func_repeated_field = func_field |> ignore(string(","))
  distinct_in_func = distinct |> post_traverse({:atomize_literal,[]}) |> unwrap_and_tag(:atom) |> reduce({:to_struct,[QueryComponentAtomLiteral]})
  spaced_literals = distinct_in_func |> concat(ignore(string(" ")))
  func_args = repeat(choice([spaced_literals,func_repeated_field,func_field]))
  single_func =
    func_label
    |> post_traverse({:atomize_func,[]})
    |> unwrap_and_tag(:name)
    |>
    concat(func_args
      |>
    tag(:params)
    )
    |>
    concat(func_close) |> concat(optional(as))
    |> reduce({:func_to_struct,[QueryComponentFunc]})

  single_field = field_label |> concat(optional(as)) |> reduce({:to_struct,[QueryComponentField]})

  single_func_or_field = choice([
  star,
  single_func,
  single_field
  ])
  multi_func_or_field = single_func_or_field |> concat(ignore(string(",")))
  fields = repeat(choice(
  [
    multi_func_or_field,
    single_func_or_field
  ]
  )) |> reduce({:gen_attr_index,[]}) |> unwrap_and_tag(:fields)


  query_resource_separator = string(@query_resource_separator)

  datasource_base = field_label_part
  |> unwrap_and_tag(:data_source) |> ignore(query_resource_separator)
  |> concat(
    choice([field_label_part,single_quoted_string_bare |> reduce({:unwrap_quoted_string,[]})]) |> unwrap_and_tag(:src)
  )
  select_datasource = datasource_base |> concat(
    ignore(string(" "))
    |>
    concat(field_label_part) |> unwrap_and_tag(:alias)
  ) |> reduce({:to_struct,[QueryComponentResource]})

  from = ignore(string(" FROM ")) |> concat(select_datasource |> unwrap_and_tag(:resource))
  left_join_prefix = string("LEFT JOIN") |> ignore(string(" ")) |> replace(:LEFT) |> unwrap_and_tag(:type)
  right_join_prefix = string("RIGHT JOIN") |> ignore(string(" ")) |> replace(:RIGHT) |> unwrap_and_tag(:type)
  inner_join_prefix = string("INNER JOIN") |> ignore(string(" ")) |> replace(:INNER) |> unwrap_and_tag(:type)

  left_join_prefix_with_alias = left_join_prefix |>
  concat(datasource_base
  |> concat(ignore(string(" "))
  |>
  concat(field_label_part) |> unwrap_and_tag(:alias)
  )
  |> reduce({:to_struct,[QueryComponentResource]})
  |> unwrap_and_tag(:resource))

  right_join_prefix_with_alias = right_join_prefix |>
  concat(datasource_base
  |> concat(ignore(string(" "))
  |>
  concat(field_label_part) |> unwrap_and_tag(:alias)
  )
  |> reduce({:to_struct,[QueryComponentResource]})
  |> unwrap_and_tag(:resource))

  inner_join_prefix_with_alias = inner_join_prefix |>
  concat(datasource_base
  |> concat(ignore(string(" "))
  |>
  concat(field_label_part) |> unwrap_and_tag(:alias)
  )
  |> reduce({:to_struct,[QueryComponentResource]})
  |> unwrap_and_tag(:resource))

  binary_comparison_operators = choice([
    string("="),
    string("!="),
    string("<>"),
    string("<="),
    string(">="),
    string(">"),
    string("<")
  ])
  join_clause = tag(unwrap_and_tag(ignore(string(" ON "))
  |> ignore(string("("))
  |> concat(field_label_with_alias |> reduce({:to_struct,[QueryComponentField]})),:p1)
  |> optional(ignore(string(" ")))
  |> concat(unwrap_and_tag(binary_comparison_operators |> map({:convert_operator,[]}),:operator))
  |> unwrap_and_tag(optional(ignore(string(" ")))
  |> concat(field_label_with_alias |> reduce({:to_struct,[QueryComponentField]})),:p2)
  |> ignore(string(")"))
  |> reduce({:to_struct,[QueryComponentBinaryClause]}),:clauses)
  left_join = ignore(string(" ")) |> concat(left_join_prefix_with_alias) |> concat(join_clause)
  right_join = ignore(string(" ")) |> concat(right_join_prefix_with_alias) |> concat(join_clause)
  inner_join = ignore(string(" ")) |> concat(inner_join_prefix_with_alias) |> concat(join_clause)
  select = select |> concat(fields) |> concat(from) |> reduce({:to_struct,[QuerySegmentSELECT]})
  joins = choice([left_join,right_join,inner_join]) |> reduce({:to_struct,[QuerySegmentJOIN]})

  # TODO - WHERE clause is a copy of left_join_clause, will want to deduplicate this
  # single_unquoted_number should be a separate struct type in a later version
  single_unquoted_number = ascii_string([?0..?9,?.],min: 1) |> unwrap_and_tag(:field) |> reduce({:quoted_string_to_struct,[]})
  where = string(" WHERE ") |> replace(:WHERE) |> unwrap_and_tag(:type)
  where_clauses = tag(unwrap_and_tag(field_label_with_alias |> reduce({:to_struct,[QueryComponentField]}),:p1)
  |> optional(ignore(string(" ")))

  |> concat(unwrap_and_tag(binary_comparison_operators |> map({:convert_operator,[]}),:operator))
  |> unwrap_and_tag(optional(ignore(string(" ")))
  |> concat(
    choice([single_quoted_string,field_label_with_alias |> reduce({:to_struct,[QueryComponentField]}),single_unquoted_number])
  ),:p2)
  |> reduce({:to_struct,[QueryComponentBinaryClause]}),:clauses)
  where = where |> concat(where_clauses) |> reduce({:to_struct,[QuerySegmentFilter]})

  group_by = ignore(string(" GROUP BY ")) |> concat(unwrap_and_tag(choice([field_label_with_alias |> reduce({:to_struct,[QueryComponentField]}),alias_placeholder |> reduce({:to_struct,[QueryComponentAliasPlaceholder]})]),:attr)) |> reduce({:to_struct,[QuerySegmentGroupBy]})

  limit = unwrap_and_tag(ignore(string(" LIMIT ")) |> concat(integer(min: 1)),:limit) |> reduce({:to_struct,[QuerySegmentLimit]})

  order_by = ignore(string(" ORDER BY ")) |> concat(unwrap_and_tag(choice([field_label_with_alias |> reduce({:to_struct,[QueryComponentField]}),alias_placeholder |> reduce({:to_struct,[QueryComponentAliasPlaceholder]})]),:attr)) |> concat(optional(unwrap_and_tag(choice([string(" ASC"),string(" DESC"),empty() |> replace("ASC")]) |> map({:convert_direction,[]}),:dir))) |> reduce({:to_struct,[QuerySegmentOrderBy]})

  query = select |> concat(repeat(joins)) |> optional(where) |> optional(group_by) |> optional(order_by) |> optional(limit) |> eos() |> tag(:parts)
  defparsec :sql, query

  # Converts ORDER BY directions to an atom
  # This could be done using `atomize/5` instead
  defp convert_direction(str) do
    case String.downcase(String.trim(str)) do
      "desc" -> :desc
      "asc" -> :asc
      _ -> :asc
    end
  end
  # Converts binary comparison operators an atom
  defp convert_operator(str) do
    case str do
      "=" -> :equals
      "!=" -> :not_equals
      "<>" -> :not_equals
      "<=" -> :less_equals
      ">=" -> :greater_equals
      ">" -> :greater
      "<" -> :less
      _ -> :unknown
    end
  end
  # Converts a string literal to an atom, primarily used for DISTINCT
  defp atomize_literal(rest,args,context,line,offset) do
    case atomize(rest,args,context,line,offset) do
      {:error,msg} -> {:error,"Invalid literal #{msg}"}
      ret -> ret
    end
  end
  # Converts a function name string to an atom
  defp atomize_func(rest,args,context,line,offset) do
    case atomize(rest,args,context,line,offset) do
      {:error,msg} -> {:error,"Invalid function #{msg}"}
      ret -> ret
    end
  end
  # Generic conversion of string to atom
  defp atomize(rest,[name|_args],context,_line,_offset) do
    name = String.downcase(name)
    try do
      {rest,[String.to_existing_atom(name)],context}
    rescue
      _e -> {:error,"#{name}"}
    end
  end
  # Converts a valid function to a function struct, adding `:type` annotation
  defp func_to_struct(p,s) do
    LogUtil.inspect(p,label: "func_to_struct")
    {_,func_name} = LogUtil.inspect(List.keyfind(p,:name,0),label: "Keyfind")
    cond do
      func_name in get_aggregate_functions() ->
        to_struct([{:type,:aggregate}|p],s)
      func_name in get_scalar_vararg_functions() ->
        to_struct([{:type,:scalar_vararg}|p],s)
      true -> to_struct([{:type,nil}|p],s)
    end
  end
  @doc """
  Initializes atoms configured as module attributes, to make them available for `String.to_existing_atom/1`.

  This is for parsing string literals (e.g. `DISTINCT`), aggregate, and vararg functions.
  """
  def init_required_atoms() do
    Enum.each(get_atom_literals(),fn atom -> atom end)
    Enum.each(get_aggregate_functions(),fn atom -> atom end)
    Enum.each(get_scalar_vararg_functions(),fn atom -> atom end)
  end
  defp get_atom_literals() do
    @atom_literals
  end
  defp get_aggregate_functions() do
    @aggregate_functions
  end
  defp get_scalar_vararg_functions() do
    @scalar_vararg_functions
  end
  defp to_struct(p,s) do
    struct(s,p)
  end
  defp unwrap_quoted_string([field: field],q \\ "'") do
    String.trim(field,q)
  end
  defp quoted_string_to_struct([field: field] = p,s \\ QueryComponentQuotedString,q \\ "'") do
    p = p ++ [unquoted: String.trim(field,q)]
    to_struct(p,s)
  end
  defp gen_attr_index(p) do
    LogUtil.debug("gen_attr_index: #{inspect p}")
    set_attr_index(p,[],0)
  end
  defp set_attr_index([],n,_i) do
    Enum.reverse(n)
  end
  defp set_attr_index([f|p],n,i) do
    case f do
      %QueryComponentFunc{} -> set_attr_index(p,[%{f|_index: i,_ident: "#{Atom.to_string(f.name)}_#{i}"}|n],i+1)
      _ -> set_attr_index(p,[%{f|_index: i}|n],i+1)
    end
  end
end
