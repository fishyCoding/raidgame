# Running a dedicated server

This is how the game is played. There is one server, it is always up, and the
menu has a single JOIN MATCHMAKING button pointed at `Net.MATCHMAKING_HOST` -
players do not host each other and there is nowhere to type an address.

`Net.serve()` is the same session as `Net.host()` with one thing left out -
nobody asks for a character - and every other difference follows from that.
`host()` is still in the file because the two-process test harnesses need a
session that comes up without a server beside them; nothing player-facing calls
it.

The server waits. A match does not start until two players have arrived, and
when the last of them leaves it reloads the level and waits for the next two.

## What works over the wire

Movement, guards, everyone seeing everyone, combat, loot and bodies. Rounds and
grenades are drawn everywhere and count on the server; a grapple is thrown on
every machine and the anchor is sent, so you can watch somebody else swing;
guards leave a body carrying what they died with, and so do players.

Still per-machine: a live player's inventory (only the body it becomes is sent)
and the deploy/extract flow.

## 1. The instance

In the Oracle console: **Compute → Instances → Create instance**.

| Field | What to pick |
| --- | --- |
| Name | `raid-server` |
| Image | Canonical Ubuntu 24.04 |
| Shape | **Ampere → VM.Standard.A1.Flex**, 4 OCPU / 24 GB |
| Networking | create a new VCN, and **Assign a public IPv4 address: yes** |
| SSH keys | paste your public key |

The A1 shape is the good one and all four cores are inside the Always Free
allowance. **"Out of host capacity" is the normal outcome, not a problem with
your account** - free Ampere capacity is genuinely scarce, and it can be empty
in every availability domain for weeks at a time. In order of what actually
helps:

1. Ask for **1 OCPU / 6 GB** rather than 4 / 24. A smaller request fits into
   fragments of a host that cannot take a big one. It is still more machine than
   this game needs.
2. Cycle the availability domains at that smaller size. The answer is per-AD and
   per-moment; the error comes back instantly, so this costs seconds.
3. Retry off-peak for the region. Capacity frees up unpredictably.
4. Take **VM.Standard.E2.1.Micro** - x86, 1 GB of RAM, always available. Nothing
   here changes: `setup.sh` reads the architecture off the machine and installs
   the matching Godot. It also adds a 2 GB swapfile on any box under 2 GB of
   RAM, because importing the project is the one step that will not fit
   otherwise. You can move to A1 later if capacity appears.

No SSH key yet? On your PC:

```powershell
ssh-keygen -t ed25519 -C raid-server
# paste the contents of C:\Users\Computer\.ssh\id_ed25519.pub into the console
```

Write down the **public IP address** when the instance finishes provisioning.

## 2. Let UDP in

This is the step everyone forgets, and it fails in the most confusing way: the
server looks perfectly healthy in `systemctl status` and simply never answers.

Instance details → click the **Virtual cloud network** link → **Security Lists**
→ **Default Security List** → **Add Ingress Rules**:

- Stateless: **no**
- Source CIDR: `0.0.0.0/0`
- IP Protocol: **UDP**
- Destination Port Range: `27015`

ENet is UDP only. A TCP rule here does nothing at all.

## 3. Set the machine up

```powershell
scp server\setup.sh ubuntu@<public-ip>:~
ssh ubuntu@<public-ip> "bash setup.sh"
```

That installs Godot for this machine's architecture, makes `/opt/raid`, opens
udp/27015 in the *instance's own* firewall (separate from the Oracle rule above,
and also required), and installs a `raid-server` systemd unit set to come back
after a reboot.

## 4. Send the game up

```powershell
powershell -File server\deploy.ps1 -Target ubuntu@<public-ip>
```

Packs the project, uploads it, imports it, and restarts the service. Run it
again any time you change the game - it is the whole deploy.

## 5. Play

Start the game, click **JOIN**, type the public IP, press enter. On the server:

```bash
journalctl -u raid-server -f
```

```
[server] listening on udp/27015, up to 4 players
[server] peer 1202323081 connected (1/4)
```

## Running it by hand

The service is only systemd wrapping one command, and that command is the same
one the local test uses:

```bash
/opt/godot/godot --headless --path /opt/raid -- --server
/opt/godot/godot --headless --path /opt/raid -- --server=27016   # another port
```

## Checking it before you blame the network

`server\test_dedicated.ps1` runs the whole thing on your own PC - a real server
process on 27778 and two real clients joining it over a real socket:

```powershell
powershell -File server\test_dedicated.ps1
```

It asserts the three things that break first: that exactly two characters exist
(a server that spawned one for itself would make three), that the guards are
thinking on the server and nowhere else, and that the guards are actually
*moving* - which is how you catch a server sitting paused behind a shop screen
nobody can see.

Four more runners in the same shape, each a server and two real clients:

| Runner | What it proves |
| --- | --- |
| `test_queue.ps1` | the menu: kit out, one button, and the rifle you bought is on the body a countdown later |
| `test_match.ps1` | a whole match - wait, countdown, opposite ends, shooting a guard until he dies, and racing for his body |
| `test_grapple.ps1` | a hook thrown in a real session bites, pulls, and is seen - line, anchor and all - from the other end |
| `test_death_loot.ps1` | a player who dies leaves everything they were carrying on the floor of both machines |
| `test_latecomer.ps1` | somebody joining an hour in is told about the bodies already down, and what was taken off them |

If that passes and the VM still does not answer, it is the network, in this
order of likelihood:

| Symptom | Cause |
| --- | --- |
| `could not reach <ip>` in the lobby | the VCN ingress rule (step 2) |
| same, and the rule is there | the instance firewall - re-run `setup.sh` |
| `systemctl status` shows restarting | read `journalctl -u raid-server -n 50` |
| ssh works, game does not | you opened TCP 27015 instead of UDP |

On the VM, `sudo ss -lunp | grep 27015` should show the socket bound.

## Things to know about the free tier

- Always Free covers the A1 shape up to 4 OCPU / 24 GB and 10 TB of egress a
  month. A 2D game for four people will not come close to either.
- Oracle can reclaim an **idle** Always Free instance. A server with nobody on
  it is idle by any measure they use, so if the box disappears after a quiet
  fortnight, that is why - not a billing problem.
- Keep the instance in the region closest to whoever plays most. It was fixed
  when you made the account, so this is a reason to check which region you got
  rather than something to change now.
