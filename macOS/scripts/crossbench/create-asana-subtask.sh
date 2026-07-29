#!/usr/bin/env bash
#
# Create one Asana subtask without reading the parent task or existing subtasks.
#
# Usage:
#   ASANA_ACCESS_TOKEN=... ./create-asana-subtask.sh \
#     <parent-task-gid> <name> <notes-file> <start-date> <due-date>

set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "Usage: $0 <parent-task-gid> <name> <notes-file> <start-date> <due-date>" >&2
  exit 2
fi
: "${ASANA_ACCESS_TOKEN:?ASANA_ACCESS_TOKEN is required}"

parent_task_gid="$1"
task_name="$2"
notes_file="$3"
start_date="$4"
due_date="$5"

if ! [[ "$parent_task_gid" =~ ^[0-9]+$ ]]; then
  echo "ERROR: parent task GID must be numeric." >&2
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

payload="$(jq -n \
  --arg name "$task_name" \
  --arg start_on "$start_date" \
  --arg due_on "$due_date" \
  --rawfile notes "$notes_file" \
  '{data: {
    name: $name,
    resource_subtype: "default_task",
    notes: $notes,
    start_on: $start_on,
    due_on: $due_on
  }}')"
response_file="$(mktemp)"
trap 'rm -f "$response_file"' EXIT

http_status="$(
  curl --silent --show-error \
    --request POST \
    --header "Authorization: Bearer $ASANA_ACCESS_TOKEN" \
    --header "Content-Type: application/json" \
    --data "$payload" \
    --output "$response_file" \
    --write-out '%{http_code}' \
    "https://app.asana.com/api/1.0/tasks/$parent_task_gid/subtasks"
)"

if [ "$http_status" != "201" ]; then
  echo "ERROR: Asana subtask creation returned HTTP $http_status." >&2
  jq -r '.errors[]?.message // empty' "$response_file" >&2 || true
  exit 1
fi

subtask_gid="$(jq -er '.data.gid' "$response_file")"
echo "created Asana subtask: https://app.asana.com/0/0/$subtask_gid"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "subtask-gid=$subtask_gid" >> "$GITHUB_OUTPUT"
fi
