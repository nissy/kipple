#!/usr/bin/env python3
"""Verify restart cleanup using isolated processes, without stopping the real app."""

import shutil
import signal
import subprocess
import tempfile
import threading
import unittest
import uuid
from pathlib import Path


class StopAppTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="kipple-stop-test-")
        cls.app_name = "KST" + uuid.uuid4().hex[:6]
        cls.executable = Path(cls.directory.name) / cls.app_name
        cls.helper = Path(cls.directory.name) / (cls.app_name + "MCP")
        cls.script = Path(__file__).with_name("stop_app.sh")
        source = r'''
            #include <signal.h>
            #include <stdio.h>
            #include <unistd.h>
            int main(int argc, char **argv) {
                if (argc > 1) signal(SIGTERM, SIG_IGN);
                puts("ready");
                fflush(stdout);
                for (;;) pause();
            }
        '''
        subprocess.run(["xcrun", "clang", "-x", "c", "-", "-o", str(cls.executable)],
                       input=source, text=True, capture_output=True, check=True)
        shutil.copy2(cls.executable, cls.helper)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def setUp(self):
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
            process.stdout.close()

    def start(self, ignore_term=False, helper=False):
        command = [str(self.helper if helper else self.executable)]
        if ignore_term:
            command.append("ignore-term")
        process = subprocess.Popen(command, stdout=subprocess.PIPE, text=True)
        self.processes.append(process)
        self.assertEqual(process.stdout.readline().strip(), "ready")
        # Reap exited children while the stop script checks process disappearance.
        threading.Thread(target=process.wait, daemon=True).start()
        return process

    def stop(self):
        result = subprocess.run(["bash", str(self.script), self.app_name],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_no_existing_process_is_successful(self):
        self.assertEqual(self.stop(), "")

    def test_stops_all_instances_but_not_similarly_named_helper(self):
        first, second = self.start(), self.start()
        helper = self.start(helper=True)
        self.stop()
        self.assertEqual(first.wait(timeout=1), -signal.SIGTERM)
        self.assertEqual(second.wait(timeout=1), -signal.SIGTERM)
        self.assertIsNone(helper.poll())

    def test_force_stops_an_instance_that_ignores_term(self):
        process = self.start(ignore_term=True)
        self.assertIn("forcing termination", self.stop())
        self.assertEqual(process.wait(timeout=1), -signal.SIGKILL)


if __name__ == "__main__":
    unittest.main(verbosity=2)
