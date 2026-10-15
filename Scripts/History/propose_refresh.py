import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

from generate_archive import OUTPUT, ROOT, semantic_content


PREFIX = 'chore/bundled-history-refresh'
ARCHIVE = OUTPUT.relative_to(ROOT).as_posix()
TITLE = '🔧 history: refresh bundled reference data'
BODY = '''## 🔗 Related issue

No linked issue.

## 📝 Summary

Refresh bundled reference observations through the latest completed month, including upstream corrections to the older Coin Metrics and selected Frankfurter archives. Preserve the data licences, notices and provenance.

## 🧪 Validation

Archive generator tests passed. Generation completed and validated all selected sources before replacing the resource. No merge or self-approval is automated.

Approve workflows to run on this bot-created PR if GitHub requests it, then require the normal Tests checks before merging. The refresh job is not a substitute for app CI.
'''


def select_review(pull_requests, run_id, attempt):
    candidates = [pr for pr in pull_requests
                  if pr['state'] == 'OPEN' and not pr['isCrossRepository']
                  and pr['author'].get('is_bot') is True
                  and pr['author']['login'] == 'app/github-actions'
                  and (pr['headRefName'] == PREFIX or pr['headRefName'].startswith(PREFIX + '-'))]
    if len(candidates) > 1:
        raise ValueError('Multiple open managed history PRs require manual review')
    if candidates:
        return candidates[0]['headRefName'], candidates[0]['url']
    if not run_id.isdecimal() or not attempt.isdecimal():
        raise ValueError('Invalid workflow run identity')
    return f'{PREFIX}-{run_id}-{attempt}', None


def command(arguments):
    return subprocess.run(arguments, check=True, text=True, capture_output=True).stdout.strip()


def propose(candidate_path, base_sha, run_id, attempt, run=command):
    if run(['git', 'rev-parse', 'HEAD']) != base_sha:
        raise ValueError('The default branch changed during generation; rerun the refresh')
    candidate = json.loads(candidate_path.read_text())
    if semantic_content(json.loads(Path(ARCHIVE).read_text())) == semantic_content(candidate):
        return None
    pull_requests = json.loads(run([
        'gh', 'pr', 'list', '--base', 'main', '--state', 'open', '--author', 'github-actions[bot]',
        '--limit', '1000', '--json', 'headRefName,isCrossRepository,url,state,author',
    ]))
    branch, review_url = select_review(pull_requests, run_id, attempt)
    run(['gh', 'auth', 'setup-git'])
    if review_url:
        remote = f'origin/{branch}'
        run(['git', 'fetch', 'origin', f'{branch}:refs/remotes/origin/{branch}'])
        changed_files = run(['git', 'diff', '--name-only', f'origin/main...{remote}']).splitlines()
        if any(path != ARCHIVE for path in changed_files):
            raise ValueError('The managed history PR contains unexpected changes; review it manually')
        previous = json.loads(run(['git', 'show', f'{remote}:{ARCHIVE}']))
        if semantic_content(previous) == semantic_content(candidate):
            return review_url
        run(['git', 'switch', '--create', branch, '--track', remote])
    else:
        run(['git', 'switch', '--create', branch, 'origin/main'])
    Path(ARCHIVE).write_bytes(candidate_path.read_bytes())
    run(['git', 'add', '--', ARCHIVE])
    run(['git', 'config', 'user.name', 'github-actions[bot]'])
    run(['git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com'])
    run(['git', 'commit', '-m', TITLE, '-m', '* refresh selected provider observations and provenance'])
    run(['git', 'push', '--set-upstream', 'origin', branch])
    if review_url:
        return review_url
    with tempfile.NamedTemporaryFile(mode='w', suffix='.md') as body:
        body.write(BODY)
        body.flush()
        return run(['gh', 'pr', 'create', '--base', 'main', '--head', branch,
                    '--title', TITLE, '--body-file', body.name])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate', type=Path, required=True)
    args = parser.parse_args()
    review_url = propose(args.candidate, os.environ['BASE_SHA'], os.environ['GITHUB_RUN_ID'],
                         os.environ['GITHUB_RUN_ATTEMPT'])
    message = f'History review: {review_url}' if review_url else 'The default branch already contains this history.'
    print(message)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(message + '\n')


if __name__ == '__main__':
    main()
