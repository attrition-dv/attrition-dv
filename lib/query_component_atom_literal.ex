#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QueryComponentAtomLiteral do
  @moduledoc """
  Represents an atomized literal in an SQL query. An "atomized literal" is one which was converted to a known atom value (hardcoded in `Parsec`) during query parsing.

  Used in `Parsec` for the `DISTINCT` keyword (converting to `:distinct`)

  Definitions:

  * `:atom`: The atom representing the literal.
  * `:_index`: Position of the atom in the result set (INTERNAL only).
  * `:_drop`: Whether to remove the atom before returning the result set (INTERNAL only).
  * `:_applied`: Whether the atom was already applied (processed) during query processing (INTERNAL only).
  """
  defstruct [:atom]
end
defimpl String.Chars,for: QueryComponentAtomLiteral do
  def to_string(param) do
    Atom.to_string(param)
  end
end
