defmodule Features.ProgressiveStreamingTest do
  use PhoenixTest.Playwright.Case,
    async: false,
    headless: true

  import PhoenixTest.Playwright, only: [screenshot: 2, type: 3, click: 2, evaluate: 2, evaluate: 3]

  @tag timeout: 180_000
  test "widgets render progressively during streaming", %{conn: conn} do
    conn =
      conn
      |> visit("/")
      |> evaluate("""
        window.__specVersions = [];
        const poll = setInterval(() => {
          const el = document.querySelector('[data-spec-version]');
          const ver = el ? el.getAttribute('data-spec-version') : null;
          const renderEl = document.querySelector('[data-live-render-id]');
          const divs = renderEl ? renderEl.querySelectorAll('div').length : 0;
          const last = window.__specVersions[window.__specVersions.length - 1];
          if (!last || last.ver !== ver || last.divs !== divs) {
            window.__specVersions.push({t: Date.now(), ver: ver, divs: divs});
          }
        }, 50);
        window.__stop = () => clearInterval(poll);
      """)
      |> type("input[name='prompt']", "What is the weather in London?")
      |> click("button[type='submit']")

    conn = assert_has(conn, "[data-live-render-id]", timeout: 90_000)
    Process.sleep(5_000)

    conn
    |> evaluate("window.__stop(); JSON.stringify(window.__specVersions)", fn result ->
      states = Jason.decode!(result)
      IO.puts("\n=== SPEC VERSION TRACKING (50ms poll) ===")
      IO.puts("Total distinct states: #{length(states)}")

      for {s, i} <- Enum.with_index(states) do
        IO.puts("  ##{i}: version=#{s["ver"]} divs=#{s["divs"]}")
      end

      versions = Enum.map(states, & &1["ver"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      IO.puts("Unique versions seen: #{length(versions)} — #{inspect(versions)}")

      divs = Enum.map(states, & &1["divs"])
      IO.puts("Div progression: #{inspect(divs)}")

      assert length(versions) >= 5,
        "Expected >=5 spec versions in browser, got #{length(versions)}: #{inspect(versions)}"
    end)
    |> screenshot("progressive-result.png")
  end
end
