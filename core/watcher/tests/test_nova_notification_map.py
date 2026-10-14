"""epoxy_patch nova.py.patch: Watcher updates a migrated instance from the
destination's live_migration_post_dest.end (new host), not from the source's
live_migration_post.end (old host). Applies the patch to the pristine .orig.

    python3.11 -m unittest discover -s core/watcher/tests -v
"""
import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
NOTIF = os.path.join(HERE, '..', 'epoxy_patch', 'watcher', 'decision_engine',
                     'model', 'notification')


def patched_source():
    with tempfile.TemporaryDirectory() as d:
        tgt = os.path.join(d, 'nova.py')
        with open(os.path.join(NOTIF, 'nova.py.orig')) as f, open(tgt, 'w') as o:
            o.write(f.read())
        with open(os.path.join(NOTIF, 'nova.py.patch')) as p:
            subprocess.run(['patch', '--forward', '--no-backup-if-mismatch',
                            '-r', '-', tgt], stdin=p, check=True,
                           stdout=subprocess.DEVNULL)
        with open(tgt) as f:
            return f.read()


class TestNovaNotificationMap(unittest.TestCase):
    def test_post_dest_end_updates_the_instance(self):
        src = patched_source()
        self.assertIn("'instance.live_migration_post_dest.end': instance_updated", src)

    def test_post_end_no_longer_maps_the_old_host(self):
        src = patched_source()
        self.assertNotIn("'instance.live_migration_post.end': instance_updated", src)

    def test_pristine_maps_post_end(self):
        with open(os.path.join(NOTIF, 'nova.py.orig')) as f:
            self.assertIn("'instance.live_migration_post.end': instance_updated", f.read())


if __name__ == '__main__':
    unittest.main()
