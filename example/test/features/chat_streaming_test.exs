defmodule Features.ChatStreamingTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright, only: [screenshot: 2, type: 3, click: 2, click: 3]

  @tag timeout: 120_000
  test "homepage loads with input and suggestions", %{conn: conn} do
    conn
    |> visit("/")
    |> assert_has("input[name='prompt']")
    |> assert_has("button", text: "Weather comparison")
  end

  @tag timeout: 120_000
  test "user message bubble appears on submit", %{conn: conn} do
    conn
    |> visit("/")
    |> type("input[name='prompt']", "Hello from test")
    |> click("button[type='submit']")
    |> assert_has("div", text: "Hello from test", timeout: 5_000)
    |> screenshot("user-message.png")
  end

  @tag timeout: 120_000
  test "suggestion buttons submit prompt and trigger streaming", %{conn: conn} do
    conn
    |> visit("/")
    |> click("button", "Weather comparison")
    |> assert_has("div", text: "Compare the weather in New York, London, and Tokyo", timeout: 5_000)
    |> screenshot("suggestion-submitted.png")
  end

  @tag timeout: 180_000
  test "submitting weather prompt shows tools then streams widget", %{conn: conn} do
    conn
    |> visit("/")
    |> type("input[name='prompt']", "What is the weather in London?")
    |> click("button[type='submit']")
    # User message appears
    |> assert_has("div", text: "What is the weather in London?", timeout: 5_000)
    |> screenshot("01-user-message.png")
    # Tool calls appear
    |> assert_has("[data-tool]", timeout: 30_000)
    |> screenshot("02-tools.png")
    # Widget streams in
    |> assert_has("[data-live-render-id]", timeout: 90_000)
    |> screenshot("03-widget.png")
  end
end
