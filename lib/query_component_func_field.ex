#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentFuncField do
  @moduledoc """
  Represents a field in an SQL function (e.g. `LOWER(alias.field)`)

  Used in `Parsec`.

  Definitions:

  * `:src`: The targeted data source.
  * `:field`: The field name.
  """
  defstruct [:src,:field,:_index]
end
defimpl String.Chars,for: QueryComponentFuncField do
  def to_string(param) do
    "#{param.src}.#{param.field}"
  end
end
