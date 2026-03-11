defmodule LiveRender.Format.OpenUILang.TokenizerTest do
  use ExUnit.Case, async: true

  alias LiveRender.Format.OpenUILang.Tokenizer

  describe "tokenize/1" do
    test "tokenizes a simple assignment" do
      assert {:ok, tokens} = Tokenizer.tokenize(~s|name = "hello"|)

      assert tokens == [
               {:identifier, "name"},
               :equals,
               {:string, "hello"}
             ]
    end

    test "tokenizes a component call" do
      assert {:ok, tokens} = Tokenizer.tokenize(~s|Heading("Title", "h2")|)

      assert tokens == [
               {:identifier, "Heading"},
               :lparen,
               {:string, "Title"},
               :comma,
               {:string, "h2"},
               :rparen
             ]
    end

    test "tokenizes numbers" do
      assert {:ok, tokens} = Tokenizer.tokenize("42")
      assert tokens == [{:number, 42}]

      assert {:ok, tokens} = Tokenizer.tokenize("3.14")
      assert tokens == [{:number, 3.14}]

      assert {:ok, tokens} = Tokenizer.tokenize("-1")
      assert tokens == [{:number, -1}]
    end

    test "tokenizes booleans and null" do
      assert {:ok, tokens} = Tokenizer.tokenize("true false null")
      assert tokens == [true, false, :null]
    end

    test "tokenizes arrays" do
      assert {:ok, tokens} = Tokenizer.tokenize("[a, b, c]")

      assert tokens == [
               :lbracket,
               {:identifier, "a"},
               :comma,
               {:identifier, "b"},
               :comma,
               {:identifier, "c"},
               :rbracket
             ]
    end

    test "tokenizes objects" do
      assert {:ok, tokens} = Tokenizer.tokenize(~s|{key: "val"}|)

      assert tokens == [
               :lbrace,
               {:identifier, "key"},
               :colon,
               {:string, "val"},
               :rbrace
             ]
    end

    test "handles newlines" do
      assert {:ok, tokens} = Tokenizer.tokenize("a\nb")
      assert tokens == [{:identifier, "a"}, :newline, {:identifier, "b"}]
    end

    test "handles escape sequences in strings" do
      assert {:ok, tokens} = Tokenizer.tokenize(~s|"hello\\"world"|)
      assert [{:string, ~s|hello"world|}] = tokens
    end

    test "skips comments" do
      assert {:ok, tokens} = Tokenizer.tokenize("a = b // comment\nc = d")

      assert tokens == [
               {:identifier, "a"},
               :equals,
               {:identifier, "b"},
               {:identifier, "c"},
               :equals,
               {:identifier, "d"}
             ]
    end

    test "handles empty input" do
      assert {:ok, []} = Tokenizer.tokenize("")
    end

    test "errors on unexpected characters" do
      assert {:error, _} = Tokenizer.tokenize("@invalid")
    end
  end
end
