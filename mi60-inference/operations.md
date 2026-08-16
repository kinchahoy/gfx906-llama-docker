# Operations quick guide

## Dockge and inference

- Dockge: `http://localhost:5005`
- Inference API/UI: `http://localhost:8000`
- Stack: `mi60-llamaswap`
- Live container: `gfx906-llama-docker`

```bash
docker logs -f gfx906-llama-docker
docker restart gfx906-llama-docker
curl -s http://localhost:8000/health
```

Build a different local engine, then redeploy the stack in Dockge:

```bash
./scripts/build-image /path/to/llama.cpp/build
./scripts/redeploy-container
```

Model catalog edits use the same deploy helper. Keep the documented four-model
catalog, use `hf-repo` rather than direct GGUF paths, and leave KV-cache
precision native. The helper recreates the owning Dockge stack and runs the
health/model check:

```bash
./scripts/redeploy-container
```

## Useful telemetry

```bash
watch -n 1 'rocm-smi --showtemp --showclocks --showpower --showuse --showfan'
```

Inspect active power limits:

```bash
rocm-smi --showmaxpower
```

Temporarily test GPU1 at 177 W; reboot or `VR-gpu-setup.service` restores the
configured 160 W cap:

```bash
sudo rocm-smi -d 1 --setpoweroverdrive 177 --autorespond y
```

Do not combine a power-cap change, clock lock, and fan-curve change in one
test. A/B one variable against the same uncached prompt.

## Temporary autonomous lab control

Install a root-owned, narrowly scoped controller and grant access for three
hours:

```bash
sudo ./scripts/install-mi60-lab-control 180
```

The grant permits only bounded GPU caps, fixed manifold-fan speeds from 70--100%,
status, normal-profile restore, and revocation. It cannot run arbitrary root
commands. A systemd timer restores the selected `210/170 W`, restarts the saved
CoolerControl profile, and removes the sudo grant automatically. A small
boot-time cleanup unit provides the same restore-and-revoke behavior if the
machine reboots before the transient timer fires.

Fixed manifold-fan mode stops CoolerControl but does not disable it. A normal reboot
starts `coolercontrold.service` and `apply_on_boot=true` reapplies the saved
`mi60blower` curve; the cleanup unit then confirms `210/170 W`, restarts that
curve, and revokes the grant. Expiry, `restore`, and `revoke` restore it
immediately without requiring a reboot.

Revoke early and restore normal settings:

```bash
sudo -n /usr/local/sbin/mi60-lab-control revoke
```

The installed helper remains root-owned but is unusable through sudo after
revocation. Re-run the installer to start another timed session.

## Permanent production profile

After validating a new cap and fan curve, install the maintained production
profile with:

```bash
sudo ./scripts/install-mi60-production-profile
```

The installer backs up `/usr/local/bin/VR-gpu-init.sh` and
`/etc/coolercontrol/config.toml`, installs `210/170 W` boot caps, updates the
controller's restore defaults, and makes the Noctua manifold fan reach 96% at
75 C. It then restarts and verifies the boot and CoolerControl services and
revokes temporary lab access.
