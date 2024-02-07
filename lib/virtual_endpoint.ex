#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule VirtualEndpoint do
  @moduledoc """
  Represents a Virtual Endpoint ("endpoint") in the `Metadata` repository.

  Definitions:

  * `:endpoint`: The Endpoint name in submitted casing (i.e. not lowercased)
  * `:model`: Associated Model

  """
@enforce_keys [:endpoint,:model]
@derive {Jason.Encoder,only: [:endpoint,:model]}
defstruct [:endpoint,:model]
end
