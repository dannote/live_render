defmodule Example.Tools.Weather do
  @moduledoc """
  Weather tool using Open-Meteo API (free, no key required).
  """

  use Jido.Action,
    name: "get_weather",
    description:
      "Get current weather conditions and a 7-day forecast for a given city. " <>
        "Returns temperature, humidity, wind speed, weather conditions, and daily forecasts.",
    schema: [
      city: [type: :string, required: true, doc: "City name (e.g., 'New York', 'London')"]
    ]

  @weather_codes %{
    0 => "Clear sky",
    1 => "Mainly clear",
    2 => "Partly cloudy",
    3 => "Overcast",
    45 => "Foggy",
    48 => "Depositing rime fog",
    51 => "Light drizzle",
    53 => "Moderate drizzle",
    55 => "Dense drizzle",
    61 => "Slight rain",
    63 => "Moderate rain",
    65 => "Heavy rain",
    71 => "Slight snow",
    73 => "Moderate snow",
    75 => "Heavy snow",
    80 => "Slight rain showers",
    81 => "Moderate rain showers",
    82 => "Violent rain showers",
    95 => "Thunderstorm",
    96 => "Thunderstorm with slight hail",
    99 => "Thunderstorm with heavy hail"
  }

  @impl true
  def run(%{city: city}, _context) do
    with {:ok, location} <- geocode(city),
         {:ok, weather} <- fetch_weather(location) do
      forecast =
        Enum.zip([
          weather["daily"]["time"],
          weather["daily"]["weather_code"],
          weather["daily"]["temperature_2m_max"],
          weather["daily"]["temperature_2m_min"],
          weather["daily"]["precipitation_sum"]
        ])
        |> Enum.map(fn {date, code, high, low, precip} ->
          day =
            date
            |> Date.from_iso8601!()
            |> Calendar.strftime("%a")

          %{
            date: date,
            day: day,
            high: round(high),
            low: round(low),
            condition: describe_code(code),
            precipitation: precip
          }
        end)

      {:ok,
       %{
         city: location.name,
         country: location.country,
         current: %{
           temperature: round(weather["current"]["temperature_2m"]),
           feelsLike: round(weather["current"]["apparent_temperature"]),
           humidity: weather["current"]["relative_humidity_2m"],
           windSpeed: round(weather["current"]["wind_speed_10m"]),
           condition: describe_code(weather["current"]["weather_code"])
         },
         forecast: forecast
       }}
    end
  end

  defp geocode(city) do
    url =
      "https://geocoding-api.open-meteo.com/v1/search?name=#{URI.encode(city)}&count=1&language=en&format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: %{"results" => [loc | _]}}} ->
        {:ok,
         %{
           name: loc["name"],
           country: loc["country"],
           lat: loc["latitude"],
           lon: loc["longitude"],
           tz: loc["timezone"]
         }}

      _ ->
        {:error, "City not found: #{city}"}
    end
  end

  defp fetch_weather(loc) do
    url =
      "https://api.open-meteo.com/v1/forecast" <>
        "?latitude=#{loc.lat}&longitude=#{loc.lon}" <>
        "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m" <>
        "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum" <>
        "&temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch" <>
        "&timezone=#{URI.encode(loc.tz)}&forecast_days=7"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      _ -> {:error, "Failed to fetch weather data"}
    end
  end

  defp describe_code(code), do: Map.get(@weather_codes, code, "Unknown")
end
