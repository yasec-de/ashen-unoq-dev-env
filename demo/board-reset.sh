#!/bin/sh
# Reset the board through the Glasgow GPIO control on TCP 8812 (same protocol as reset-target.sh).
printf 'A5=0\nA5=Z\n' | timeout 5 python3 -c "import socket,sys; s=socket.create_connection(('127.0.0.1',8812)); s.sendall(sys.stdin.buffer.read()); s.close()"
