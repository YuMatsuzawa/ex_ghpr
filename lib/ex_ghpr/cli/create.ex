use Croma

defmodule ExGHPR.CLI.Create do
  alias Croma.Result, as: R
  alias ExGHPR.Github
  import ExGHPR.{Util, CLI}

  @moduledoc false

  defun ensure_current_branch_pushed_to_origin(
      %Git.Repository{} = repo,
      current_branch :: v[String.t],
      username       :: v[String.t],
      token          :: v[String.t]) :: R.t(term) do
    origin_url = case Git.remote(repo, ["get-url", "origin"]) do
      {:error, _  } -> exit_with_error("Cannot find `origin` remote")
      {:ok   , url} -> url
    end
    origin_url_with_auth = case URI.parse(origin_url) do
      %URI{scheme: "https", host: "github.com", path: path} ->
        "https://#{username}:#{token}@github.com#{String.rstrip(path, ?\n)}" # Yes, this way you can push without entering password
      _ssh_url -> origin_url
    end
    Git.push(repo, [origin_url_with_auth, current_branch])
  end

  defun ensure_pull_requested(
      opts           :: Keyword.t,
      %Git.Repository{} = repo,
      current_branch :: v[String.t],
      username       :: v[String.t],
      token          :: v[String.t],
      tracker_url    :: nil | String.t) :: R.t(term) do
    api_url = Github.pull_request_api_url(repo, validate_remote(opts[:remote], "origin"))
    |> R.map_error(&exit_with_error(inspect(&1)))
    |> R.get
    head = case validate_fork(opts[:fork]) do
      nil  -> current_branch
      fork -> "#{fork}:#{current_branch}"
    end
    base = validate_base(opts[:base], "master")
    Github.existing_pull_request(api_url, username, token, head, base)
    |> R.bind(fn
      nil ->
        title = validate_title(opts[:title], current_branch)
        body = validate_message(opts[:message], calc_body(current_branch, tracker_url))
        Github.create_pull_request(api_url, username, token, title, head, base, body)
      url -> {:ok, url}
    end)
  end

  defp   calc_body(_branch_name, nil), do: ""
  defunp calc_body(branch_name :: v[String.t], tracker_url) :: String.t do
    case Regex.named_captures(~r/\A(?<issue_num>\d+)_/, branch_name) do
      %{"issue_num" => num} -> "#{tracker_url}/#{num}"
      _                     -> ""
    end
  end
end