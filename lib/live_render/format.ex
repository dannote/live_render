defmodule LiveRender.Format do
  @moduledoc """
  Behaviour for spec format backends.

  A format defines how the LLM should encode UI specs (prompt),
  how to parse a complete response (parse), and how to
  incrementally build a spec from streaming chunks (stream).

  ## Built-in formats

  - `LiveRender.Format.JSONPatch` — JSONL RFC 6902 patches (progressive streaming)
  - `LiveRender.Format.JSONObject` — single JSON object with root/elements/state
  - `LiveRender.Format.OpenUILang` — compact line-oriented DSL (~50% fewer tokens)
  - `LiveRender.Format.A2UI` — Google's A2UI protocol (JSONL envelopes, interoperable)
  - `LiveRender.Format.YAML` — YAML wire format (requires `:yaml_elixir` dependency)

  ## Edit modes

  All JSON-based formats and YAML support multi-turn editing via RFC 7396 merge
  semantics. Pass `:current_spec` in opts to enable: the prompt instructs the LLM
  to output only changed keys, which are deep-merged into the existing spec.
  """

  @type spec :: %{String.t() => term()}
  @type stream_state :: term()
  @type event :: {:spec, spec()} | {:text, String.t()}

  @doc """
  Returns the system prompt section describing the output format.
  """
  @callback prompt(%{String.t() => module()}, [{atom(), String.t()}], keyword()) :: String.t()

  @doc """
  Parses a complete LLM response text into a spec map.
  """
  @callback parse(String.t(), keyword()) :: {:ok, spec()} | {:error, term()}

  @doc """
  Initializes streaming parser state.
  """
  @callback stream_init(keyword()) :: stream_state()

  @doc """
  Feeds a text chunk into the streaming parser.
  Returns updated state and a list of events.
  """
  @callback stream_push(stream_state(), String.t()) :: {stream_state(), [event()]}

  @doc """
  Finalizes the stream, flushing any buffered content.
  """
  @callback stream_flush(stream_state()) :: {stream_state(), [event()]}
end
