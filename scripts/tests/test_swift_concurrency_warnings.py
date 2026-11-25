from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCANNER = Path(__file__).resolve().parents[1] / "check-swift-concurrency-warnings.py"


class MacroWarnings(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(temporary.cleanup)
        cls.root = Path(temporary.name)
        cls.package = cls.root / "Fixture"
        cls.package.mkdir()
        (cls.package / "Package.swift").write_text("""// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "Fixture", targets: [
    .target(name: "Strict-Kit", swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]),
    .target(name: "Strict-KitTests")
])
""")
        cls.logs = {}
        for target in ("Strict-Kit", "Strict-KitTests"):
            source = cls.package / "Sources" / target / "Widget.swift"
            source.parent.mkdir(parents=True)
            source.write_text("""import Observation
@available(macOS 14, *)
@Observable final class Widget: Sendable {
    var count = 0
}
""")
            module = target.replace("-", "_")
            for style in ("llvm", "swift"):
                result = subprocess.run(
                    ["swiftc", "-typecheck", "-swift-version", "5", "-diagnostic-style", style,
                     "-module-name", module, str(source)],
                    capture_output=True, text=True, check=True,
                )
                cls.logs[target, style] = result.stderr

    def scan(self, log, *scope):
        path = self.root / "build.log"
        path.write_text(log)
        return subprocess.run([sys.executable, SCANNER, path, *scope], capture_output=True, text=True)

    def test_compiler_diagnostics_respect_scope(self):
        for style, marker in (("llvm", "swift-generated-sources/"), ("swift", "macro expansion @")):
            strict = self.logs["Strict-Kit", style]
            ignored = self.logs["Strict-KitTests", style]
            self.assertIn(marker, strict)
            self.assertIn(marker, ignored)
            for scope in (("--package-roots", self.root), ("--package", self.package),
                          (self.package / "Sources" / "Strict-Kit",)):
                with self.subTest(style=style, scope=scope):
                    result = self.scan(strict, *scope)
                    self.assertEqual(result.returncode, 1)
                    self.assertIn("stored property '_count'", result.stderr)
                    result = self.scan(ignored, *scope)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_xcode_attributes_the_module_to_its_resolved_package(self):
        header = (
            f"Resolved source packages:\n  Fixture: {self.package} @ local\n\n"
            r"SwiftEmitModule normal arm64 Emitting\ module\ for\ Strict_Kit "
            "(in target 'Strict-Kit' from project 'Fixture')\n"
        )
        log = header + self.logs["Strict-Kit", "llvm"]
        result = self.scan(log, "--package-roots", self.root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("stored property '_count'", result.stderr)

        # Another package under the checked roots can declare the same module.
        # The recorded build compiled Fixture outside those roots.
        other = self.root / "Other"
        other.mkdir()
        (other / "Package.swift").write_bytes((self.package / "Package.swift").read_bytes())
        (other / "Sources").symlink_to(self.package / "Sources", target_is_directory=True)
        result = self.scan(log, "--package-roots", other)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
