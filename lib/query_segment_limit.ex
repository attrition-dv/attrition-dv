#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule QuerySegmentLimit do
  @moduledoc """
  Represents a `LIMIT` clause in an SQL query (e.g. `LIMIT 1`)

  Offsets are currently NOT supported.

  Used in `Parsec`.

  Definitions:

  * `:limit`: Numeric limit on number of result rows.
  """
  defstruct [:limit]
end
