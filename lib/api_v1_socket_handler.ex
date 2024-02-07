#####################################################################################################################
#
# Copyright 2023 - present William Crooks
#
# This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
# If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
# This Source Code Form is “Incompatible With Secondary Licenses”, as defined by the Mozilla Public License, v. 2.0.
#
#####################################################################################################################

defmodule APIV1SocketHandler do
  @moduledoc """
  `Plug.Router` for WebSocket API calls. Wrapper for `APIV1`.

  Supports JSON payloads only. Returns JSON.

  Handles requests sent to /api/v1/client/open_websocket.

  *Part of V1 API*
  """

  def init(state) do
  {:ok,state}
  end

  @doc """
  Accepts incoming WebSocket payloads and delegates to `APIV1`.

  Only supports text-based WebSocket messages.
  """
  def handle_in(msg,request_context) do
    {request,[opcode: :text]} = msg
    LogUtil.debug("START WebSocket call #{inspect request}")
    payload = case LogUtil.inspect(APIV1.handle(request,request_context,:websocket),label: "APIV1.handle/3 Response") do
      {:ok,{:file,filename}} -> File.stream!(filename) |> Enum.into([])
      {:ok,resp} -> resp
      {:error,_code,resp} -> resp
    end
    {:push,[{:text,payload}],request_context} |> LogUtil.pipe("END WebSocket call")
  end
end
