defmodule BBS.View.Prompt do
  @moduledoc false

  defstruct [
    :name,
    :value,
    :length,
    :permitted,
    :immediate,
    :bell,
    :index,
    :placeholder,
    :format,
    :transform
  ]

  def new(name, opts) do
    length =
      case Keyword.get(opts, :length, 0..255) do
        number when is_integer(number) -> 0..number
        %Range{} = range -> range
      end

    %__MODULE__{
      name: name,
      value: "",
      length: length,
      permitted:
        Keyword.get(
          opts,
          :permitted,
          ~r/[a-zA-Z0-9]/
        ),
      immediate: Keyword.get(opts, :immediate, false),
      bell: Keyword.get(opts, :bell, false),
      index: 0,
      placeholder: Keyword.get(opts, :placeholder, ""),
      format: Keyword.get(opts, :format, ""),
      transform: Keyword.get(opts, :transform, & &1)
    }
  end

  def put(%{immediate: false} = prompt, "\r") do
    if String.length(prompt.value) >= prompt.length.first do
      {:halt, prompt.value}
    else
      {:cont, prompt, if(prompt.bell, do: "\a", else: "")}
    end
  end

  def put(prompt, ignore) when ignore in ["\n", "\0"] do
    {:cont, prompt, ""}
  end

  # backspace
  def put(%{index: 0} = prompt, "\b") do
    {:cont, prompt, ""}
  end

  def put(%{index: index} = prompt, "\b") when index > 0 do
    {pre, post} = String.split_at(prompt.value, prompt.index)
    new_index = prompt.index - 1
    new_pre = String.slice(pre, 0..-2//1)
    new_value = new_pre <> post
    prompt = %{prompt | value: new_value, index: new_index}

    trailing =
      case placeholder(prompt) do
        "" -> " " <> cursor_left(1)
        placeholder -> placeholder
      end

    output =
      "\b" <>
        prompt.format <>
        post <>
        trailing <> cursor_left(String.length(post)) <> IO.ANSI.reset()

    {:cont, prompt, output}
  end

  # some char
  def put(prompt, char) when is_binary(char) do
    char = prompt.transform.(char)

    if Regex.match?(prompt.permitted, char) && String.length(prompt.value) < prompt.length.last do
      # Allowed! Insert the char in the middle of the string
      {pre, post} = String.split_at(prompt.value, prompt.index)
      new_value = pre <> char <> post
      new_index = prompt.index + 1

      if prompt.immediate && String.length(new_value) == prompt.length.last do
        # Complete prompt if immediate and max length is reached
        {:halt, new_value}
      else
        # Not done yet, print the new character and any trailing characters
        # and move the cursor back to the right place
        prompt = %{prompt | value: new_value, index: new_index}

        output =
          prompt.format <>
            char <>
            post <> placeholder(prompt) <> cursor_left(String.length(post)) <> IO.ANSI.reset()

        {:cont, prompt, output}
      end
    else
      # Not allowed!
      {:cont, prompt, if(prompt.bell, do: "\a", else: "")}
    end
  end

  # Move left if possible
  def put(prompt, {:cursor_left, [count]}) do
    new_index = max(0, prompt.index - count)

    if new_index == prompt.index do
      {:cont, prompt, ""}
    else
      code = IO.ANSI.cursor_left(prompt.index - new_index)
      {:cont, %{prompt | index: new_index}, code}
    end
  end

  # Move right if possible
  def put(prompt, {:cursor_right, [count]}) do
    new_index = min(String.length(prompt.value) + 1, prompt.index + count)

    if new_index == String.length(prompt.value) + 1 do
      {:cont, prompt, ""}
    else
      code = IO.ANSI.cursor_right(new_index - prompt.index)
      {:cont, %{prompt | index: new_index}, code}
    end
  end

  def put(prompt, _), do: {:cont, prompt, ""}

  defp cursor_left(0), do: ""
  defp cursor_left(count), do: IO.ANSI.cursor_left(count)

  def placeholder(%{placeholder: ""}), do: ""

  def placeholder(prompt) do
    count = prompt.length.last - String.length(prompt.value)

    prompt.format <>
      String.duplicate(prompt.placeholder, count) <> cursor_left(count)
  end
end
