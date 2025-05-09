# SPDX-FileCopyrightText: 2021 Frank Hunleth
# SPDX-FileCopyrightText: 2021 Jon Carstens
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.Cookbook do
  @moduledoc """
  Recipes for common QMI network configurations
  """

  @doc """
  Return a configuration for connecting to a cellular network by APN
  """
  @spec simple(String.t()) ::
          {:ok,
           %{type: VintageNetQMI, vintage_net_qmi: %{service_providers: [%{apn: String.t()}]}}}
  def simple(apn) when is_binary(apn) do
    {:ok,
     %{
       type: VintageNetQMI,
       vintage_net_qmi: %{
         service_providers: [%{apn: apn}]
       }
     }}
  end
end
