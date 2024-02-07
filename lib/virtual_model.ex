#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule VirtualModel do
  @moduledoc """
  Represents a Virtual Model ("model") in the `Metadata` repository.

  Definitions:

  * `:model`: The Model name in submitted casing (i.e. not lowercased)
  * `:query`: Model query

  """
@enforce_keys [:model,:query]
@derive {Jason.Encoder,only: [:model,:query]}
defstruct [:model,:query]
end
