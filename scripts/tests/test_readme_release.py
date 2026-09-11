import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[1] / 'readme-release.py'
spec = importlib.util.spec_from_file_location('readme_release', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReadmeReleaseTests(unittest.TestCase):
    def metadata(self):
        return {'status': 'available', 'version': '0.9.0-beta.1', 'build': 90001, 'beta': True,
                'download': module.REPOSITORY + '/releases/download/v0.9.0-beta.1/DuoLid-0.9.0-beta.1.dmg',
                'notes': module.REPOSITORY + '/releases/tag/v0.9.0-beta.1'}

    def test_unpublished_release_does_not_offer_an_app_download(self):
        result = module.release_block({'status': 'preparing', 'version': '0.9.0-beta.1', 'download': None})
        self.assertNotIn('/releases/download/', result)
        self.assertNotIn('src="docs/assets/download.svg"', result)

    def test_beta_download_targets_the_exact_asset(self):
        result = module.release_block(self.metadata())
        self.assertIn('href="' + self.metadata()['download'] + '"', result)
        self.assertIn('Beta · 0.9.0-beta.1', result)

    def test_rejects_latest_links_and_mismatched_versions(self):
        for link in (module.REPOSITORY + '/releases/latest', self.metadata()['download'].replace('beta.1', 'beta.2')):
            bad = self.metadata(); bad['download'] = link
            with self.assertRaises(ValueError): module.release_block(bad)

    def test_stable_releases_have_no_beta_label(self):
        metadata = self.metadata()
        for field in ('version', 'download', 'notes'):
            metadata[field] = metadata[field].replace('0.9.0-beta.1', '1.0.0')
        metadata['beta'] = False
        self.assertNotIn('Beta ·', module.release_block(metadata))

    def test_marker_errors_fail_without_rewriting_other_content(self):
        for body in ('No markers', module.END + module.BEGIN, module.BEGIN * 2 + module.END):
            with self.assertRaises(ValueError): module.replace_block(body, self.metadata())
        readme = 'Before\n' + module.BEGIN + '\nOld download\n' + module.END + '\nAfter'
        result = module.replace_block(readme, self.metadata())
        self.assertTrue(result.startswith('Before\n'))
        self.assertTrue(result.endswith('\nAfter'))

    def test_rejects_injected_versions_and_false_availability(self):
        bad = self.metadata(); bad['version'] = '1.0.0"><script>'
        with self.assertRaises(ValueError): module.release_block(bad)
        bad = self.metadata(); bad['status'] = 'preparing'
        with self.assertRaises(ValueError): module.release_block(bad)
