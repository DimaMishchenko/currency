import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import propose_refresh as publisher


class ReviewLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / 'history.json'
        self.candidate = Path(self.temp.name) / 'candidate.json'
        self.old = {'version': 1, 'provenance': {'acquired': '2026-10-01'}, 'fiat': {'EUR': [[1, 2]]}}
        self.new = copy.deepcopy(self.old)
        self.new['fiat']['EUR'].append([2, 3])
        self.output.write_text(json.dumps(self.old))
        self.candidate.write_text(json.dumps(self.new))
        self.archive_patch = patch.object(publisher, 'ARCHIVE', str(self.output))
        self.archive_patch.start()
        self.addCleanup(self.archive_patch.stop)
        self.calls = []
        self.prs = []
        self.previous = self.old
        self.changed_files = str(self.output)

    def review(self, branch=None, state='OPEN', author='app/github-actions', cross_repo=False):
        return {'headRefName': branch or publisher.PREFIX + '-123-1', 'state': state,
                'url': 'https://github.com/example/currency/pull/1',
                'author': {'login': author, 'is_bot': author == 'app/github-actions'}, 'isCrossRepository': cross_repo}

    def execute(self, arguments):
        self.calls.append(arguments)
        if arguments[:3] == ['git', 'rev-parse', 'HEAD']:
            return 'base'
        if arguments[:3] == ['gh', 'pr', 'list']:
            return json.dumps(self.prs)
        if arguments[:3] == ['git', 'diff', '--name-only']:
            return self.changed_files
        if arguments[:2] == ['git', 'show']:
            return json.dumps(self.previous)
        if arguments[:3] == ['gh', 'pr', 'create']:
            body = Path(arguments[arguments.index('--body-file') + 1]).read_text()
            self.assertIn('## 🔗 Related issue', body)
            self.assertIn('## 📝 Summary', body)
            self.assertIn('## 🧪 Validation', body)
            return 'https://github.com/example/currency/pull/2'
        return ''

    def propose(self):
        return publisher.propose(self.candidate, 'base', '456', '2', run=self.execute)

    def mutations(self):
        return [call for call in self.calls if call[:2] in (['git', 'commit'], ['git', 'push'])]

    def test_actual_gh_cli_actions_author_reuses_open_review(self):
        review = self.review()
        review['author'] = {'is_bot': True, 'login': 'app/github-actions'}
        branch, url = publisher.select_review([review], '456', '2')
        self.assertEqual(branch, review['headRefName'])
        self.assertEqual(url, review['url'])

    def test_retained_squash_merged_branch_is_ignored_even_if_its_content_matches(self):
        self.prs = [self.review(state='MERGED')]
        self.previous = self.new
        result = self.propose()
        branch = publisher.PREFIX + '-456-2'
        self.assertEqual(result, 'https://github.com/example/currency/pull/2')
        self.assertIn(['git', 'switch', '--create', branch, 'origin/main'], self.calls)
        self.assertIn(['git', 'push', '--set-upstream', 'origin', branch], self.calls)
        self.assertFalse(any(call[:2] in (['git', 'show'], ['git', 'fetch']) for call in self.calls))
        self.assertEqual(json.loads(self.output.read_text()), self.new)

    def test_closed_unmerged_branch_does_not_reuse_its_stale_base(self):
        self.prs = [self.review(state='CLOSED')]
        self.propose()
        self.assertIn(['git', 'switch', '--create', publisher.PREFIX + '-456-2', 'origin/main'], self.calls)

    def test_open_managed_review_is_updated_with_regular_push(self):
        review = self.review()
        self.prs = [review]
        result = self.propose()
        branch = review['headRefName']
        self.assertEqual(result, review['url'])
        self.assertIn(['git', 'switch', '--create', branch, '--track', 'origin/' + branch], self.calls)
        self.assertIn(['git', 'push', '--set-upstream', 'origin', branch], self.calls)
        self.assertFalse(any('--force' in argument for call in self.calls for argument in call))
        self.assertFalse(any(call[:3] == ['gh', 'pr', 'create'] for call in self.calls))

    def test_open_review_with_same_semantics_has_no_commit_or_pr_update(self):
        review = self.review()
        self.prs = [review]
        self.previous = copy.deepcopy(self.new)
        self.previous['provenance']['acquired'] = '2026-09-01'
        result = self.propose()
        self.assertEqual(result, review['url'])
        self.assertEqual(self.mutations(), [])
        self.assertFalse(any(call[:2] == ['git', 'switch'] for call in self.calls))
        self.assertFalse(any(call[:3] == ['gh', 'pr', 'create'] for call in self.calls))

    def test_main_already_contains_semantics_without_any_pr_lookup(self):
        self.output.write_text(json.dumps(self.new))
        self.assertIsNone(self.propose())
        self.assertEqual(self.calls, [['git', 'rev-parse', 'HEAD']])

    def test_unexpected_managed_branch_changes_fail_before_writing_or_pushing(self):
        self.prs = [self.review()]
        self.changed_files += '\nApp/private-change.swift'
        original = self.output.read_bytes()
        with self.assertRaisesRegex(ValueError, 'unexpected changes'):
            self.propose()
        self.assertEqual(self.output.read_bytes(), original)
        self.assertEqual(self.mutations(), [])

    def test_multiple_open_managed_reviews_require_manual_resolution(self):
        self.prs = [self.review(), self.review(branch=publisher.PREFIX + '-222-1')]
        with self.assertRaisesRegex(ValueError, 'Multiple open'):
            self.propose()
        self.assertEqual(self.mutations(), [])

    def test_human_and_fork_reviews_are_not_reused(self):
        self.prs = [self.review(author='a-person'), self.review(cross_repo=True)]
        self.propose()
        self.assertIn(['git', 'switch', '--create', publisher.PREFIX + '-456-2', 'origin/main'], self.calls)

    def test_stale_generation_base_fails_before_mutation(self):
        with self.assertRaisesRegex(ValueError, 'default branch changed'):
            publisher.propose(self.candidate, 'older-base', '456', '2', run=self.execute)
        self.assertEqual(self.calls, [['git', 'rev-parse', 'HEAD']])


if __name__ == '__main__':
    unittest.main()
