#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule DataSourceKerberosAuth do
  @moduledoc """
  Represents a Kerberos configuration for a specific data source.

  Currently only stores the textual representation of the Service Principal Name (SPN).
  """
    @enforce_keys [:spn]
    @derive {Jason.Encoder,only: [:spn]}
    defstruct [:spn]
end
