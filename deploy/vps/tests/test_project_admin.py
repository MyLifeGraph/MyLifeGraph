from __future__ import annotations

import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

BIN = Path(__file__).resolve().parents[1] / 'bin'
spec = importlib.util.spec_from_file_location('project_admin', BIN / 'project_admin.py')
admin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(admin)


class ProjectAdminTests(unittest.TestCase):
    def test_only_fixed_commands_units_and_tags_are_accepted(self):
        for argv in (['restart', 'ssh'], ['stop', 'docker'], ['enable', 'ssh'], ['disable', 'docker'], ['logs', 'api', '--follow'],
                     ['shell'], ['setup', '--command', 'id'], ['prepare', 'tag', 'extra']):
            with self.subTest(argv=argv), self.assertRaises(SystemExit):
                with patch('sys.stderr', new=io.StringIO()):
                    admin.parser().parse_args(argv)
        for value in ('../escape', '/root', 'v1.0.0-pilot.1-rc.1;id', '--help', 'main'):
            with self.subTest(value=value), self.assertRaises(admin.ProjectError):
                admin.tag(value)

    def test_upload_checks_bytes_limits_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'incoming').mkdir()
            payload = b'public source artifact'
            digest = hashlib.sha256(payload).hexdigest()
            with (patch.object(admin, 'ROOT', root), patch.object(admin, 'protected'),
                  patch.object(admin, 'LIMITS', {'archive': 32, 'manifest': 32}),
                  patch.object(admin.shutil, 'disk_usage') as disk,
                  patch('sys.stdout', new=io.StringIO())):
                disk.return_value.free = admin.RESERVE + 1024
                admin.upload('v1.0.0-pilot.1-rc.1', 'archive', digest, io.BytesIO(payload))
                target = admin.artifact('v1.0.0-pilot.1-rc.1', 'archive')
                self.assertEqual(target.read_bytes(), payload)
                self.assertEqual(target.stat().st_mode & 0o777, 0o400)
                admin.upload('v1.0.0-pilot.1-rc.1', 'archive', digest, io.BytesIO(payload))
                for data, expected in ((b'changed', hashlib.sha256(b'changed').hexdigest()),
                                       (b'x'*33, hashlib.sha256(b'x'*33).hexdigest()),
                                       (payload, '0'*64)):
                    with self.assertRaises(admin.ProjectError):
                        admin.upload('v1.0.0-pilot.1-rc.1', 'archive', expected, io.BytesIO(data))
                    self.assertEqual(target.read_bytes(), payload)
                    self.assertEqual(list((root/'incoming').iterdir()), [target])

    def test_upload_preserves_disk_reserve_before_writing(self):
        with patch.object(admin, 'protected'), patch.object(admin.shutil, 'disk_usage') as disk:
            disk.return_value.free = 0
            with patch.object(admin.tempfile, 'mkstemp') as create, self.assertRaises(admin.ProjectError):
                admin.upload('v1.0.0-pilot.1-rc.1', 'archive', '0'*64, io.BytesIO(b'x'))
            create.assert_not_called()

    def test_root_command_environment_does_not_inherit_caller_secrets(self):
        with patch.dict(admin.os.environ, {'SUPABASE_SECRET_KEY': 'synthetic',
                                          'PYTHONPATH': '/untrusted', 'PAGER': '/untrusted'}):
            output = admin.run(['/usr/bin/env'], capture=True)
        self.assertNotIn('SUPABASE', output)
        self.assertNotIn('PYTHONPATH', output)
        self.assertNotIn('PAGER', output)
        self.assertIn('PATH=' + admin.ENV['PATH'], output)

    def test_setup_uses_exec_to_preserve_secret_input_terminal(self):
        class File:
            def read_bytes(self): return b'script'
        class Setup:
            def __truediv__(self, name): return File()
        with (patch.object(admin, 'protected'), patch.object(admin, 'SETUP', Setup()),
              patch.object(admin.hashlib, 'sha256') as digest,
              patch.object(admin.sys.stdin, 'isatty', return_value=True),
              patch.object(admin, 'run') as run,
              patch.object(admin.os, 'chdir'), patch.object(admin.os, 'execve') as execute):
            digest.return_value.hexdigest.return_value = 'a22190362a64fadf67b96ea6bb24e5a364fbc05e36c6b0c02b09a527c9d13a5a'
            admin.setup()
        run.assert_called_once()
        self.assertEqual(execute.call_args.args[0], '/bin/bash')
        self.assertEqual(execute.call_args.args[2], admin.ENV)

    def test_core_check_covers_loopback_and_public_exact_release(self):
        import json
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory)
            manifest = {'release_sha': 'a'*40, 'release_tag': 'v1.0.0-pilot.1-rc.1',
                        'migration_head': '20260101000000_test.sql',
                        'migration_inventory': {'count': 1, 'identity_sha256': 'b'*64}}
            (candidate/'.mylifegraph-source-manifest.json').write_text(json.dumps(manifest))
            with patch.object(admin, 'protected'), patch.object(admin, 'helper') as helper:
                admin.core_ready(candidate, 'api.example.org')
            self.assertEqual(len(helper.call_args_list), 2)
            self.assertIn('http://127.0.0.1:8000', helper.call_args_list[0].args)
            self.assertIn('https://api.example.org', helper.call_args_list[1].args)
            for call in helper.call_args_list:
                self.assertEqual(call.args[0], 'health_check.py')
                self.assertIn('a'*40, call.args)
                self.assertIn('b'*64, call.args)
            with patch.object(admin, 'protected'), patch.object(admin, 'helper', side_effect=admin.ProjectError('not ready')):
                with self.assertRaises(admin.ProjectError):
                    admin.core_ready(candidate, 'api.example.org')

    def test_policy_publication_failures_leave_no_active_partial_file(self):
        spec = importlib.util.spec_from_file_location('project_installer', BIN/'install_project_admin.py')
        installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installer)
        for name in ('sudoers', 'ssh.conf'):
            for failing_sync in (1, 2):
                with self.subTest(name=name, sync=failing_sync), tempfile.TemporaryDirectory() as directory:
                    path = Path(directory)/name
                    actual_sync = installer.os.fsync
                    calls = 0
                    def sync(fd):
                        nonlocal calls
                        calls += 1
                        if calls == failing_sync: raise OSError('injected I/O failure')
                        actual_sync(fd)
                    with patch.object(installer, 'protected'), patch.object(installer.os, 'fsync', side_effect=sync):
                        with self.assertRaises(OSError): installer.write_new(path, b'policy', 0o440)
                    self.assertEqual(list(path.parent.iterdir()), [])
            with tempfile.TemporaryDirectory() as directory:
                path = Path(directory)/name
                path.write_bytes(b'existing')
                with patch.object(installer, 'protected'):
                    with self.assertRaises(FileExistsError): installer.write_new(path, b'new', 0o440)
                installer.remove_owned(path, None)
                self.assertEqual(path.read_bytes(), b'existing')



if __name__ == '__main__':
    unittest.main()
