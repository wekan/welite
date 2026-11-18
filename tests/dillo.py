"""Optional Dillo HTML4 board check on an isolated Xvfb display."""
import os
from pathlib import Path
import subprocess
import tempfile
import time


def run(base):
    tools = Path(os.environ['WELITE_DILLO_TOOLS']).resolve()
    with tempfile.TemporaryDirectory(prefix='wldillo-', dir=os.environ['TMPDIR']) as directory:
        profile = Path(directory) / '.dillo'
        profile.mkdir()
        (profile / 'cookiesrc').write_text('DEFAULT DENY\n')
        env = dict(os.environ, HOME=directory)
        library = tools / 'usr/lib/aarch64-linux-gnu'
        env['LD_LIBRARY_PATH'] = str(library) + (os.pathsep + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        read_fd, write_fd = os.pipe()
        with (Path(directory) / 'xvfb.log').open('w+') as log:
            display = subprocess.Popen([str(tools / 'usr/bin/Xvfb'), '-displayfd', str(write_fd),
                                        '-screen', '0', '640x480x24', '-nolisten', 'tcp'],
                                       env=env, stdout=log, stderr=log, pass_fds=(write_fd,))
            os.close(write_fd)
            browser = None
            try:
                with os.fdopen(read_fd) as display_number:
                    number = display_number.readline().strip()
                log.seek(0)
                assert number.isdecimal(), log.read()
                env['DISPLAY'] = ':' + number
                browser = subprocess.Popen([str(tools / 'usr/bin/dillo'), '-f', '-g', '640x480+0+0',
                                            base.replace('://localhost:', '://127.0.0.1:') + '/board?id=boardtxt&lang=en'], env=env)
                def highlight():
                    pixels = subprocess.check_output([
                        'ffmpeg', '-v', 'error', '-f', 'x11grab', '-video_size', '640x480',
                        '-i', env['DISPLAY'], '-frames:v', '1', '-threads', '1',
                        '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], env=env, timeout=10)
                    return [(offset // 3 % 640, offset // 3 // 640)
                            for offset in range(0, len(pixels), 3)
                            if pixels[offset:offset + 3] == b'\xff\xff\x66']
                for _ in range(8):
                    points = highlight()
                    if points:
                        break
                    assert browser.poll() is None
                    time.sleep(.5)
                assert len(points) > 20, 'Dillo did not render the HTML4 minimap highlight'
                left = min(x for x, _ in points)
                top = min(y for _, y in points)
                bottom = max(y for _, y in points)
                assert top < bottom and left > 300
                # The neighboring marker is one cell to the right of the first
                # viewport; click the center of that marker, not its border.
                right = max(x for x, _ in points)
                step = right - left + 3
                subprocess.run([str(tools / 'usr/bin/xdotool'), 'mousemove',
                                str((left + right) // 2 + step), str((top + bottom) // 2),
                                'click', '1'], env=env, check=True)
                for _ in range(8):
                    moved = highlight()
                    if moved and min(x for x, _ in moved) > right:
                        break
                    time.sleep(.5)
                else:
                    raise AssertionError('Dillo minimap click did not move the viewport highlight')
            finally:
                if browser is not None and browser.poll() is None:
                    browser.terminate()
                    browser.wait(timeout=10)
                display.terminate()
                display.wait(timeout=10)
    print('PASS: Dillo rendered the HTML4 minimap and followed a viewport link with cookies denied')
