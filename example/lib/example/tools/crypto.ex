defmodule Example.Tools.CryptoPrice do
  @moduledoc """
  Current crypto market data from CoinGecko (free, no key required).
  """

  use Jido.Action,
    name: "get_crypto_price",
    description:
      "Get current price, market cap, 24h change, and 7-day sparkline for a cryptocurrency.",
    schema: [
      coin_id: [
        type: :string,
        required: true,
        doc: "CoinGecko coin ID (e.g., 'bitcoin', 'ethereum', 'solana')"
      ]
    ]

  @impl true
  def run(%{coin_id: coin_id}, _context) do
    url =
      "https://api.coingecko.com/api/v3/coins/#{URI.encode(coin_id)}" <>
        "?localization=false&tickers=false&community_data=false&developer_data=false&sparkline=true"

    case Req.get(url) do
      {:ok, %{status: 200, body: data}} ->
        md = data["market_data"]

        sparkline =
          md["sparkline_7d"]["price"]
          |> sample(14)
          |> Enum.with_index()
          |> Enum.map(fn {price, i} ->
            %{date: "Day #{i + 1}", price: Float.round(price * 1.0, 2)}
          end)

        {:ok,
         %{
           id: data["id"],
           symbol: String.upcase(data["symbol"]),
           name: data["name"],
           rank: data["market_cap_rank"],
           price: md["current_price"]["usd"],
           marketCap: md["market_cap"]["usd"],
           volume24h: md["total_volume"]["usd"],
           change24h: Float.round((md["price_change_percentage_24h"] || 0) * 1.0, 2),
           change7d: Float.round((md["price_change_percentage_7d"] || 0) * 1.0, 2),
           high24h: md["high_24h"]["usd"],
           low24h: md["low_24h"]["usd"],
           sparkline7d: sparkline
         }}

      {:ok, %{status: 404}} ->
        {:error, "Cryptocurrency not found: #{coin_id}"}

      {:ok, %{status: 429}} ->
        {:error, "CoinGecko rate limit exceeded. Try again in a minute."}

      _ ->
        {:error, "Failed to fetch crypto data"}
    end
  end

  defp sample(list, max_points) do
    len = length(list)
    step = max(1, div(len, max_points))
    list |> Enum.take_every(step) |> Enum.take(max_points)
  end
end

defmodule Example.Tools.CryptoPriceHistory do
  @moduledoc """
  Historical crypto price data from CoinGecko (free, no key required).
  """

  use Jido.Action,
    name: "get_crypto_price_history",
    description:
      "Get historical price data for a cryptocurrency over a specified number of days.",
    schema: [
      coin_id: [type: :string, required: true, doc: "CoinGecko coin ID"],
      days: [type: :pos_integer, required: true, doc: "Number of days of history (1-365)"]
    ]

  @impl true
  def run(%{coin_id: coin_id, days: days}, _context) do
    url =
      "https://api.coingecko.com/api/v3/coins/#{URI.encode(coin_id)}/market_chart?vs_currency=usd&days=#{days}"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"prices" => prices}}} ->
        len = length(prices)
        step = max(1, div(len, 20))

        history =
          prices
          |> Enum.take_every(step)
          |> Enum.take(20)
          |> Enum.map(fn [ts, price] ->
            date =
              ts
              |> trunc()
              |> DateTime.from_unix!(:millisecond)
              |> Calendar.strftime("%b %d")

            %{date: date, price: Float.round(price * 1.0, 2)}
          end)

        {:ok, %{coinId: coin_id, days: days, priceHistory: history}}

      _ ->
        {:error, "Failed to fetch price history for #{coin_id}"}
    end
  end
end
