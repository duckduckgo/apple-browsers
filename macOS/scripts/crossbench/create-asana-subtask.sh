#!/usr/bin/env bash
#
# Create one Asana alert task in a fixed project section, without reading the
# project's existing tasks.
#
# Usage:
#   ASANA_ACCESS_TOKEN=... [ASANA_FOLLOWERS=a@b.com,123] ./create-asana-subtask.sh \
#     <project-gid> <section-gid> <name> <notes-file> <start-date> <due-date> \
#     [attachment-file]
#
# ASANA_FOLLOWERS is an optional comma-separated list of collaborators to add to
# the new task. Asana accepts an email or a user GID for each entry. Blank
# entries are dropped, and an empty list omits the field entirely so the task
# keeps Asana's default collaborators.
#
# NOTE: placing the task into a project section via `memberships` on creation
# follows Asana's documented request shape, but it has not been exercised
# against the live API in this change. Verify the first real alert actually
# lands in the target section.

set -euo pipefail

if [ "$#" -lt 6 ] || [ "$#" -gt 7 ]; then
  echo "Usage: $0 <project-gid> <section-gid> <name> <notes-file> <start-date> <due-date> [attachment-file]" >&2
  exit 2
fi
: "${ASANA_ACCESS_TOKEN:?ASANA_ACCESS_TOKEN is required}"
ASANA_FOLLOWERS="${ASANA_FOLLOWERS:-}"

project_gid="$1"
section_gid="$2"
task_name="$3"
notes_file="$4"
start_date="$5"
due_date="$6"
attachment_file="${7:-}"

if ! [[ "$project_gid" =~ ^[0-9]+$ ]]; then
  echo "ERROR: project GID must be numeric." >&2
  exit 2
fi
if ! [[ "$section_gid" =~ ^[0-9]+$ ]]; then
  echo "ERROR: section GID must be numeric." >&2
  exit 2
fi
if [ ! -f "$notes_file" ]; then
  echo "ERROR: notes file not found: $notes_file" >&2
  exit 2
fi
if ! [[ "$start_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: start date must use YYYY-MM-DD." >&2
  exit 2
fi
if ! [[ "$due_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "ERROR: due date must use YYYY-MM-DD." >&2
  exit 2
fi

followers_json="$(jq -n --arg raw "$ASANA_FOLLOWERS" \
  '$raw
   | split(",")
   | map(sub("^ +";"") | sub(" +$";""))
   | map(select(length > 0))')"

payload="$(jq -n \
  --arg name "$task_name" \
  --arg start_on "$start_date" \
  --arg due_on "$due_date" \
  --arg project "$project_gid" \
  --arg section "$section_gid" \
  --rawfile notes "$notes_file" \
  --argjson followers "$followers_json" \
  '{data: ({
    name: $name,
    resource_subtype: "default_task",
    notes: $notes,
    start_on: $start_on,
    due_on: $due_on,
    projects: [$project],
    memberships: [{project: $project, section: $section}]
  } + (if ($followers | length) > 0 then {followers: $followers} else {} end))}')"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

http_status="$(
  curl --silent --show-error \
    --retry 3 --retry-delay 5 --retry-all-errors \
    --request POST \
    --header "Authorization: Bearer $ASANA_ACCESS_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    --output "$response_file" \
    --write-out '%{http_code}' \
    "https://app.asana.com/api/1.0/tasks"
)"

if [ "$http_status" != "201" ]; then
  echo "ERROR: Asana task creation returned HTTP $http_status." >&2
  jq -r '.errors[]?.message // empty' "$response_file" >&2 || true
  exit 1
fi

task_gid="$(jq -er '.data.gid' "$response_file")"
echo "created Asana task: https://app.asana.com/0/0/$task_gid"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "task-gid=$task_gid" >> "$GITHUB_OUTPUT"
fi

if [ -n "$attachment_file" ]; then
  if [ ! -f "$attachment_file" ]; then
    echo "WARNING: Asana attachment not found: $attachment_file" >&2
  else
    http_status="$(
      curl --silent --show-error \
        --retry 3 --retry-delay 5 --retry-all-errors \
        --request POST \
        --header "Authorization: Bearer $ASANA_ACCESS_TOKEN" \
        --form "parent=$task_gid" \
        --form "file=@$attachment_file" \
        --output "$response_file" \
        --write-out '%{http_code}' \
        "https://app.asana.com/api/1.0/attachments"
    )"
    if [ "$http_status" = "200" ]; then
      echo "attached diagnostics: $(basename "$attachment_file")"
    else
      echo "WARNING: Asana attachment upload returned HTTP $http_status." >&2
      jq -r '.errors[]?.message // empty' "$response_file" >&2 || true
    fi
  fi
fi
