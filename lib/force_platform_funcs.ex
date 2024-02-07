#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule ForcePlatformFuncs do
  @moduledoc """
  Function Support Module that forces all functions (including scalar functions) to be executed at the platform level.

  This only impacts functions defined as `:scalar`. Other function types are always executed at the platform level.

  Used for Data Source types that do not support functions (e.g. flat-files, web APIs).
  """

  @doc """
  Checks support for the function defined by the passed attribute.

  Always fails to force functions to platform excecution.
  """
  def check_func_support(_attr) do
    {:error,"Function not found"}
  end
end
