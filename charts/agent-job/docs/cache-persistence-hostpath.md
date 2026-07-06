# Configuring Per-Node Agent Cache with a hostPath Volume (Node-Local Disk)

This guide demonstrates how to back the agent cache with a node-local disk (local SSD or a sized boot disk) using a `hostPath` volume.

## Overview

The shared-cache setups ([GKE Filestore](cache-persistence-filestore.md), [Amazon EFS](cache-persistence-efs.md)) use a ReadWriteMany network volume: one cache, shared by every task pod in the cluster. That is the easiest to operate, but network-volume throughput is shared across all nodes and may degrade under load.

A `hostPath` cache trades global sharing for raw speed: each node keeps its own cache on its own disk. Local SSD is far faster than any network volume and removes the shared-throughput ceiling.

Choose `hostPath` when:

- Your runs are IO-heavy on the cache and the RWX volume is the bottleneck
- Your node pools have local SSDs (or generously sized boot disks)
- You accept a per-node cache scope: every node warms up its own cache, so a run scheduled on a fresh node downloads providers once for that node

Stay with a RWX PVC when you want a single warm cache cluster-wide, or when your cluster policy forbids `hostPath` volumes (see [Security considerations](#security-considerations)).

### How it works

With `persistence.cache.hostPath.enabled=true`:

- The `cache-dir` volume in the controller and every task pod becomes a `hostPath` mount of `persistence.cache.hostPath.path`. It takes precedence over `persistentVolumeClaim` and `emptyDir`, and no PVC is created.
- The persistent cache subPath layout (`cache/binaries`, `cache/providers`, etc.) applies exactly as in the PVC case, so the worker and runner containers share the same per-node directory tree.
- The node path must be prepared before use: made writable by the non-root agent user (Kubernetes does not apply `fsGroup` to hostPath volumes). This is handled by a small node-preparation DaemonSet that is **installed once per cluster, separately from the chart** — node preparation is cluster-level infrastructure, shared by every agent release that uses the same path, not something each release should manage. See [Step 2](#step-2-deploy-the-node-preparation-daemonset-cluster-wide).

## Prerequisites

- A Kubernetes cluster where the target namespace permits `hostPath` volumes — they are forbidden under the Pod Security Admission `baseline` and `restricted` profiles, and are commonly blocked by Gatekeeper/OPA or Kyverno policies
- Nodes with a suitable local disk path (see Step 1)
- `kubectl` configured to access your cluster
- Helm 3.x installed

## Step 1: Choose the Node Path

This is the step where hostPath setups usually go wrong. The path must satisfy three requirements:

1. **It must be backed by a real disk with enough space.** `hostPath` has no capacity enforcement: the cache consumes the backing disk's free space and counts toward the node's ephemeral storage, so an undersized disk leads to `No space left on device` failures in runs or node disk-pressure eviction.
2. **It must not be on a `noexec` mount.** The cache stores OpenTofu/Terraform and provider binaries that are executed in place. On a `noexec` filesystem, runs fail with intermittent `fork/exec ... permission denied` errors.
3. **It must not be a directory reserved by other node agents.** For example, `/home/kubernetes/flexvolume` on GKE is scanned by the kubelet for Flexvolume plugins — placing files there makes every kubelet in the cluster log errors (see [agent-helm#33](https://github.com/Scalr/agent-helm/issues/33)).

Nothing validates these requirements for you — a wrong path surfaces later as failing runs (see [Troubleshooting](#troubleshooting)), so choose carefully up front.

### GKE

| Node pool | Recommended path | Notes |
|---|---|---|
| With local SSD (`--local-ssd-count N`) | `/mnt/disks/ssd0/scalr-agent-cache` | GKE formats and mounts local SSDs at `/mnt/disks/ssd0`, `/mnt/disks/ssd1`, ... This is the intended use case. |
| Without local SSD (boot disk) | `/home/kubernetes/bin/scalr-agent-cache` | Exec-capable, writable, not reserved. Size the boot disk accordingly. |

> [!IMPORTANT]
> On GKE nodes **without** a local SSD, `/mnt/disks` itself is a tiny (256K) tmpfs that only serves as a mount-point directory. The chart's default path (`/mnt/disks/scalr-agent-cache`) will not work there — runs fail with `No space left on device`. Also note that most other COS node paths (e.g. under `/var`) are mounted `noexec`.

To create a node pool with local SSDs:

```shell
gcloud container node-pools create scalr-agents-ssd \
  --cluster {cluster-name} \
  --zone {zone} \
  --local-ssd-count 1 \
  --machine-type n2-standard-8  # REPLACE: your machine type; local SSD support varies by machine family
```

### Other platforms

The same three requirements apply; the concrete paths depend on the platform and node OS:

- **Self-managed GCE nodes** (kOps, kubeadm, ...): unlike GKE, plain GCE does not format or mount local SSDs automatically — do it in your node startup script ([GCE local SSD docs](https://cloud.google.com/compute/docs/disks/add-local-ssd)) and point the chart at a subdirectory of the mount. Since you control node bootstrap, you can also pre-create the directory with the agent's ownership there and skip the node-preparation DaemonSet entirely.
- **EKS**: mount instance-store volumes via your node bootstrap and use a subdirectory. On read-only host OSes such as Bottlerocket, writable-and-exec locations are limited and `fork/exec` failures have been reported ([agent-helm#33](https://github.com/Scalr/agent-helm/issues/33)) — test a run on one node before rolling out widely.

## Step 2: Deploy the Node-Preparation DaemonSet (cluster-wide)

The node path must be prepared on every node before agents can use it: the chart's pods run as a non-root user, Kubernetes does not apply `fsGroup` to hostPath volumes, and a freshly created directory is root-owned. The DaemonSet below is **cluster-level infrastructure**: install it once per cluster, and every agent release pointing at the same path shares it. It is deliberately not part of the chart, so multiple releases do not each manage a copy.

On each matching node the DaemonSet must recursively sets ownership of the cache directory to the agent user/group and permissions to `0775`

Create a file named `scalr-agent-cache-init.yaml`:

> [!IMPORTANT]
> Replace the values marked with `# REPLACE` comments with your own. `HOST_PATH` and the volume `path` must both match `persistence.cache.hostPath.path` from Step 3, and the `nodeSelector` must cover every node where agent task pods can run.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: scalr-agent-cache-init
  namespace: kube-system  # REPLACE: any infra namespace whose policy permits hostPath mounts
  labels:
    app.kubernetes.io/name: scalr-agent-cache-init
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: scalr-agent-cache-init
  template:
    metadata:
      labels:
        app.kubernetes.io/name: scalr-agent-cache-init
    spec:
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: 5
      nodeSelector:
        cloud.google.com/gke-nodepool: scalr-agents-ssd  # REPLACE: the nodes where agent task pods run
      # tolerations: []  # add if your agent node pool is tainted
      containers:
        - name: cache-init
          image: busybox:1.37  # any image with a POSIX shell and chown/chmod works
          env:
            - name: HOST_PATH
              value: /mnt/disks/ssd0/scalr-agent-cache  # REPLACE: same as persistence.cache.hostPath.path
            - name: CACHE_UID
              value: "1000"  # REPLACE only if you override the chart's podSecurityContext user
            - name: CACHE_GID
              value: "1000"  # REPLACE only if you override the chart's podSecurityContext group
            - name: CACHE_DIR
              value: /scalr-agent-cache  # in-container mount of the cache
          command:
            - /bin/sh
            - -ec
            - |
              echo "preparing host cache directory ${HOST_PATH} (uid=${CACHE_UID} gid=${CACHE_GID}, recursive)"
              chmod -R 0775 "${CACHE_DIR}"
              chown -R "${CACHE_UID}:${CACHE_GID}" "${CACHE_DIR}"
              echo "host cache directory ${HOST_PATH} ready"
              while true; do sleep 3600; done
          securityContext:
            runAsNonRoot: false
            runAsUser: 0
            runAsGroup: 0
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
              add: ["CHOWN", "FOWNER", "DAC_OVERRIDE"]
          resources:
            requests:
              cpu: 10m
              memory: 16Mi
            limits:
              cpu: 50m
              memory: 64Mi
          volumeMounts:
            - name: cache-dir
              mountPath: /scalr-agent-cache
      volumes:
        - name: cache-dir
          hostPath:
            path: /mnt/disks/ssd0/scalr-agent-cache  # REPLACE: same as HOST_PATH above
            type: DirectoryOrCreate
```

Apply and verify it is healthy on all target nodes:

```shell
kubectl apply -f scalr-agent-cache-init.yaml
kubectl get daemonset scalr-agent-cache-init -n kube-system
kubectl logs -n kube-system -l app.kubernetes.io/name=scalr-agent-cache-init --tail=5
```

Expected log output on each node:

```text
preparing host cache directory /mnt/disks/ssd0/scalr-agent-cache (uid=1000 gid=1000, recursive)
host cache directory /mnt/disks/ssd0/scalr-agent-cache ready
```

To re-run preparation (e.g. after fixing a node, or changing the agent uid/gid):

```shell
kubectl rollout restart daemonset/scalr-agent-cache-init -n kube-system
```

If you already pre-provision node directories via node startup scripts or your own tooling, you can skip this step — but make sure your provisioning covers ownership, permissions, and the exec requirement.

## Step 3: Configure the Scalr Agent Helm Chart

The examples show only the cache-related values — combine them with the rest of your agent configuration (such as the agent token and URL).

Create or extend your `agent-values.yaml`:

```yaml
persistence:
  cache:
    hostPath:
      enabled: true
      path: /mnt/disks/ssd0/scalr-agent-cache  # REPLACE: your node path from Step 1

# Schedule task pods only on nodes that actually have the disk
# (the same nodes the Step 2 DaemonSet targets):
task:
  nodeSelector:
    cloud.google.com/gke-nodepool: scalr-agents-ssd  # REPLACE: your node pool label

# Recommended: cache providers and modules, not just binaries
agent:
  providerCache:
    enabled: true
    sizeLimit: 20Gi  # soft limit, per node
```

Install or upgrade the chart:

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --namespace scalr-agent \
  --values agent-values.yaml
```

> [!NOTE]
> When `hostPath.enabled` is true it takes precedence: `persistence.cache.enabled` (PVC mode) is ignored for the cache volume and no PVC is created. Multiple agent releases may point at the same node path — they share the per-node cache and the same node-preparation DaemonSet.

## Step 4: Verify the Cache is Functioning

Trigger a run and check the initialization stage output in the Scalr run console. The first run on each node warms that node's cache:

```text
Initializing plugins...
Initialized 20 plugins in 79.39s (20 downloaded)
```

Subsequent runs on the same node pick it up from the cache:

```text
Initializing plugins...
Initialized 20 plugins in 6.09s (20 used from cache)
```

Unlike the RWX setups, `used from cache` is expected per node: a run landing on a freshly added node downloads again, once, for that node.

## Security Considerations

- `hostPath` volumes are forbidden by the Pod Security Admission `baseline` and `restricted` profiles; the namespace must run at the `privileged` level or carry a policy exemption. Gatekeeper/OPA and Kyverno installations often restrict `hostPath` as well — allowlist the cache path if needed.
- The node-preparation container is the only piece that runs as root (it must chown the node directory). The manifest in Step 2 is hardened: all capabilities dropped except `CHOWN`/`FOWNER`/`DAC_OVERRIDE`, no privilege escalation, read-only root filesystem, no service account token. Since it is cluster infrastructure you install yourself, it can live in an infra namespace (e.g. `kube-system`) with a permissive policy, keeping the agent namespace's policy surface smaller.
- The agent and runner containers keep running as the regular non-root user; the hostPath directory is made group-writable for them by the preparation step.

## Operational Notes

- **No size enforcement.** Nothing caps the cache at the volume level. Use the agent-side limits (`agent.providerCache.sizeLimit`, `agent.binaryCache.sizeLimit` — both per node) and size the disk with headroom, or the node risks disk-pressure eviction.
- **Node replacement is free cleanup.** The cache lives and dies with the node — autoscaled or upgraded-away nodes take their cache with them, and new nodes start cold.

## Troubleshooting

### Runs fail with `OSError: [Errno 28] No space left on device` at the start of a run

The write is landing on a filesystem that is full or tiny — classically the GKE tmpfs trap: no local SSD on the node, so the default path sits inside the 256K `/mnt/disks` tmpfs. Confirm from the node:

```shell
kubectl debug node/{node-name} -it --image=ubuntu
# the node filesystem is mounted at /host inside the debug pod:
df -h /host/mnt/disks/scalr-agent-cache   # a 256K tmpfs here confirms the trap
df -i /host/mnt/disks/scalr-agent-cache   # inode exhaustion also reports ENOSPC
```

Fix: use a node pool with local SSDs, or point `persistence.cache.hostPath.path` at a boot-disk location (see [Step 1](#step-1-choose-the-node-path)).

### Runs fail with `fork/exec ... permission denied`

The path is on a `noexec` mount, or ownership was never fixed. Check the `scalr-agent-cache-init` pod log on the affected node; if you provision nodes yourself instead of using the Step 2 DaemonSet, verify your provisioning covers exec and ownership. See [agent-helm#33](https://github.com/Scalr/agent-helm/issues/33) for the GKE/COS background.

### scalr-agent-cache-init pod in `CrashLoopBackOff`

The preparation script failed on that node — `kubectl logs` on the pod shows which command failed (typically `chmod`/`chown` on an unwritable or read-only path).

### Runs on some nodes are slow (always downloading)

Per-node scope means new/replaced nodes start with a cold cache. If cold starts dominate, your node churn may be too high for a per-node cache — consider the RWX shared-cache setups instead.

## Additional Resources

- [Kubernetes hostPath volumes](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
- [GKE local SSDs](https://cloud.google.com/kubernetes-engine/docs/concepts/local-ssd)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [GKE Filestore shared cache guide](cache-persistence-filestore.md)
- [Amazon EFS shared cache guide](cache-persistence-efs.md)
