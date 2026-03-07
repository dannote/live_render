defmodule Example.Tools.GitHubRepo do
  @moduledoc """
  GitHub repo info using the public REST API (no auth, 60 req/hr).
  """

  use Jido.Action,
    name: "get_github_repo",
    description:
      "Get information about a public GitHub repository including stars, forks, issues, languages, and topics.",
    schema: [
      owner: [type: :string, required: true, doc: "Repository owner (e.g., 'vercel')"],
      repo: [type: :string, required: true, doc: "Repository name (e.g., 'next.js')"]
    ]

  @headers [{"accept", "application/vnd.github.v3+json"}]

  @impl true
  def run(%{owner: owner, repo: repo}, _context) do
    base = "https://api.github.com/repos/#{URI.encode(owner)}/#{URI.encode(repo)}"

    tasks = [
      Task.async(fn -> Req.get(base, headers: @headers) end),
      Task.async(fn -> Req.get("#{base}/languages", headers: @headers) end)
    ]

    [repo_result, lang_result] = Task.await_many(tasks, 10_000)

    with {:ok, %{status: 200, body: data}} <- repo_result do
      languages =
        case lang_result do
          {:ok, %{status: 200, body: langs}} when is_map(langs) ->
            total = langs |> Map.values() |> Enum.sum() |> max(1)

            langs
            |> Enum.sort_by(fn {_, bytes} -> bytes end, :desc)
            |> Enum.take(8)
            |> Enum.map(fn {lang, bytes} ->
              %{language: lang, percentage: round(bytes / total * 100)}
            end)

          _ ->
            []
        end

      {:ok,
       %{
         name: data["full_name"],
         description: data["description"],
         url: data["html_url"],
         stars: data["stargazers_count"],
         forks: data["forks_count"],
         openIssues: data["open_issues_count"],
         primaryLanguage: data["language"],
         license: get_in(data, ["license", "spdx_id"]) || "None",
         createdAt: data["created_at"],
         lastPush: data["pushed_at"],
         topics: data["topics"] || [],
         languages: languages
       }}
    else
      {:ok, %{status: 404}} -> {:error, "Repository not found: #{owner}/#{repo}"}
      {:ok, %{status: 403}} -> {:error, "GitHub API rate limit exceeded"}
      _ -> {:error, "Failed to fetch repo: #{owner}/#{repo}"}
    end
  end
end
