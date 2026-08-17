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

Before recording an engine or flag experiment, capture the versions actually
running in the container:

```bash
./scripts/check-container
docker exec gfx906-llama-docker sh -lc 'cat /opt/therock/VERSION'
docker image inspect kinchahoy/gfx906-llama-docker:latest \
  --format 'image={{.Id}} created={{.Created}} labels={{json .Config.Labels}}'
```

Copy the llama-server version, TheRock version, image ID, and source-build
revision into the run note. The host build directory is intentionally external
so a specialized gfx906 fork can be swapped in with `./scripts/build-image`.

Model catalog edits use the same deploy helper. Keep the documented four weight
sets and six profiles, use `hf-repo` rather than direct GGUF paths, and leave
KV-cache precision native. Refresh the curated cache index first; production is
offline and will never download missing model data:

```bash
./scripts/prepare-mi60-router-cache
./scripts/redeploy-container
```

To add a cached model artifact, edit
`models/cache-manifest.tsv` (repository, snapshot pattern, minimum file size,
and exposed filename), add its profile to
`live-monitored/llama-server-models.ini`, then run the two commands above.
Rows for one repository are selected from one snapshot, and group minimums
protect sharded models. This keeps model onboarding out of the cache-preparer
shell code.

The normal Hugging Face cache is retained for maintenance and experiments. The
router sees only `~/.cache/huggingface/mi60-router`, which hard-links the four
approved weight sets plus Qwen/Gemma projectors and Gemma's MTP sidecar. Use the
aliases printed by `./scripts/check-container`; Qwen medium is the default, with
xhigh and no-reasoning variants available.

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
