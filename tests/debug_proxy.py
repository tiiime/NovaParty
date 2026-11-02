"""Drop the first submit response after forwarding the request to a real Debug server."""
import contextlib
import json
from pathlib import Path
import select
import socket
import threading
import time


@contextlib.contextmanager
def lost_submit_reply(connection_path, output):
    connection = json.loads(Path(connection_path).read_text())
    listener = socket.socket()
    listener.bind(('127.0.0.1', 0))
    listener.listen()
    listener.settimeout(.1)
    stopped = threading.Event()
    dropped = threading.Event()
    workers = []

    def relay(client):
        upstream = socket.create_connection((connection['host'], connection['port']), 2)
        buffer = b''
        dropping = False
        until = float('inf')
        try:
            while not stopped.is_set() and time.monotonic() < until:
                for source in select.select([client, upstream], [], [], .02)[0]:
                    data = source.recv(8192)
                    if not data:
                        return
                    if source is client:
                        buffer += data
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            message = json.loads(line)
                            if message.get('method') == 'game.submit' and not dropped.is_set():
                                dropping = True
                                dropped.set()
                                until = time.monotonic() + .3
                            upstream.sendall(line + b'\n')
                    elif not dropping:
                        client.sendall(data)
        except OSError:
            pass
        finally:
            client.close()
            upstream.close()

    def accept():
        while not stopped.is_set():
            try:
                client, _ = listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            worker = threading.Thread(target=relay, args=(client,), daemon=True)
            workers.append(worker)
            worker.start()

    thread = threading.Thread(target=accept, daemon=True)
    thread.start()
    output.write_text(json.dumps(dict(connection, host='127.0.0.1', port=listener.getsockname()[1])))
    output.chmod(0o600)
    try:
        yield output, dropped
    finally:
        stopped.set()
        listener.close()
        thread.join(timeout=2)
        for worker in workers:
            worker.join(timeout=3)
