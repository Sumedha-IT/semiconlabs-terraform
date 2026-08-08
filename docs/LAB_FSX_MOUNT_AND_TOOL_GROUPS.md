# Lab FSx mounts — per-path Lustre (IT form, production)

Host = FSx IP (e.g. `10.50.10.147`). Mount name = `t4zh7bev`.

## Layout

```text
/data/                 ← local dir
/data/tools/PD         ← mount -t lustre 10.50.10.147:/t4zh7bev/tools/PD
/data/tools/DV         ← …/tools/DV
/data/tools/AL         ← …/tools/AL
/data/semicon_labs_pd  ← …/semicon_labs_pd
/data/pdk              ← …/pdk
/data/DV               ← …/DV
/data/futurense_modules
```

No `/PD`, `/DV`, or `/AL` bind shortcuts — source from actual paths only.

Domain selection via `TOOLS_LIST` (PD / DV / AL / FUTURENSE) is unchanged.

**Futurense (`FUTURENSE`)** mounts: `tools/PD`, `pdk`, `tools/DV`, `futurense_modules` — **not** `/data/semicon_labs_pd` or `/data/DV`.

### PD

```bash
mkdir -p /data/tools/PD /data/semicon_labs_pd /data/pdk

mount -t lustre 10.50.10.147:/t4zh7bev/tools/PD /data/tools/PD
mount -t lustre 10.50.10.147:/t4zh7bev/semicon_labs_pd /data/semicon_labs_pd
mount -t lustre 10.50.10.147:/t4zh7bev/pdk /data/pdk
```

```tcsh
cd /data/tools/PD
source /data/tools/PD/pdsource
```

---

### DV

```bash
mkdir -p /data/tools/DV /data/DV

mount -t lustre 10.50.10.147:/t4zh7bev/tools/DV /data/tools/DV
mount -t lustre 10.50.10.147:/t4zh7bev/DV /data/DV
```

```tcsh
cd /data/tools/DV
source /data/tools/DV/dvsource
```

---

### AL

```bash
mkdir -p /data/tools/AL /data/pdk

mount -t lustre 10.50.10.147:/t4zh7bev/tools/AL /data/tools/AL
mount -t lustre 10.50.10.147:/t4zh7bev/pdk /data/pdk
```

```tcsh
cd /data/tools/AL
source /data/tools/AL/alsource
```

---

### Futurense

```bash
mkdir -p /data/tools/PD /data/pdk /data/tools/DV /data/futurense_modules

mount -t lustre 10.50.10.147:/t4zh7bev/tools/PD /data/tools/PD
mount -t lustre 10.50.10.147:/t4zh7bev/pdk /data/pdk
mount -t lustre 10.50.10.147:/t4zh7bev/tools/DV /data/tools/DV
mount -t lustre 10.50.10.147:/t4zh7bev/futurense_modules /data/futurense_modules
```

Do **not** mount `/data/semicon_labs_pd` or `/data/DV` for Futurense.

```tcsh
cd /data/tools/PD
source /data/tools/PD/pdsource
# and/or
cd /data/tools/DV
source /data/tools/DV/dvsource
```

---

No `/PD`, `/DV`, or `/AL` binds. Only the mounts above + source from `/data/tools/...`.

## Env

```text
LAB_FSX_LUSTRE_DNS=10.50.10.147
LAB_FSX_LUSTRE_MOUNT_NAME=t4zh7bev
```

Userdata resolves `LAB_FSX_LUSTRE_DNS` to an IP when possible, then mounts:

`mount -t lustre <host>:/${FSX_MOUNT_NAME}/<rel> /data/<rel>`
