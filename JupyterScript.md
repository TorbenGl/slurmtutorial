# Jupyter on the Slurm Cluster

Everything notebook-related, split out from the [main tutorial](Readme.md) because it's a topic of its own. Three parts, roughly in order of how you'll grow into them:

1. [Run Jupyter Lab on a compute node](#1-run-jupyter-lab-on-a-compute-node) — the basic "I want a notebook with a GPU" workflow.
2. [Specialized environments (multiple kernels)](#2-specialized-environments-multiple-kernels) — offer several different Python environments as selectable kernels inside one Jupyter.

> **Conventions:** angle-bracket placeholders like `<your-username>` need to be replaced with your real values.

**Prerequisite:** the project `.venv`, built with `uv sync` on the login node — see [Project setup](Readme.md#project-setup-uv--clone) and [GPU environment](Readme.md#gpu-environment-cuda-build-of-torch) in the main tutorial. It already contains `jupyterlab` and a CUDA build of torch.

---
## 1. Run Jupyter Lab on a compute node

The repo ships two scripts so you don't tunnel by hand:

- **`examples/jupyter.sh`** — run this on the login node. It submits the job,
  waits for it to start, then prints your laptop's tunnel command and the URL.
- **`examples/jupyter.sbatch`** — the job it submits: activates `.venv`, picks a
  free port, generates a token + self-signed TLS cert, and writes the connection
  details to `logs/<job>.conn`.

**Start a notebook** (login node, from the repo root):

    ./examples/jupyter.sh                  # CPU only
    ./examples/jupyter.sh --gpu            # any free MIG slice
    ./examples/jupyter.sh --gpu33 torch    # ~33 GB slice, job named jupyter-torch

When the job starts it prints a command to run **on your laptop** — a plain
**forward** tunnel through the login node — and the URL to open:

    ssh -N -L 8888:<node>:<port> slurm     # the script fills in <node>/<port>

Leave that running, then open the printed `https://localhost:8888/lab?token=...`
(self-signed cert, so the browser warns once — accept it).

**Manage sessions:**

    ./examples/jupyter.sh --list           # your running/pending Jupyter jobs
    ./examples/jupyter.sh --stop torch     # cancel it, free the GPU, drop the tunnel

> **Forward, not reverse:** the login node can resolve the compute node's name
> and route to it, so your laptop reaches Jupyter *through* the login node —
> nothing SSHes from compute back to login. Port and token/TLS are per-job, so
> two people can run this at once without colliding.

---

## 2. Specialized environments (multiple kernels)

Out of the box, the setup above gives you **one** environment: the project `.venv`. But Jupyter separates the *server* from the **kernels** it can launch — a single Jupyter Lab can offer many kernels, each pointing at a *different* Python environment. That's how you keep, say, a CUDA-torch env, a JAX env, and an env pinned to an older numpy all available in the same Lab, selectable from the launcher.

To expose an environment as a kernel, install `ipykernel` into it and register it:

```
# inside the environment you want to expose
uv add ipykernel                 # or: pip install ipykernel
python -m ipykernel install --user \
    --name project-cuda \
    --display-name "Project (CUDA)"
```

`--user` writes a small `kernel.json` into `~/.local/share/jupyter/kernels/project-cuda/`. Do this once per environment and they all appear side by side in the launcher and the kernel-picker of the same Jupyter. A natural pattern on this cluster: keep a lightweight `.venv` for *launching* Jupyter, and register your heavier project envs as kernels.

A kernelspec is just a directory containing a `kernel.json` like this — note the **absolute path** to that env's Python, which is what makes it work:

```json
{
  "argv": ["/absolute/path/to/env/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}"],
  "display_name": "Project (CUDA)",
  "language": "python"
}
```

List and remove kernels with:

```
jupyter kernelspec list          # see what's registered and where
jupyter kernelspec remove <name> # drop one
```


---

## See also

- [Main tutorial](Readme.md) — connecting, `sbatch`, logs, arrays, dependencies.
- [Project setup](Readme.md#project-setup-uv--clone) and [GPU environment](Readme.md#gpu-environment-cuda-build-of-torch) — building the `.venv` these kernels are based on.
