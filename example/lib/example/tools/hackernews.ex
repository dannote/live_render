defmodule Example.Tools.HackerNews do
  @moduledoc """
  Hacker News top stories using the Firebase API (free, no auth).
  """

  use Jido.Action,
    name: "get_hackernews_top",
    description:
      "Get the current top stories from Hacker News, including title, score, author, URL, and comment count.",
    schema: [
      count: [type: :pos_integer, required: true, doc: "Number of top stories to fetch (1-30)"]
    ]

  @impl true
  def run(%{count: count}, _context) do
    count = min(count, 30)

    case Req.get("https://hacker-news.firebaseio.com/v0/topstories.json") do
      {:ok, %{status: 200, body: ids}} when is_list(ids) ->
        stories =
          ids
          |> Enum.take(count)
          |> Task.async_stream(
            fn id ->
              case Req.get("https://hacker-news.firebaseio.com/v0/item/#{id}.json") do
                {:ok, %{status: 200, body: story}} when is_map(story) ->
                  %{
                    id: story["id"],
                    title: story["title"],
                    url:
                      story["url"] || "https://news.ycombinator.com/item?id=#{story["id"]}",
                    score: story["score"],
                    author: story["by"],
                    comments: story["descendants"] || 0,
                    hnUrl: "https://news.ycombinator.com/item?id=#{story["id"]}"
                  }

                _ ->
                  nil
              end
            end,
            max_concurrency: 10,
            timeout: 10_000
          )
          |> Enum.flat_map(fn
            {:ok, story} when not is_nil(story) -> [story]
            _ -> []
          end)

        {:ok, %{stories: stories, fetchedAt: DateTime.utc_now() |> DateTime.to_iso8601()}}

      _ ->
        {:error, "Failed to fetch Hacker News top stories"}
    end
  end
end
