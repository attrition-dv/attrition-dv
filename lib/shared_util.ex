#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule SharedUtil do
  @moduledoc """
  Shared utility functions that don't fit anywhere else.

  May be called from any area of the code base, without explicit documentation.
  """
  @doc """
  Generate a version 4 UUID. Used for generating Request IDs for `DV`.
  """
  def gen_uuid() do
    UUID.uuid4()
  end
  @doc """
  Parses an SPN string in the form of service/hostname@DOMAIN into a map of key:value pairs.
  """
  def parse_spn(spn) do
    # SPNs have multiple formats, but the one we're supporting out of the box is e.g. service/hostname@DOMAIN
    rex = ~r/(?<service>[\w]{1,})\/(?<host>[\w\.]{1,})\@(?<domain>[\w\.]{1,})/
    case LogUtil.inspect(Regex.named_captures(rex,spn)) do
      %{} = captures -> {:ok,%{domain: captures["domain"],host: captures["host"],service: captures["service"]}}
      nil -> {:error,"Failed to extract components from #{inspect spn}!"}
    end
  end
end
