# Log the board's debug UART (Glasgow, TCP 8811) to a file with host timestamps, reconnecting
# if the stream drops.   python3 uart-log.py OUT
import socket, sys, time
out = open(sys.argv[1], "ab", buffering=0)
while True:
    try:
        s = socket.create_connection(("127.0.0.1", 8811), timeout=5)
        s.settimeout(None)
        buf = b""
        while True:
            d = s.recv(4096)
            if not d:
                break
            buf += d
            *lines, buf = buf.split(b"\n")
            for l in lines:
                out.write(time.strftime("%H:%M:%S ").encode() + l.rstrip(b"\r") + b"\n")
    except OSError:
        pass
    time.sleep(1)
