defmodule Telnex.Lexer do
  @moduledoc """
  Implements a lexer for RFC 854.

  https://datatracker.ietf.org/doc/html/rfc854
  """
  defstruct buffer: "",
            sub_option: nil,
            sub: ""

  # @special_chars %{
  #   null: 0,
  #   lf: 10,
  #   # cr: 13, # ignore CR that's on its own
  #   bell: 7,
  #   bs: 8,
  #   ht: 9,
  #   vt: 11,
  #   ff: 12
  # }

  @basic_commands %{
    se: 240,
    nop: 241,
    data_mark: 242,
    break: 243,
    interrupt_process: 244,
    abort_output: 245,
    are_you_there: 246,
    erase_character: 247,
    erase_line: 248,
    go_ahead: 249,
    sb: 250
  }

  @option_commands %{
    will: 251,
    wont: 252,
    do: 253,
    dont: 254
  }

  # defguardp is_valid_char(char)
  #           when char in [10, 13, 7, 8, 9, 11, 12] or char in 32..126 or char in 240..255

  # @options %{
  #   binary_transmission: 0,
  #   echo: 1,
  #   reconnection: 2,
  #   suppress_go_ahead: 3,
  #   approximate_message_size_negotiation: 4,
  #   status: 5,
  #   timing_mark: 6,
  #   remote_controlled_trans_and_echo: 7,
  #   output_line_width: 8,
  #   output_page_size: 9,
  #   output_carriage_return_disposition: 10,
  #   output_horizontal_tab_stops: 11,
  #   output_horizontal_tab_disposition: 12,
  #   output_formfeed_disposition: 13,
  #   output_vertical_tabstops: 14,
  #   output_vertical_tab_disposition: 15,
  #   output_linefeed_disposition: 16,
  #   extended_ascii: 17,
  #   logout: 18,
  #   byte_macro: 19,
  #   data_entry_terminal: 20,
  #   supdup: 21,
  #   supdup_output: 22,
  #   send_location: 23,
  #   terminal_type: 24,
  #   end_of_record: 25,
  #   tacacs_user_identification: 26,
  #   output_marking: 27,
  #   terminal_location_number: 28,
  #   telnet_3270_regime: 29,
  #   x_3_pad: 30,
  #   window_size: 31,
  #   terminal_speed: 32,
  #   remote_flow_control: 33,
  #   linemode: 34,
  #   x_display_location: 35,
  #   environment_option: 36,
  #   authentication_option: 37,
  #   encryption_option: 38,
  #   new_environment_option: 39,
  #   tn3270e: 40,
  #   xauth: 41,
  #   charset: 42,
  #   telnet_remote_serial_port: 43,
  #   com_port_control_option: 44,
  #   suppress_local_echo: 45,
  #   telnet_start_tls: 46,
  #   kermit: 47,
  #   send_url: 48,
  #   forward_x: 49
  # }

  # @cr 13
  # @lf 10
  # @null 0

  @sb 250
  @se 240
  @iac 255

  def put(lexer, binary) do
    all_next(%{lexer | buffer: lexer.buffer <> binary})
  end

  defp all_next(lexer, acc \\ [])

  defp all_next(lexer, acc) do
    case next(lexer) do
      {:eof, lexer} -> {Enum.reverse(acc), lexer}
      {nil, lexer} -> all_next(lexer, acc)
      {token, lexer} -> all_next(lexer, [token | acc])
    end
  end

  # Subnegotiation: start
  defp next(%{buffer: <<@iac, @sb, option, rest::binary>>} = lexer) do
    lexer = %{lexer | buffer: rest, sub_option: option}
    {nil, lexer}
  end

  # Subnegotiation: end
  defp next(%{buffer: <<@iac, @se, rest::binary>>, sub_option: option, sub: sub} = lexer) do
    lexer = %{lexer | buffer: rest, sub_option: nil, sub: ""}
    {{:subnegotiation, option, sub}, lexer}
  end

  # sub: accumulate
  defp next(%{buffer: <<char, rest::binary>>, sub: sub, sub_option: option} = lexer)
       when is_integer(option) do
    lexer = %{lexer | buffer: rest, sub: sub <> <<char>>}
    {nil, lexer}
  end

  # ASCII text
  # defp next(%{buffer: <<char, rest::binary>>} = lexer) when char in 32..126 do
  #   lexer = %{lexer | buffer: rest}
  #   {<<char>>, lexer}
  # end

  # Newlines
  # If we just have the newline in the buffer, we need to wait for the next char
  # defp next(%{buffer: <<@cr>>} = lexer) do
  #   {:eof, lexer}
  # end

  # defp next(%{buffer: <<@cr, @lf, rest::binary>>} = lexer) do
  #   lexer = %{lexer | buffer: rest}
  #   {:cr_lf, lexer}
  # end

  # defp next(%{buffer: <<@cr, @null, rest::binary>>} = lexer) do
  #   lexer = %{lexer | buffer: rest}
  #   {:cr_nul, lexer}
  # end

  # Special characters
  # for {name, code} <- @special_chars do
  #   defp next(%{buffer: <<char, rest::binary>>} = lexer) when char == unquote(code) do
  #     lexer = %{lexer | buffer: rest}
  #     {unquote(name), lexer}
  #   end
  # end

  # Basic commands
  for {name, code} <- @basic_commands do
    defp next(%{buffer: <<@iac, unquote(code), rest::binary>>} = lexer) do
      lexer = %{lexer | buffer: rest}
      {unquote(name), lexer}
    end
  end

  # Commands with options
  for {name, code} <- @option_commands do
    defp next(%{buffer: <<@iac, unquote(code), option, rest::binary>>} = lexer) do
      lexer = %{lexer | buffer: rest}
      {{unquote(name), option}, %{lexer | buffer: rest}}
    end
  end

  # Special case: IAC IAC represents byte 255
  defp next(%{buffer: <<@iac, @iac, rest::binary>>} = lexer) do
    lexer = %{lexer | buffer: rest}
    {<<255>>, lexer}
  end

  # Invalid character
  # defp next(%{buffer: <<char, rest::binary>>} = lexer) when is_valid_char(char) do
  #   {nil, %{lexer | buffer: rest}}
  # end

  defp next(%{buffer: <<char, rest::binary>>} = lexer) do
    lexer = %{lexer | buffer: rest}
    {<<char>>, lexer}
  end

  # Empty buffer
  defp next(%{buffer: <<>>} = lexer) do
    {:eof, %{lexer | buffer: <<>>}}
  end
end
