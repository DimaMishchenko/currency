import copy
import datetime
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import generate_archive as generator


class ArchiveGenerationTests(unittest.TestCase):
    def setUp(self):
        self.today = datetime.date(2024, 5, 15)
        self.allowed = {'USD', 'EUR', 'GBP', *(code.upper() for code in generator.CODES)}
        self.crypto = {code: [['2024-02-01', '2'], ['2024-02-29', '3'], ['2024-03-01', '9']]
                       for code in generator.CODES}
        self.fiat = [
            {'date': '2024-02-01', 'base': 'USD', 'quote': 'EUR', 'rate': 0.8},
            {'date': '2024-02-01', 'base': 'USD', 'quote': 'GBP', 'rate': 0.5},
        ]
        self.tables = {day: {'date': day, 'usd': {'usd': 1, 'eur': 0.8, 'btc': 2, 'unused': 999}}
                       for day in generator.publication_days(self.today)}
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / 'history.json'

    def build(self, today=None):
        return generator.build_archive(self.crypto, self.fiat, self.tables, self.allowed, today or self.today)

    def test_completed_month_boundary_including_year_rollover(self):
        self.assertEqual(generator.publication_days(datetime.date(2024, 3, 31)), [])
        self.assertEqual(generator.publication_days(datetime.date(2024, 4, 1)), ['2024-03-02'])
        self.assertEqual(generator.publication_days(datetime.date(2026, 10, 1))[-1], '2026-09-01')
        self.assertEqual(generator.publication_days(datetime.date(2026, 10, 31))[-1], '2026-09-01')
        self.assertEqual(generator.publication_days(datetime.date(2027, 1, 1))[-1], '2026-12-01')

    def test_sampling_preserves_selected_observations_and_provider_notices(self):
        archive = self.build()
        february = (datetime.date(2024, 2, 29) - generator.EPOCH).days
        self.assertEqual(archive['crypto']['BTC'], [[february, 3.0]])
        self.assertEqual(archive['cryptoFX']['BTC'][0][1], 2.0)
        self.assertEqual(len(archive['fawaz']['BTC']), 2)
        self.assertNotIn('UNUSED', archive['fawaz'])
        self.assertEqual(len(archive['providers']), 66)
        self.assertNotIn('BOE', archive['providers'])
        self.assertEqual(archive['provenance']['licenses'],
                         ['CC-BY-NC-4.0.txt', 'CC-BY-4.0.txt', 'Fawaz-CC0-1.0.txt'])
        self.assertEqual(archive['provenance']['notice'], 'DataSources.md')

    def test_acquisition_and_input_hash_churn_do_not_rewrite_output(self):
        self.assertTrue(generator.write_archive(self.output, self.build()))
        original = self.output.read_bytes()
        timestamp = self.output.stat().st_mtime_ns
        later = self.build(datetime.date(2024, 5, 30))
        for key in generator.VOLATILE_METADATA:
            later['provenance'][key] = 'changed'
        self.assertFalse(generator.write_archive(self.output, later))
        self.assertEqual(self.output.read_bytes(), original)
        self.assertEqual(self.output.stat().st_mtime_ns, timestamp)

    def test_unselected_source_changes_are_noop(self):
        generator.write_archive(self.output, self.build())
        self.crypto['btc'].append(['2026-01-01', '1000'])
        self.tables['2024-04-01']['usd']['unused'] = 1001
        self.fiat.append({'date': '2024-02-01', 'base': 'USD', 'quote': 'UNUSED', 'rate': 1002})
        self.assertFalse(generator.write_archive(self.output, self.build()))

    def test_older_crypto_and_fiat_corrections_are_written(self):
        generator.write_archive(self.output, self.build())
        self.crypto['btc'][1][1] = '3.5'
        self.assertTrue(generator.write_archive(self.output, self.build()))
        self.assertEqual(json.loads(self.output.read_text())['crypto']['BTC'][0][1], 3.5)
        self.fiat[0]['rate'] = 0.9
        self.assertTrue(generator.write_archive(self.output, self.build()))
        self.assertEqual(json.loads(self.output.read_text())['fiat']['EUR'][0][1], 0.9)

    def test_next_completed_month_adds_only_real_dated_table(self):
        generator.write_archive(self.output, self.build())
        self.tables['2024-05-01'] = {'date': '2024-05-01', 'usd': {'usd': 1, 'eur': 0.9, 'btc': 3}}
        self.assertTrue(generator.write_archive(self.output, self.build(datetime.date(2024, 6, 1))))
        saved = json.loads(self.output.read_text())
        self.assertEqual(len(saved['fawaz']['BTC']), 3)
        self.assertEqual(saved['fawaz']['BTC'][-1][1], 3)

    def test_meaningful_provenance_change_is_written(self):
        archive = self.build()
        generator.write_archive(self.output, archive)
        archive['provenance']['cryptoSource'] = 'https://example.invalid/corrected-source'
        self.assertTrue(generator.write_archive(self.output, archive))

    def test_upstream_failure_leaves_previous_output_untouched(self):
        generator.write_archive(self.output, self.build())
        original = self.output.read_bytes()
        with patch.object(generator, 'load_sources', side_effect=OSError('upstream unavailable')):
            with self.assertRaises(OSError):
                generator.main(['--output', str(self.output), '--today', '2024-05-15'])
        self.assertEqual(self.output.read_bytes(), original)
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_wrong_publication_fails_before_output_replacement(self):
        generator.write_archive(self.output, self.build())
        original = self.output.read_bytes()
        self.tables['2024-04-01']['date'] = '2024-03-31'
        with patch.object(generator, 'load_sources', return_value=(self.crypto, self.fiat, self.tables)):
            with self.assertRaisesRegex(ValueError, 'Wrong publication'):
                generator.main(['--output', str(self.output), '--today', '2024-05-15'])
        self.assertEqual(self.output.read_bytes(), original)

    def test_malformed_rates_cannot_replace_valid_archive(self):
        for value in [float('nan'), float('inf'), 0, -1, True]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                generator.positive(value)

    def test_coverage_loss_requires_manual_review(self):
        archive = self.build()
        generator.write_archive(self.output, archive)
        original = self.output.read_bytes()
        candidate = copy.deepcopy(archive)
        candidate['fiat']['GBP'] = []
        with self.assertRaisesRegex(ValueError, 'coverage decreased'):
            generator.write_archive(self.output, candidate)
        self.assertEqual(self.output.read_bytes(), original)

    def test_new_month_cannot_hide_loss_of_an_old_observation(self):
        archive = self.build()
        generator.write_archive(self.output, archive)
        original = self.output.read_bytes()
        candidate = copy.deepcopy(archive)
        day, value = candidate['crypto']['ETH'][0]
        candidate['crypto']['ETH'] = [[day + 31, value]]
        self.assertEqual(len(candidate['crypto']['ETH']), len(archive['crypto']['ETH']))
        with self.assertRaisesRegex(ValueError, 'coverage decreased: crypto/ETH'):
            generator.write_archive(self.output, candidate)
        self.assertEqual(self.output.read_bytes(), original)

    def test_failed_atomic_replace_preserves_previous_output_and_removes_temporary_file(self):
        archive = self.build()
        generator.write_archive(self.output, archive)
        original = self.output.read_bytes()
        archive['fawaz']['BTC'][-1][1] = 3
        with patch.object(Path, 'replace', side_effect=OSError('replace failed')):
            with self.assertRaises(OSError):
                generator.write_archive(self.output, archive)
        self.assertEqual(self.output.read_bytes(), original)
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])


if __name__ == '__main__':
    unittest.main()
