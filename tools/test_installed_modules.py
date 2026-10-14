import json
from pathlib import Path
import tempfile
import unittest
from verify_installed_modules import audit

class InstalledModulesTests(unittest.TestCase):
    def test_installed_dependency_and_inventory(self):
        with tempfile.TemporaryDirectory()as temporary:
            root=Path(temporary);(root/'src').mkdir()
            (root/'main.lua').write_text("return mod.require('src/standalone.lua')")
            (root/'src/standalone.lua').write_text("return host.require('src/cursor_capture.lua')")
            (root/'src/cursor_capture.lua').write_text('return {}')
            manifest={'lll':{'entry':'main.lua','modules':['src/standalone.lua']}}
            (root/'manifest.json').write_text(json.dumps(manifest))
            result=audit(root)
            self.assertFalse(result['passed'])
            self.assertTrue(any('undeclared private import src/cursor_capture.lua'in error for error in result['errors']))
            manifest['lll']['modules'].append('src/cursor_capture.lua')
            (root/'manifest.json').write_text(json.dumps(manifest))
            self.assertTrue(audit(root)['passed'])
            (root/'src/cursor_capture.lua').unlink()
            self.assertFalse(audit(root)['passed'])

if __name__=='__main__':unittest.main()
