#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule PostgreSQLFuncs do
  @moduledoc """
  Function Support Module based on PostgreSQL version 15.

  This only impacts functions defined as `:scalar`. Other function types are always executed at the platform level.
  """
  @doc """
  Checks support for the function defined by the passed attribute.

  Returns a callback to this module if the function is supported.
  """
  def check_func_support(attr) do
    func = attr.name
    param_count = length(attr.params)
    case Kernel.function_exported?(__MODULE__,func,param_count) do
      true -> {:ok,{__MODULE__,func}}
      false -> {:error,"Function not found"}
    end
  end

  # Scalar Functions #

  @doc """
  `UPPER(field)`
  """
  def upper(%QueryComponentFuncField{field: param}) do
    {:ok,"UPPER(#{param})"}
  end
  def upper(_param) do
    {:error,"Unsupported function variant for upper/1"}
  end
  @doc """
  `LOWER(field)`
  """
  def lower(%QueryComponentFuncField{field: param}) do
    {:ok,"LOWER(#{param})"}
  end
  def lower(_param) do
    {:error,"Unsupported function variant for upper/1"}
  end

  # End Scalar Functions #

   # Scalar Varargs Functions #

  # UNSUPPORTED in this version #

  # Aggregate Functions #

  # UNSUPPORTED in this version #
end
