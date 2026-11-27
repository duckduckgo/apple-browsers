#!/usr/bin/env bash
#
# Attaches an image to an Asana task and, optionally, deletes the automatic
# "attached" activity entry for that upload, so the image only appears where
# it is referenced (e.g. inline in a comment via <img data-asana-gid="...">).
#
# Outputs (GITHUB_OUTPUT):
#   attachment-gid - GID of the created attachment
#
set -euo pipefail

asana_api="https://app.asana.com/api/1.0"
image_file="" # global so the EXIT trap can clean it up after main returns

# The task GID is the last long number in the task URL
extract_task_gid() {
  local task_url="$1"
  grep -oE '[0-9]{10,}' <<< "${task_url}" | tail -1
}

download_image() {
  local image_url="$1"
  local output_file="$2"
  curl -sfL --retry 3 "${image_url}" -o "${output_file}"
}

# Prints the GID of the new attachment
upload_attachment() {
  local task_gid="$1"
  local image_file="$2"
  local filename="$3"
  local content_type="$4"
  local response http_code body

  response="$(curl -sS --retry 3 -w '\n%{http_code}' \
    -H "Authorization: Bearer ${ASANA_ACCESS_TOKEN}" \
    --form-string "parent=${task_gid}" \
    -F "file=@${image_file};filename=${filename};type=${content_type}" \
    "${asana_api}/attachments")"
  http_code="$(tail -n1 <<< "${response}")"
  body="$(sed '$d' <<< "${response}")"

  if [[ "${http_code}" != 2* ]]; then
    echo "::error::Failed to upload the attachment (HTTP ${http_code}): $(jq -c '.errors // empty' <<< "${body}" 2>/dev/null)" >&2
    return 1
  fi
  jq -r '.data.gid' <<< "${body}"
}

# Prints the GID of the "attached" activity entry whose text mentions the file name, if any
find_attachment_story() {
  local task_gid="$1"
  local filename="$2"

  curl -sfS --retry 3 -H "Authorization: Bearer ${ASANA_ACCESS_TOKEN}" \
    "${asana_api}/tasks/${task_gid}/stories?opt_fields=resource_subtype,text" \
    | jq -r --arg filename "${filename}" \
      '[.data[] | select(.resource_subtype == "attachment_added" and ((.text // "") | contains($filename)))] | last | .gid // empty'
}

delete_story() {
  local story_gid="$1"
  curl -sfS -X DELETE -H "Authorization: Bearer ${ASANA_ACCESS_TOKEN}" \
    "${asana_api}/stories/${story_gid}" > /dev/null
}

main() {
  : "${ASANA_ACCESS_TOKEN:?Missing ASANA_ACCESS_TOKEN}"
  : "${ASANA_TASK_URL:?Missing ASANA_TASK_URL}"
  : "${IMAGE_URL:?Missing IMAGE_URL}"
  : "${FILENAME:?Missing FILENAME}"
  local content_type="${CONTENT_TYPE:-image/png}"
  local delete_attachment_story="${DELETE_ATTACHMENT_STORY:-true}"
  local task_gid attachment_gid story_gid

  task_gid="$(extract_task_gid "${ASANA_TASK_URL}" || true)"
  if [[ -z "${task_gid}" ]]; then
    echo "::error::Could not extract an Asana task GID from the task URL."
    exit 1
  fi

  image_file="$(mktemp)"
  trap 'rm -f "${image_file}"' EXIT
  download_image "${IMAGE_URL}" "${image_file}"

  attachment_gid="$(upload_attachment "${task_gid}" "${image_file}" "${FILENAME}" "${content_type}")"
  echo "Uploaded attachment ${attachment_gid}"
  echo "attachment-gid=${attachment_gid}" >> "${GITHUB_OUTPUT}"

  if [[ "${delete_attachment_story}" != "true" ]]; then
    return
  fi

  story_gid="$(find_attachment_story "${task_gid}" "${FILENAME}")"
  if [[ -z "${story_gid}" ]]; then
    echo "::warning::Attachment activity entry not found; nothing to remove."
  elif delete_story "${story_gid}"; then
    echo "Removed attachment activity entry ${story_gid}"
  else
    echo "::warning::Could not remove the attachment activity entry; the image is still attached."
  fi
}

main
