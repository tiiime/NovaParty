"""TCP fault injector: keep sockets open while dropping selected game traffic."""
import json
import select
import socket
import threading


class GameLink:
    def __init__(self, host, port):
        self.target = host, port
        self.listener = socket.socket()
        self.listener.bind(('127.0.0.1', 0))
        self.listener.listen()
        self.listener.settimeout(.1)
        self.port = self.listener.getsockname()[1]
        self.stopped = threading.Event()
        self.lock = threading.Lock()
        self.links = []
        self.workers = []
        self.commands = []
        self.thread = threading.Thread(target=self.accept, daemon=True)

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_):
        self.stopped.set()
        self.listener.close()
        self.thread.join(timeout=2)
        for worker in self.workers:
            worker.join(timeout=2)

    def interrupt_existing(self, mode):
        assert mode in ['close', 'both', 'upstream', 'downstream']
        with self.lock:
            current = [link for link in self.links if not link['closed']]
            assert current, 'no active game connection'
            for link in current:
                link['mode'] = mode
        return len(current)

    def lose_next_command_reply(self):
        self.commands.clear()
        with self.lock:
            for link in self.links:
                if not link['closed']:
                    link['armed'] = True

    def accept(self):
        while not self.stopped.is_set():
            try:
                client, _ = self.listener.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            link = {'client': client, 'mode': 'pass', 'closed': False}
            with self.lock:
                self.links.append(link)
            worker = threading.Thread(target=self.relay, args=(link,), daemon=True)
            self.workers.append(worker)
            worker.start()

    def relay(self, link):
        client = link['client']
        upstream = None
        buffer = b''
        try:
            upstream = socket.create_connection(self.target, timeout=2)
            client.settimeout(1)
            upstream.settimeout(1)
            while not self.stopped.is_set():
                mode = link['mode']
                if mode == 'close':
                    return
                for source in select.select([client, upstream], [], [], .02)[0]:
                    mode = link['mode']
                    data = source.recv(16384)
                    if not data:
                        return
                    direction = 'upstream' if source is client else 'downstream'
                    trigger = False
                    if source is client:
                        buffer += data
                        while b'\n' in buffer:
                            line, buffer = buffer.split(b'\n', 1)
                            message = json.loads(line)
                            if message.get('type') == 'command':
                                self.commands.append(message)
                                if link.get('armed'):
                                    trigger = True
                                    link['armed'] = False
                    if mode not in ['both', direction]:
                        (upstream if source is client else client).sendall(data)
                    if trigger:
                        link['mode'] = 'both'
        except OSError:
            pass
        finally:
            link['closed'] = True
            client.close()
            if upstream:
                upstream.close()
