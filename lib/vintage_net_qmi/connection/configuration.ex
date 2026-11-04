# SPDX-FileCopyrightText: 2022 Matt Ludwigs
# SPDX-FileCopyrightText: 2023 Frank Hunleth
#
# SPDX-License-Identifier: Apache-2.0
#
defmodule VintageNetQMI.Connection.Configuration do
  @moduledoc false

  # Configuration logic for a network connection

  # Items run in this order: the radio technologies and the initial EPS
  # bearer are set before the modem registers for the data call.
  @configuration_order [
    :radio_technologies_set,
    :initial_eps_bearer_set,
    :reporting_connection_stats
  ]
  @required_configuration_items [:radio_technologies_set, :initial_eps_bearer_set]

  @typedoc """
  A connection configuration

  * `:connection_stats` - if the device is configured for reporting connection
    stats
  * `:radio_technologies_set` - if the device is configured to use specified radio
    technologies
  * `:initial_eps_bearer_set` - if the LTE attach profile holds the configured
    initial EPS bearer settings

  The `:radio_technologies_set` and `:initial_eps_bearer_set` fields need to be
  marked as configured before the configuration is considered configured.
  Switching the radio technology during an established connection can have
  unknown side effects to the stability of the mobile connection, and changing
  the initial EPS bearer makes the modem register again.

  Establishing a connection before setting the connection stats reporting is a
  safe operation and does not need to be configured to for the configuration to
  be considered complete.
  """
  @type t() :: %{
          optional(:reporting_connection_stats) => boolean(),
          :radio_technologies_set => boolean(),
          :initial_eps_bearer_set => boolean()
        }

  @type configuration_setting() ::
          :reporting_connection_stats | :radio_technologies_set | :initial_eps_bearer_set

  @typedoc """
  A function that is called when trying to configure a modem setting

  This receives one of the configuration settings and expects a return value of
  `:ok` or `{:error, reason :: atom()}`. If the return is `:ok` this means the
  item was successfully configured and the configuration map will be updated.
  If the return is an error this means something did not work when trying to
  configure the setting and the configuration map will not update the setting to
  be considered configured.
  """
  @type configuration_callback() :: (configuration_setting() -> :ok | {:error, atom()})

  @doc """
  Create a new connection configuration with all fields marked as not configured
  """
  @spec new() :: t()
  def new() do
    %{
      reporting_connection_stats: false,
      radio_technologies_set: false,
      initial_eps_bearer_set: false
    }
  end

  @doc """
  """
  @spec run_configurations(t(), configuration_callback()) ::
          {:ok, t()} | {:error, atom(), configuration_setting(), t()}
  def run_configurations(configuration, func) do
    config_items = Enum.reject(@configuration_order, &Map.get(configuration, &1, true))

    case do_run_configurations(configuration, config_items, func) do
      {:error, _reason, _setting, _config} = error -> error
      config -> {:ok, config}
    end
  end

  defp do_run_configurations(configuration, config_settings, callback) do
    Enum.reduce_while(config_settings, configuration, fn setting, config ->
      case callback.(setting) do
        {:error, reason} ->
          {:halt, {:error, reason, setting, config}}

        _other ->
          new_config = setting_configured(config, setting)
          {:cont, new_config}
      end
    end)
  end

  @doc """
  Check if the required settings are configured
  """
  @spec required_configured?(t()) :: boolean()
  def required_configured?(config) do
    config
    |> Enum.filter(fn {config_item, _value} -> config_item in @required_configuration_items end)
    |> Enum.all?(fn {_, value} -> value end)
  end

  @doc """
  Check if the configuration is completely configured
  """
  @spec completely_configured?(t()) :: boolean()
  def completely_configured?(config) do
    Enum.reduce_while(config, true, fn
      {_setting, true}, acc -> {:cont, acc}
      {_setting, false}, _acc -> {:halt, false}
    end)
  end

  @doc """
  Set a setting to be configured
  """
  @spec setting_configured(t(), configuration_setting()) :: t()
  def setting_configured(config, setting) do
    Map.update!(config, setting, fn _ -> true end)
  end
end
