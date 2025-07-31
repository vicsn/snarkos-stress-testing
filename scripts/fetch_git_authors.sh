#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 https://github.com/ProvableHQ/snarkVM/compare/mainnet...staging" >&2
  exit 1
fi

url="$1"

# define the regexp separately (must NOT be quoted in the [[ =~ ]] test)
regex='^https?://github\.com/([^/]+)/([^/]+)/compare/([^./]+)\.\.\.([^./]+)'

# test & populate BASH_REMATCH
if [[ $url =~ $regex ]]; then
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[2]}"
  base="${BASH_REMATCH[3]}"
  head="${BASH_REMATCH[4]}"
else
  echo "✖ Invalid GitHub compare URL: $url" >&2
  exit 1
fi

echo "Owner = $owner"
echo "Repo  = $repo"
echo "Base  = $base"
echo "Head  = $head"


api="https://api.github.com/repos/${owner}/${repo}/compare/${base}...${head}"
per_page=100
page=1
declare -a all_authors

echo "Fetching commits from $base → $head in $owner/$repo..."

while :; do
  # fetch paginated results
  resp_headers=$(mktemp)
  body=$(curl -sSL -D "$resp_headers" \
    "${api}?page=${page}&per_page=${per_page}")

  # extract author.login (if available) or commit.author.name
  page_authors=()
  while IFS= read -r author; do
    page_authors+=("$author")
  done < <(
    echo "$body" \
      | jq -r '.commits[] | (.author.login // .commit.author.name)'
  )

  # if no commits returned, stop
  (( ${#page_authors[@]} )) || break

  all_authors+=( "${page_authors[@]}" )

  # stop if there's no “next” link in the headers
  if ! grep -q 'rel="next"' "$resp_headers"; then
    rm "$resp_headers"
    break
  fi

  rm "$resp_headers"
  ((page++))
done

# dedupe & sort
printf "@%s\n" "${all_authors[@]}" \
  | sort -u

exit 0
