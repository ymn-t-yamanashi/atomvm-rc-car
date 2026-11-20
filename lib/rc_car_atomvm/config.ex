defmodule RcCarAtomvm.Config do
  @moduledoc "Non-secret configuration for the AtomVM firmware."

  @device_id "xiao-esp32-s3-01"
  @server_url "wss://rc.ymnbuild.org/ws"

  @type endpoint :: %{
          scheme: :ws | :wss,
          host: binary(),
          port: pos_integer(),
          path: binary()
        }

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

  @spec server_endpoint() :: {:ok, endpoint()} | {:error, atom()}
  def server_endpoint, do: parse_server_url(@server_url)

  @spec parse_server_url(binary()) :: {:ok, endpoint()} | {:error, :invalid_server_url}
  def parse_server_url(<<"ws://", rest::binary>>), do: parse_authority(:ws, rest)
  def parse_server_url(<<"wss://", rest::binary>>), do: parse_authority(:wss, rest)
  def parse_server_url(_value), do: {:error, :invalid_server_url}

  @spec device_id() :: binary()
  def device_id, do: @device_id

  defp parse_authority(scheme, rest) do
    {authority, path} = split_path(rest)

    with false <- authority == <<>>,
         {:ok, host, port} <- parse_host_port(scheme, authority),
         true <- valid_path?(path) do
      {:ok, %{scheme: scheme, host: host, port: port, path: path}}
    else
      _ -> {:error, :invalid_server_url}
    end
  end

  defp split_path(rest) do
    case :binary.match(rest, "/") do
      {position, _length} ->
        {
          :erlang.binary_part(rest, 0, position),
          :erlang.binary_part(rest, position, byte_size(rest) - position)
        }

      :nomatch ->
        {rest, "/ws"}
    end
  end

  defp parse_host_port(scheme, authority) do
    case :binary.match(authority, ":") do
      :nomatch ->
        {:ok, authority, default_port(scheme)}

      {position, _length} ->
        host = :erlang.binary_part(authority, 0, position)

        port_binary =
          :erlang.binary_part(authority, position + 1, byte_size(authority) - position - 1)

        with false <- host == <<>>,
             {:ok, port} <- parse_port(port_binary) do
          {:ok, host, port}
        else
          _ -> {:error, :invalid_server_url}
        end
    end
  end

  defp parse_port(port_binary) do
    try do
      port = :erlang.binary_to_integer(port_binary)

      if port in 1..65_535 do
        {:ok, port}
      else
        {:error, :invalid_server_url}
      end
    catch
      :error, :badarg -> {:error, :invalid_server_url}
    end
  end

  defp default_port(:ws), do: 80
  defp default_port(:wss), do: 443

  defp valid_path?(<<"/", _rest::binary>>), do: true
  defp valid_path?(_path), do: false
end
