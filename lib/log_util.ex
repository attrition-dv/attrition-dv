#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule LogUtil do
  @moduledoc """
  Logging helpers. Standardizes format and handling of platform log calls.

  This is primarily future proofing so there's a centralized place to intercept/modify logging behavior.
  """

  @doc """
  Equivalent to `IO.inspect/2`. Accepts a :level option to control log levels (e.g. `LogUtil.log("test,level: :debug)`). Defaults to `:debug`.
  """
  def inspect(var,options \\ []) do
    label = Keyword.get(options,:label,"")
    level = Keyword.get(options,:level,:debug)
    apply(:logger,level,["#{label}: #{Kernel.inspect var}"])
    var
  end
  @doc """
  Equivalent to `:logger.:level/1` (e.g. `:logger.debug([str])`).

  Defaults to `:debug`.
  """
  def log(str,options \\ []) do
    level = Keyword.get(options,:level,:debug)
    apply(:logger,level,[str])
  end
  @doc """
  Pipeline friendly version of `LogUtil.log/2`.

  Accepts pipeline `input`, logs `str` according to `options`, and returns `input`.

  """
  def pipe(input,str,options \\ []) do
    LogUtil.log(str,options)
    input
  end
  @doc """
  Equivalent to calling `LogUtil.log(str,level: :debug)`
  """
  def debug(str) do
    log(str,level: :debug)
  end
  @doc """
  Equivalent to calling `Logutil.log(str,level: :error)`
  """
  def error(str) do
    log(str,level: :error)
  end
  @doc """
  Equivalent to calling `Logutil.log(str,level: :info)`
  """
  def info(str) do
    log(str,level: :info)
  end
end
