defmodule RcCarAtomvm.Config do
  @moduledoc "Non-secret configuration for the AtomVM firmware."

  # Wi-Fi credentials are read from ESP32 NVS at runtime.
  @server_port 4000
  @server_path "/ws"
  @device_id "xiao-esp32-s3-01"

  @server_namespace :rc_car
  @server_host_key :server_host

  @spec wifi() ::
          {:ok, [{:ssid, binary()} | {:psk, binary()}]} | {:error, :missing_wifi_credentials}
  def wifi do
    with {:ok, ssid} <- :esp.nvs_fetch_binary(:atomvm, :sta_ssid),
         {:ok, psk} <- :esp.nvs_fetch_binary(:atomvm, :sta_psk),
         false <- ssid == <<>>,
         false <- psk == <<>> do
      {:ok, [ssid: ssid, psk: psk]}
    else
      _ -> {:error, :missing_wifi_credentials}
    end
  end

  @spec server_host() :: {:ok, :inet.ip_address()} | {:error, atom()}
  def server_host do
    case :esp.nvs_fetch_binary(@server_namespace, @server_host_key) do
      {:ok, value} ->
        case :inet.parse_address(:erlang.binary_to_list(value)) do
          {:ok, address} -> {:ok, address}
          _ -> {:error, :invalid_server_host}
        end

      _ ->
        {:error, :missing_server_host}
    end
  end

  @spec server_port() :: pos_integer()
  def server_port, do: @server_port

  @spec server_path() :: binary()
  def server_path, do: @server_path

  @spec device_id() :: binary()
  def device_id, do: @device_id
end
