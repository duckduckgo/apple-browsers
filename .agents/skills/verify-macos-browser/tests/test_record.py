"""Tests for `record stop` on this Mac, with a generated movie in place of screencapture's: the recording is re-encoded
small enough to upload, keeps only the seconds before a cut, and an unreadable one is reported.
Run: python3 -I -m unittest discover -s .agents/skills/verify-macos-browser/tests -p 'test_*.py'
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from fractions import Fraction

sys.dont_write_bytecode = True
SKILL = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
VERIFY = os.path.join(SKILL, "scripts", "verify.sh")

# Writes a movie as screencapture does on a Retina screen: 60 frames a second while the screen changes, none while
# it is still (from 1 s to 2 s), 3 s in all.
GENERATE = r'''import AVFoundation
let a = CommandLine.arguments, w = Int(a[2])!, h = Int(a[3])!
let writer = try! AVAssetWriter(outputURL: URL(fileURLWithPath: a[1]), fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for i in Array(0..<60) + Array(120..<180) {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    var frame: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &frame)
    CVPixelBufferLockBaseAddress(frame!, [])
    memset(CVPixelBufferGetBaseAddress(frame!), Int32(i), CVPixelBufferGetDataSize(frame!))
    CVPixelBufferUnlockBaseAddress(frame!, [])
    adaptor.append(frame!, withPresentationTime: CMTime(value: Int64(i) * 10, timescale: 600))
}
input.markAsFinished()
writer.endSession(atSourceTime: CMTime(value: 1800, timescale: 600))
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
precondition(writer.status == .completed, "\(String(describing: writer.error))")
'''


def media_info(path):
    """(width, height, seconds, shortest frame in seconds) of a movie's video track, as avmediainfo reports them."""
    out = subprocess.run(["avmediainfo", path], capture_output=True, text=True, check=True).stdout
    width, height = re.search(r"Dimensions: (\d+) x (\d+)", out).groups()
    shortest = re.search(r"Minimum sample duration: (\d+/\d+) seconds", out)[1]
    return int(width), int(height), float(re.search(r"Duration: ([\d.]+) seconds", out)[1]), Fraction(shortest)


class RecordStopTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.tools = tempfile.mkdtemp()
        source = os.path.join(cls.tools, "generate.swift")
        with open(source, "w") as f:
            f.write(GENERATE)
        cls.generate = os.path.join(cls.tools, "generate")
        subprocess.run(["swiftc", "-suppress-warnings", source, "-o", cls.generate], check=True)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tools)

    def setUp(self):
        self.home = tempfile.mkdtemp()
        self.run_dir = os.path.join(self.home, "run")
        os.makedirs(self.run_dir)
        with open(os.path.join(self.run_dir, "recording.pid"), "w") as f:
            f.write("\n")   # a recorder that already stopped
        self.mov, self.mp4 = (os.path.join(self.run_dir, f"recording.{ext}") for ext in ("mov", "mp4"))

    def tearDown(self):
        shutil.rmtree(self.home)

    def stop(self, width=2560, height=1440):
        subprocess.run([self.generate, self.mov, str(width), str(height)], check=True)
        return subprocess.run([VERIFY, "record", "rec-test", "stop"], capture_output=True, text=True, timeout=120,
                              env={**os.environ, "VERIFY_MACOS_HOME": self.home, "VERIFY_RUN_DIR": self.run_dir})

    def test_a_retina_screen_is_scaled_to_2048_wide_at_30_frames_a_second(self):
        p = self.stop()
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertRegex(p.stdout, r"recording\.mp4 seconds=3\.0+ bytes=\d+")
        width, height, seconds, shortest = media_info(self.mp4)
        self.assertEqual((width, height), (2048, 1152))
        self.assertEqual(seconds, 3.0)
        self.assertEqual(shortest, Fraction(1, 30), "no two frames closer than 1/30 s, before or after the still second")
        self.assertEqual([f for f in os.listdir(self.run_dir) if f.startswith("recording")], ["recording.mp4"])

    def test_a_window_narrower_than_that_keeps_its_size(self):
        p = self.stop(1000, 700)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(media_info(self.mp4)[:2], (1000, 700))

    def test_a_cut_keeps_only_the_seconds_before_it(self):
        with open(os.path.join(self.run_dir, "recording.cut"), "w") as f:
            f.write("1 another app came in front\n")
        p = self.stop()
        self.assertEqual(p.returncode, 1, p.stdout + p.stderr)
        self.assertIn("CUT: another app came in front", p.stdout)
        self.assertEqual(media_info(self.mp4)[2], 1.0)

    def test_a_movie_avfoundation_cant_read_is_reported_and_no_mp4_is_left(self):
        with open(self.mov, "w") as f:
            f.write("not a movie")
        p = subprocess.run([VERIFY, "record", "rec-test", "stop"], capture_output=True, text=True, timeout=120,
                           env={**os.environ, "VERIFY_MACOS_HOME": self.home, "VERIFY_RUN_DIR": self.run_dir})
        self.assertEqual(p.returncode, 2, p.stdout + p.stderr)
        self.assertIn("UNPLAYABLE", p.stdout)
        self.assertFalse(os.path.exists(self.mp4))


if __name__ == "__main__":
    unittest.main()
