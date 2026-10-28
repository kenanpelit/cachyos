-- ipc-socket.lua
-- mshellctl (play toggle / stop / …) talks to mpv over /tmp/mpvsocket ($MARGO_MPV_SOCKET overrides it).
-- Set as input-ipc-server in mpv.conf, every new mpv took that path over: a second window (or a short-lived
-- mpv run from a script) stole the socket from the one playing, and once it quit the socket file stayed behind
-- with no one listening ("Connection refused"). Now the socket is claimed only when no live mpv holds it, so the
-- mpv already playing keeps it. A path given on the command line (start-mpv, mshellctl's companion) wins as before.

local msg = require "mp.msg"

local path = os.getenv("MARGO_MPV_SOCKET") or "/tmp/mpvsocket"

-- An --input-ipc-server passed on the command line (or by a profile) is kept as it is.
if (mp.get_property("input-ipc-server") or "") ~= "" then return end

-- Whether a live mpv answers on the socket. Without python3 the socket is simply claimed (the old behaviour).
local function socket_live()
    local result = mp.command_native({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = { "python3", "-c",
            "import socket,sys\ns=socket.socket(socket.AF_UNIX)\ns.settimeout(0.3)\n"
            .. "try:\n s.connect(sys.argv[1])\nexcept OSError:\n sys.exit(1)\n", path },
    })
    if not result or result.error_string == "init" then return false end
    return result.status == 0
end

if socket_live() then
    msg.verbose(path .. " is held by another mpv: this one runs without an IPC socket")
    return
end
os.remove(path) -- a socket file left by an mpv that is gone
mp.set_property("input-ipc-server", path)
msg.verbose("IPC socket: " .. path)
