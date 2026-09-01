#!/usr/bin/env bash
set -euo pipefail

# This script runs only from the trusted base workflow. It never checks out or
# evaluates pull-request files. Its sole state-changing operation is a rerun
# of failed jobs from one previously completed pull_request_target run whose
# live source PR and head SHA have been checked immediately before the POST.

fail() {
  echo "::error::$1"
  exit 1
}

is_id() { [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]; }
is_sha() { [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]; }

readonly WORKFLOW_PATH='.github/workflows/cla.yml'
readonly TARGET_EVENT='pull_request_target'
readonly TARGET_BASE_REF='main'
readonly SIGN_PHRASE='I have read the CLA Document and I hereby sign the CLA'

[[ "${GH_REPO:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Invalid repository identity'
[[ "${CLA_GENERATION:-}" =~ ^v[0-9]+\.[0-9]+-action-[0-9a-f]{7,40}$ ]] ||
  fail 'Invalid CLA generation marker'

[[ "${EVENT_NAME:-}" == 'issue_comment' ]] || fail 'Unexpected event for CLA refresh'
[[ "${EVENT_ACTION:-}" == 'created' ]] || fail 'Unexpected issue-comment action'
[[ "${GATE_RESULT:-}" == 'success' && "${GATE_ADMITTED:-}" == 'true' ]] ||
  fail 'The exact CLA gate did not admit this comment'
is_id "${PR_NUMBER:-}" || fail 'Invalid pull request number'
is_id "${COMMENT_ID:-}" || fail 'Invalid comment ID'
[[ "${COMMENT_CREATED_AT:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] ||
  fail 'Invalid comment timestamp'
[[ "${COMMENT_USER_TYPE:-}" == 'User' ]] || fail 'Only human users may request a CLA refresh'
is_id "${COMMENT_USER_ID:-}" || fail 'Invalid comment user ID'
[[ -n "${COMMENT_USER_LOGIN:-}" ]] || fail 'Missing comment user login'
comment_user_login_lower="$(printf '%s' "${COMMENT_USER_LOGIN}" | tr '[:upper:]' '[:lower:]')"
case "${comment_user_login_lower}" in
  *'[bot]') fail 'Bot comments cannot request a CLA refresh' ;;
esac
[[ "${COMMENT_BODY:-}" == "recheck" || "${COMMENT_BODY:-}" == "${SIGN_PHRASE}" ]] ||
  fail 'Comment is not an accepted CLA command'
[[ "${WRITER_RESULT:-}" == 'success' ]] || fail 'The current CLA signer did not succeed'
if [[ "${COMMENT_BODY}" == "${SIGN_PHRASE}" ]]; then
  [[ "${PREFLIGHT_RESULT:-}" == 'success' &&
     "${SIGNER_AUTHORIZED:-}" == 'true' ]] ||
    fail 'The signing comment did not pass authenticated preflight'
fi

pr_json="$(gh api "repos/${GH_REPO}/pulls/${PR_NUMBER}" 2>/dev/null)" ||
  fail 'Could not query the live pull request'
jq -e \
  --arg repo "${GH_REPO}" \
  --argjson number "${PR_NUMBER}" \
  --arg base "${TARGET_BASE_REF}" \
  '.number == $number and
   .state == "open" and
   .base.ref == $base and
   .base.repo.full_name == $repo and
   (.head.sha | type == "string") and
   (.head.sha | test("^[0-9a-f]{40}$")) and
   (.head.ref | type == "string" and length > 0 and (test("[\\r\\n]") | not)) and
   (.head.repo | type == "object") and
   (.head.repo.full_name | type == "string" and length > 0) and
   (.head.repo.id | type == "number" and . > 0) and
   (.user.id | type == "number" and . > 0)' \
  <<<"${pr_json}" >/dev/null || fail 'The live pull request is not a valid open main pull request'

head_sha="$(jq -r '.head.sha' <<<"${pr_json}")"
head_ref="$(jq -r '.head.ref' <<<"${pr_json}")"
head_repo="$(jq -r '.head.repo.full_name' <<<"${pr_json}")"
head_repo_id="$(jq -r '.head.repo.id' <<<"${pr_json}")"
opener_id="$(jq -r '.user.id' <<<"${pr_json}")"
is_sha "${head_sha}" || fail 'The live pull request head SHA is invalid'
is_id "${head_repo_id}" || fail 'The live pull request head repository ID is invalid'
is_id "${opener_id}" || fail 'The live pull request opener ID is invalid'
if [[ "${COMMENT_BODY}" == "${SIGN_PHRASE}" ]]; then
  # The maintained preflight authenticates the signer against the live PR
  # identities. It may authorize an authenticated co-author or committer, so
  # do not impose a second opener-only rule here. The numeric opener allowlist
  # remains enforced by the action itself.
  :
else
  if [[ "${COMMENT_USER_ID}" != "${opener_id}" ]]; then
    case "${COMMENT_ASSOCIATION:-}" in
      OWNER|MEMBER|COLLABORATOR) ;;
      *) fail 'Only the pull request author or a trusted repository participant may recheck the CLA' ;;
    esac
  fi
fi

# Resolve the workflow ID by exact path and active state. The API paginates
# workflow definitions, so inspect a bounded window instead of assuming the
# CLA workflow is in the first 100 entries.
workflow_pages='[]'
workflow_page_count=0
for workflow_page_number in $(seq 1 10); do
  workflow_page="$(gh api \
    --method GET \
    --raw-field per_page=100 \
    --raw-field page="${workflow_page_number}" \
    "repos/${GH_REPO}/actions/workflows" 2>/dev/null)" ||
    fail 'Could not query repository workflows'
  jq -e '. | type == "object" and (.workflows | type == "array" and length <= 100)' \
    <<<"${workflow_page}" >/dev/null ||
    fail 'The repository workflow response is malformed or oversized'
  workflow_pages="$(jq -c --argjson page "${workflow_page}" '. + [$page]' <<<"${workflow_pages}")"
  workflow_page_count="$(jq -r '.workflows | length' <<<"${workflow_page}")"
  (( workflow_page_count < 100 )) && break
done
(( workflow_page_count < 100 )) ||
  fail 'The repository workflow list is full after the bounded page window'
workflow_id="$(jq -r \
  --arg path "${WORKFLOW_PATH}" \
  '[.[] | .workflows[]? | select(.path == $path and .state == "active") | .id]
   | if length == 1 and (.[0] | type == "number" and . > 0) then .[0] else empty end' \
  <<<"${workflow_pages}")"
is_id "${workflow_id}" || fail 'The trusted CLA workflow is not uniquely active'

# A lifecycle run can still be queued when the contributor posts the signing
# comment. Poll a bounded number of times, and bind every candidate to the
# exact live head instead of relying on the comment timestamp. GitHub does not
# expose an event ID that links the two runs, so the head/base/workflow checks
# are the authorization boundary.
candidate=''
max_attempts=12
readonly MAX_RUN_PAGES=10
for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  runs_json='[]'
  run_page_count=100
  for run_page_number in $(seq 1 "${MAX_RUN_PAGES}"); do
    runs_page="$(gh api \
      --method GET \
      --raw-field event="${TARGET_EVENT}" \
      --raw-field branch="${head_ref}" \
      --raw-field per_page=100 \
      --raw-field page="${run_page_number}" \
      "repos/${GH_REPO}/actions/workflows/${workflow_id}/runs" 2>/dev/null)" ||
      fail 'Could not query CLA workflow runs'
    jq -e '. | type == "object" and (.workflow_runs | type == "array" and length <= 100)' \
      <<<"${runs_page}" >/dev/null ||
      fail 'The CLA workflow run response is malformed or oversized'
    runs_json="$(jq -c --argjson page "${runs_page}" '. + [$page]' <<<"${runs_json}")"
    run_page_count="$(jq -r '.workflow_runs | length' <<<"${runs_page}")"
    (( run_page_count < 100 )) && break
  done
  candidate="$(jq -c \
    --arg path "${WORKFLOW_PATH}" \
    --arg event "${TARGET_EVENT}" \
    --argjson workflow_id "${workflow_id}" \
    --arg sha "${head_sha}" \
    --arg ref "${head_ref}" \
    --arg repo "${GH_REPO}" \
    --arg head_repo "${head_repo}" \
    --argjson head_repo_id "${head_repo_id}" \
    --argjson number "${PR_NUMBER}" \
    '[.[] | .workflow_runs[]?
      | select(
          .path == $path and
          .event == $event and
          (.workflow_id | type == "number") and .workflow_id == $workflow_id and
          (.head_sha | type == "string") and .head_sha == $sha and
          .head_branch == $ref and
          (.id | type == "number" and . > 0) and
          (.status | type == "string") and
          ((.conclusion == null) or (.conclusion | type == "string")) and
          (.created_at | type == "string") and
          ((.head_repository | type == "object" and
            .full_name == $head_repo and .id == $head_repo_id) or
           (.head_repository == null and $head_repo == $repo)) and
          ((.pull_requests == null or (.pull_requests | type == "array")) and
           (if ((.pull_requests // []) | length) == 0 then true else
              any(.pull_requests[]?; (.number | type == "number") and .number == $number)
            end))
        )
      | {id, head_sha, head_branch, status, conclusion, created_at, pull_requests, head_repository}
    ] | sort_by([.created_at, .id]) | if length > 0 then .[-1] else empty end' \
    <<<"${runs_json}")"
  if [[ "${run_page_count}" == 100 ]]; then
    fail 'The CLA workflow run list is full after the bounded page window'
  fi
  if [[ -n "${candidate}" ]]; then
    candidate_status="$(jq -r '.status' <<<"${candidate}")"
    candidate_conclusion="$(jq -r '.conclusion // ""' <<<"${candidate}")"
    case "${candidate_status}" in
      completed)
        case "${candidate_conclusion}" in
          failure) break ;;
          success)
            echo '::notice::The latest exact-head CLA lifecycle run already succeeded; no refresh is needed.'
            exit 0
            ;;
          *) fail 'The latest exact-head CLA lifecycle run has a non-rerunnable conclusion' ;;
        esac
        ;;
      queued|in_progress|pending|requested|waiting) ;;
      *) fail 'The latest exact-head CLA lifecycle run has an unexpected status' ;;
    esac
  fi
  if (( attempt < max_attempts )); then
    sleep 5
  fi
done
[[ -n "${candidate}" ]] || fail 'No exact-head CLA lifecycle run appeared during the bounded wait'
[[ "$(jq -r '.status' <<<"${candidate}")" == 'completed' &&
   "$(jq -r '.conclusion // ""' <<<"${candidate}")" == 'failure' ]] ||
  fail 'The exact-head CLA lifecycle run did not finish with a rerunnable failure during the bounded wait'
run_id="$(jq -r '.id' <<<"${candidate}")"
is_id "${run_id}" || fail 'The selected CLA run ID is invalid'

validate_run() {
  local payload="$1"
  jq -e \
    --argjson id "${run_id}" \
    --argjson workflow_id "${workflow_id}" \
    --arg event "${TARGET_EVENT}" \
    --arg path "${WORKFLOW_PATH}" \
    --arg sha "${head_sha}" \
    --arg ref "${head_ref}" \
    --arg repo "${GH_REPO}" \
    --arg head_repo "${head_repo}" \
    --argjson head_repo_id "${head_repo_id}" \
    --argjson number "${PR_NUMBER}" \
    '.id == $id and .workflow_id == $workflow_id and .path == $path and .event == $event and
     .head_sha == $sha and .head_branch == $ref and
     .status == "completed" and .conclusion == "failure" and
     (.created_at | type == "string") and
     ((.head_repository | type == "object" and
       .full_name == $head_repo and .id == $head_repo_id) or
      (.head_repository == null and $head_repo == $repo)) and
     ((.pull_requests == null or (.pull_requests | type == "array")) and
      (if ((.pull_requests // []) | length) == 0 then true else
         any(.pull_requests[]?; (.number | type == "number") and .number == $number)
       end))' \
    <<<"${payload}" >/dev/null
}

validate_unique_open_head() {
  local head_owner head_name matches
  head_owner="${head_repo%%/*}"
  head_name="${head_repo#*/}"
  [[ "${head_owner}" != "${head_repo}" && -n "${head_owner}" && -n "${head_name}" ]] ||
    fail 'The pull request head repository name is invalid'
  local open_pr_pages='[]' open_pr_page_count=100
  for open_pr_page_number in $(seq 1 10); do
    open_pr_page="$(gh api --method GET \
      --raw-field state=open --raw-field base="${TARGET_BASE_REF}" \
      --raw-field head="${head_owner}:${head_ref}" --raw-field per_page=100 \
      --raw-field page="${open_pr_page_number}" \
      "repos/${GH_REPO}/pulls" 2>/dev/null)" ||
      fail 'Could not query open pull requests for the exact head'
    jq -e '. | type == "array" and length <= 100' <<<"${open_pr_page}" >/dev/null ||
      fail 'The open pull request response is malformed or oversized'
    open_pr_pages="$(jq -c --argjson page "${open_pr_page}" '. + [$page]' <<<"${open_pr_pages}")"
    open_pr_page_count="$(jq -r 'length' <<<"${open_pr_page}")"
    (( open_pr_page_count < 100 )) && break
  done
  (( open_pr_page_count < 100 )) ||
    fail 'The open pull request list is full after the bounded page window'
  matches="$(jq -r \
    --arg repo "${GH_REPO}" --arg base "${TARGET_BASE_REF}" \
    --arg ref "${head_ref}" --arg head_repo "${head_repo}" \
    --argjson head_repo_id "${head_repo_id}" --argjson number "${PR_NUMBER}" \
    --arg sha "${head_sha}" \
    '[.[]?[]? | select(.number == $number and .state == "open" and
      .base.ref == $base and .base.repo.full_name == $repo and
      .head.ref == $ref and .head.sha == $sha and
      .head.repo.full_name == $head_repo and .head.repo.id == $head_repo_id)] | length' \
    <<<"${open_pr_pages}")" ||
    fail 'The open pull request response is malformed'
  [[ "${matches}" == 1 ]] || fail 'The exact head is not uniquely associated with this pull request'
}

run_json="$(gh api "repos/${GH_REPO}/actions/runs/${run_id}" 2>/dev/null)" ||
  fail 'Could not recheck the selected CLA run'
validate_run "${run_json}" || fail 'The selected CLA run no longer matches the exact failed PR head'
run_has_association="$(jq -r 'if ((.pull_requests // []) | length) > 0 then "true" else "false" end' <<<"${run_json}")"
if [[ "${run_has_association}" != 'true' ]]; then
  validate_unique_open_head
fi

# The jobs endpoint is paginated. Inspect every page before authorizing a
# rerun, because rerun-failed-jobs executes every failed job in the run.
fetch_jobs_for_run() {
  local target_run_id="$1"
  local pages='[]'
  local page_count=100
  local page_number page_json
  for page_number in $(seq 1 10); do
    page_json="$(gh api \
      --method GET \
      --raw-field per_page=100 \
      --raw-field page="${page_number}" \
      "repos/${GH_REPO}/actions/runs/${target_run_id}/jobs" 2>/dev/null)" ||
      fail 'Could not query jobs for the selected CLA run'
    jq -e '. | type == "object" and (.jobs | type == "array" and length <= 100)' \
      <<<"${page_json}" >/dev/null || fail 'The selected CLA run jobs response is malformed or oversized'
    pages="$(jq -c --argjson page "${page_json}" '. + [$page]' <<<"${pages}")"
    page_count="$(jq -r '.jobs | length' <<<"${page_json}")"
    if (( page_count < 100 )); then
      break
    fi
  done
  (( page_count < 100 )) || fail 'The selected CLA run jobs list is full after the bounded page window'
  jq -c '[.[] | .jobs[]?]' <<<"${pages}"
}

validate_failed_jobs() {
  local payload="$1"
  local failed_jobs
  jq -e 'type == "array" and length > 0 and
         all(.[]; .status == "completed" and (.conclusion | type == "string"))' \
    <<<"${payload}" >/dev/null || fail 'The selected CLA run jobs are incomplete or malformed'
  failed_jobs="$(jq -c '[.[] | select(.conclusion != "success" and .conclusion != "skipped")]' <<<"${payload}")"
  jq -e \
    --argjson expected_run_id "${run_id}" \
    --arg expected_head_sha "${head_sha}" \
    --arg generation "${CLA_GENERATION}" \
    'length > 0 and all(.[];
      (.id | type == "number" and . > 0) and
      (.run_id | type == "number" and . == $expected_run_id) and
      (.head_sha | type == "string" and . == $expected_head_sha) and
      .conclusion == "failure" and
      (.name == "CLA Signer" or .name == "CLA Assistant v2") and
      any(.steps[]?;
        .name == ("CLA generation " + $generation) and
        .status == "completed" and .conclusion == "success"
      ))' \
    <<<"${failed_jobs}" >/dev/null ||
    fail 'The selected run contains an unexpected failed job or stale CLA generation'
}

jobs_json="$(fetch_jobs_for_run "${run_id}")" || fail 'Could not query jobs for the selected CLA run'
validate_failed_jobs "${jobs_json}"

# Recheck both live objects immediately before the only state-changing call.
latest_pr_json="$(gh api "repos/${GH_REPO}/pulls/${PR_NUMBER}" 2>/dev/null)" ||
  fail 'Could not recheck the pull request before refresh'
jq -e \
  --arg repo "${GH_REPO}" --arg base "${TARGET_BASE_REF}" \
  --argjson number "${PR_NUMBER}" --arg sha "${head_sha}" \
  --arg ref "${head_ref}" --arg head_repo "${head_repo}" \
  --argjson head_repo_id "${head_repo_id}" \
  '.number == $number and .state == "open" and .base.ref == $base and
   .base.repo.full_name == $repo and .head.sha == $sha and
   .head.ref == $ref and .head.repo.full_name == $head_repo and
   .head.repo.id == $head_repo_id' <<<"${latest_pr_json}" >/dev/null ||
  fail 'The pull request changed while preparing the refresh'
final_run_json="$(gh api "repos/${GH_REPO}/actions/runs/${run_id}" 2>/dev/null)" ||
  fail 'Could not recheck the CLA run before refresh'
validate_run "${final_run_json}" || fail 'The CLA run changed while preparing the refresh'
run_has_association="$(jq -r 'if ((.pull_requests // []) | length) > 0 then "true" else "false" end' <<<"${final_run_json}")"
if [[ "${run_has_association}" != 'true' ]]; then
  validate_unique_open_head
fi
final_jobs_json="$(fetch_jobs_for_run "${run_id}")" || fail 'Could not recheck jobs for the selected CLA run'
validate_failed_jobs "${final_jobs_json}"

gh api --method POST \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  "repos/${GH_REPO}/actions/runs/${run_id}/rerun-failed-jobs" >/dev/null 2>&1 ||
  fail 'Could not rerun the exact failed CLA jobs'
echo "Requested an exact-head CLA refresh for PR ${PR_NUMBER}, run ${run_id}, head ${head_sha}"
