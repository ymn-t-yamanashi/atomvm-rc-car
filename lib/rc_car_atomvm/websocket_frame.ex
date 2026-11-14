defmodule RcCarAtomvm.WebSocketFrame do
  @moduledoc "Small RFC 6455 frame codec for the AtomVM client."

  import Bitwise

  @type frame :: %{opcode: non_neg_integer(), payload: binary()}

  @spec encode_text(binary()) :: binary()
  def encode_text(payload), do: encode(1, payload)

  @spec encode_pong(binary()) :: binary()
  def encode_pong(payload), do: encode(10, payload)

  @spec decode(binary()) :: :more | {:error, atom()} | {:ok, frame(), binary()}
  def decode(buffer) when byte_size(buffer) < 2, do: :more

  def decode(
        <<fin::1, _rsv1::1, _rsv2::1, _rsv3::1, opcode::4, masked::1, length_code::7,
          rest::binary>>
      ) do
    with 1 <- fin,
         {:ok, payload_length, after_length} <- read_length(length_code, rest),
         {:ok, mask, payload} <- read_payload(masked, payload_length, after_length) do
      {:ok, %{opcode: opcode, payload: unmask(payload, mask)},
       rest_after_payload(masked, payload_length, after_length)}
    else
      0 -> {:error, :fragmented_frames_not_supported}
      :more -> :more
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode(opcode, payload) do
    mask = :crypto.strong_rand_bytes(4)
    masked_payload = unmask(payload, mask)
    length = byte_size(payload)

    header =
      cond do
        length <= 125 -> <<1::1, 0::3, opcode::4, 1::1, length::7>>
        length <= 65_535 -> <<1::1, 0::3, opcode::4, 1::1, 126::7, length::16>>
        true -> <<1::1, 0::3, opcode::4, 1::1, 127::7, length::64>>
      end

    <<header::binary, mask::binary, masked_payload::binary>>
  end

  defp read_length(length_code, rest) when length_code <= 125, do: {:ok, length_code, rest}
  defp read_length(126, <<length::16, rest::binary>>), do: {:ok, length, rest}
  defp read_length(127, <<length::64, rest::binary>>), do: {:ok, length, rest}
  defp read_length(126, _), do: :more
  defp read_length(127, _), do: :more

  defp read_payload(0, length, rest) when byte_size(rest) >= length do
    <<payload::binary-size(length), _rest::binary>> = rest
    {:ok, <<>>, payload}
  end

  defp read_payload(1, length, <<mask::binary-size(4), rest::binary>>)
       when byte_size(rest) >= length do
    <<payload::binary-size(length), _rest::binary>> = rest
    {:ok, mask, payload}
  end

  defp read_payload(_, _, _), do: :more

  defp rest_after_payload(0, length, rest),
    do: binary_part(rest, length, byte_size(rest) - length)

  defp rest_after_payload(1, length, <<_mask::binary-size(4), rest::binary>>),
    do: binary_part(rest, length, byte_size(rest) - length)

  defp unmask(payload, <<>>), do: payload

  defp unmask(payload, <<m1, m2, m3, m4>>) do
    unmask(payload, {m1, m2, m3, m4}, 0, <<>>)
  end

  defp unmask(<<>>, _mask, _index, acc), do: acc

  defp unmask(<<byte, rest::binary>>, mask, index, acc) do
    masked_byte = bxor(byte, mask_byte(mask, rem(index, 4)))
    unmask(rest, mask, index + 1, <<acc::binary, masked_byte>>)
  end

  defp mask_byte({m1, _m2, _m3, _m4}, 0), do: m1
  defp mask_byte({_m1, m2, _m3, _m4}, 1), do: m2
  defp mask_byte({_m1, _m2, m3, _m4}, 2), do: m3
  defp mask_byte({_m1, _m2, _m3, m4}, 3), do: m4
end
