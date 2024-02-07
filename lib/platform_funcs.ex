#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule PlatformFuncs do
  @moduledoc """
  Implementations of supported SQL functions for platform-level executions.

  These implementations are based primarily on published documentation for the equivalent functions in PostgreSQL (https://www.postgresql.org/docs/15/functions-aggregate.html / https://www.postgresql.org/docs/15/functions-string.html).
  """

  @doc """
  Checks support for the function defined by the passed attribute.
  """
  def check_func_support(attr) do
    func = attr.name
    param_count = length(attr.params)
    case Kernel.function_exported?(__MODULE__,func,param_count) do
      true -> {:ok,{__MODULE__,func}}
      false -> {:error,"Function not found"}
    end
  end

  # Filters out unjoined rows (represented as rows of n 'nil' values)
  # Required for aggregations to work properly
  defp filter_unjoined_rows(vals) do
    Enum.filter(vals,fn row -> row |> Enum.count(fn col -> col != nil end) > 0 end)
  end

  # Filters out null/nil values
  # Required because the ODBC module returns DB level nulls as :null
  defp filter_nulls(val) do
    val != nil and val != :null
  end

  # Scalar Functions #

  @doc """
  `UPPER(field)`
  """
  def upper(val) do
    val = if val != nil do String.upcase(val) else nil end
    {:ok,val}
  end
  @doc """
  `LOWER(field)`
  """
  def lower(val) do
    val = if val != nil do String.downcase(val) else nil end
    {:ok,val}
  end

  # End Scalar Functions #

  # Scalar Varargs Functions #

  @doc """
  `CONCAT(field,field,...)`
  """
  def concat(vars) do
    LogUtil.log("CONCAT: #{inspect vars}")
    {:ok,Enum.join(vars)}
  end

  @doc """
  `CONCAT_WS('separator',field,field...)`
  """
  def concat_ws([seperator|vars]) do
    LogUtil.log("CONCAT_WS: #{inspect vars}")
    {:ok,Enum.join(vars,seperator)}
  end

  # End Scalar Varargs Functions #

  # Aggregate Functions #

  @doc """
  `COUNT(DISTINCT field)`
  `COUNT(*)`
  """
  def count(:distinct,vals) do
    LogUtil.inspect(vals,label: "pre-distinct vals")
    {:ok,Enum.uniq(vals) |> Enum.filter(&filter_nulls/1) |> Enum.count()}
  end
  def count(:all_fields,vals) do
    {:ok,filter_unjoined_rows(vals) |> Enum.count()}
  end
  def count(first,second) do
    LogUtil.log("first: #{inspect first}, second: #{inspect second}")
    {:error,"Unsupported function variant for count/2"}
  end
  @doc """
  `COUNT(DISTINCT *)`
  """
  def count(:distinct,:all_fields,vals) do
    {:ok,Enum.uniq(vals) |> filter_unjoined_rows() |> Enum.count()}
  end
  def count(_first,_second,_third) do
    {:error,"Unsupported function variant for count/3"}
  end
  @doc """
  `COUNT(field)`
  """
  def count(vals) when is_list(vals) do
    {:ok,Enum.filter(vals,&filter_nulls/1) |> Enum.count()}
  end
  def count(_first) do
    {:error,"Unsupported function variant for count/1"}
  end
  @doc """
  `MIN(field)`
  """
  def min([]) do
    {:ok,nil}
  end
  def min(vals) do
    {:ok,Enum.filter(vals,&filter_nulls/1) |> Enum.min(fn -> nil end)}
  end
  @doc """
  `MAX(field)`
  """
  def max([]) do
    {:ok,nil}
  end
  def max(vals) do
    {:ok,Enum.filter(vals,&filter_nulls/1) |> Enum.max(fn -> nil end)}
  end
  @doc """
  `AVG(field)`
  """
  def avg([]) do
    {:ok,nil}
  end
  def avg(vals) do
    nils_removed = Enum.filter(vals,&filter_nulls/1)
    case nils_removed do
    [_head|_tail] -> case Enum.find(nils_removed,fn val -> !is_number(val) end) do
        nil ->
          filtered = Enum.filter(vals,fn val -> is_number(val) end)
          count = Enum.count(filtered)
          sum = Enum.sum(filtered)
          avg = if count > 0 do sum/count else 0 end
          {:ok,avg}
        _ -> {:error,"Invalid values for avg()"}
      end
    [] -> {:ok,nil}
    end
  end
  @doc """
  `SUM(field)`
  """
  def sum([]) do
    {:ok,nil}
  end
  def sum(vals) do
    nils_removed = Enum.filter(vals,&filter_nulls/1)
    case nils_removed do
    [_head|_tail] -> case Enum.find(nils_removed,fn val -> !is_number(val) end) do
        nil ->
          filtered = Enum.filter(vals,fn val -> is_number(val) end)
          {:ok,filtered |> Enum.sum()}
        _ -> {:error,"Invalid values for sum()"}
      end
    [] -> {:ok,nil}
    end
  end
  # End Aggregate Functions #

end
