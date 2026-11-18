"""Optional Dillo and NetSurf HTML4 board checks on isolated Xvfb displays."""
from contextlib import contextmanager
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import select
import subprocess
import tempfile
from threading import Thread
import time
from urllib.parse import urlsplit


def run(base):
    for width, height in [(640, 480), (320, 480)]:
        check_viewport(base, width, height, "Dillo")
    if os.environ.get("WELITE_NETSURF") == "1":
        check_viewport(base, 640, 480, "NetSurf")
        check_viewport(base, 320, 480, "NetSurf")


@contextmanager
def observe_board_requests(base):
    upstream = urlsplit(base)
    exchanges = []

    class Observer(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_GET(self):
            connection = http.client.HTTPConnection(upstream.hostname, upstream.port, timeout=10)
            try:
                connection.request('GET', self.path, headers={
                    name: value for name, value in self.headers.items() if name.lower() != 'host'
                })
                response = connection.getresponse()
                body = response.read()
                if urlsplit(self.path).path in ('/board', '/sign-in'):
                    exchanges.append((self.path, self.headers.get('Cookie'),
                                      response.getheader('Set-Cookie'), response.status))
                self.send_response(response.status)
                for name, value in response.getheaders():
                    if name.lower() not in ('connection', 'content-length', 'transfer-encoding', 'date', 'server'):
                        self.send_header(name, value)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            finally:
                connection.close()

    with ThreadingHTTPServer(('127.0.0.1', 0), Observer) as server:
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f'http://127.0.0.1:{server.server_port}', exchanges
        finally:
            server.shutdown()
            thread.join()



def check_viewport(base, width, height, browser_name):
    size = f'{width}x{height}'
    tools = Path(os.environ['WELITE_DILLO_TOOLS']).resolve()
    with (observe_board_requests(base) as (observed, exchanges),
          tempfile.TemporaryDirectory(prefix='wldillo-', dir=os.environ['TMPDIR']) as directory):
        profile = Path(directory) / '.dillo'
        profile.mkdir()
        (profile / 'cookiesrc').write_text('DEFAULT DENY\n')
        env = dict(os.environ, HOME=directory)
        library = tools / 'usr/lib/aarch64-linux-gnu'
        env['LD_LIBRARY_PATH'] = str(library) + (os.pathsep + env['LD_LIBRARY_PATH'] if env.get('LD_LIBRARY_PATH') else '')
        read_fd, write_fd = os.pipe()
        with (Path(directory) / 'xvfb.log').open('w+') as log:
            display = subprocess.Popen([str(tools / 'usr/bin/Xvfb'), '-displayfd', str(write_fd),
                                        '-screen', '0', size + 'x24', '-nolisten', 'tcp'],
                                       env=env, stdout=log, stderr=log, pass_fds=(write_fd,))
            os.close(write_fd)
            browser = None
            try:
                with os.fdopen(read_fd) as display_number:
                    assert select.select([display_number], [], [], 10)[0], 'Xvfb startup timed out'
                    number = display_number.readline().strip()
                log.seek(0)
                assert number.isdecimal(), log.read()
                env['DISPLAY'] = ':' + number
                url = observed + '/board?id=boardtxt&lang=en'
                if browser_name == 'NetSurf':
                    env.update(GDK_BACKEND='x11', GDK_SCALE='1', GDK_DPI_SCALE='1', GTK_IM_MODULE='xim',
                               NETSURFRES=str(tools / 'usr/share/netsurf'),
                               XDG_CONFIG_HOME=str(Path(directory) / 'config'),
                               XDG_CACHE_HOME=str(Path(directory) / 'cache'))
                    args = ['netsurf-gtk', '--enable_javascript=0', f'--window_width={width}',
                            f'--window_height={height}', url]
                else:
                    args = ['dillo', '-f', '-g', size + '+0+0', url]
                browser = subprocess.Popen([str(tools / 'usr/bin' / args[0]), *args[1:]], env=env)
                def highlight():
                    pixels = subprocess.check_output([
                        'ffmpeg', '-v', 'error', '-f', 'x11grab', '-video_size', size,
                        '-i', env['DISPLAY'], '-frames:v', '1', '-threads', '1',
                        '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'], env=env, timeout=10)
                    return [(offset // 3 % width, offset // 3 // width)
                            for offset in range(0, len(pixels), 3)
                            if pixels[offset:offset + 3] == b'\xff\xff\x66']
                for _ in range(8):
                    points = highlight()
                    if points:
                        break
                    assert browser.poll() is None
                    time.sleep(.5)
                assert len(points) > 20, f'{browser_name} did not render the HTML4 minimap highlight'
                left = min(x for x, _ in points)
                top = min(y for _, y in points)
                bottom = max(y for _, y in points)
                assert top < bottom and left > width // 2
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
                    raise AssertionError(f'{browser_name} minimap click did not move the viewport highlight')
                assert len(exchanges) >= 2 and len({path for path, _, _, _ in exchanges}) >= 2, exchanges
                assert all(cookie is None and issued is None and status == 200
                           for _, cookie, issued, status in exchanges), exchanges
                if width == 640:
                    assert_language_form(tools, env, observed, exchanges, browser_name)

            finally:
                if browser is not None and browser.poll() is None:
                    browser.terminate()
                    browser.wait(timeout=10)
                display.terminate()
                display.wait(timeout=10)
    print(f'PASS: {browser_name} at {size} rendered the HTML4 minimap and followed a viewport link without cookies')


def assert_language_form(tools, env, observed, exchanges, browser_name):
    xdotool = str(tools / 'usr/bin/xdotool')

    def send(*args):
        subprocess.run([xdotool, *args], env=env, check=True)

    def wait_for(path):
        for _ in range(40):
            if any(route == path for route, _, _, _ in exchanges):
                return
            time.sleep(.1)
        raise AssertionError(f'No browser request for {path}: {exchanges}')

    send('key', 'ctrl+l')
    send('type', observed + '/sign-in')
    send('key', 'Return')
    wait_for('/sign-in')
    time.sleep(.4)
    if browser_name == 'NetSurf':
        # At the fixed 640-pixel viewport and GTK scale, Apply is beside the picker.
        send('mousemove', '435', '65', 'click', '1')
    else:
        send('mousemove', '500', '220', 'click', '1')
        send('key', 'Tab', 'Tab', 'Return')
    wait_for('/sign-in?lang=en')
    assert all(cookie is None and issued is None and status == 200
               for route, cookie, issued, status in exchanges
               if urlsplit(route).path == '/sign-in')
    print(f'PASS: {browser_name} submitted the HTML sign-in language form without cookies')
