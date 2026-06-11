# Configuring Shared Agent Cache with Google Filestore (RWX PVC)

This guide demonstrates how to set up a shared agent cache using a ReadWriteMany (RWX) PersistentVolume backed by Google Cloud Filestore on GKE.

## Overview

A shared cache allows multiple agent worker pods to access the same cached data, improving performance and reducing redundant downloads. This setup uses Google Filestore's NFS-based storage to provide RWX access across your cluster.

## Prerequisites

- A GKE cluster with the [Filestore CSI driver enabled](https://docs.cloud.google.com/filestore/docs/csi-driver)
- A provisioned [Filestore instance](https://docs.cloud.google.com/filestore/docs/creating-instances)
- `kubectl` configured to access your cluster
- Helm 3.x installed

## Step 1: Create the Filestore-backed PersistentVolume and PersistentVolumeClaim

Create a file named `scalr-agent-cache-filestore.yaml` with the following content:

> [!IMPORTANT]
> Replace the values marked with `# REPLACE` comments with your own. The `volumeHandle` format is `modeInstance/{instance-zone}/{instance-name}/{share-name}`.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: agent-cache-pv
  annotations:
    pv.kubernetes.io/provisioned-by: filestore.csi.storage.gke.io
spec:
  storageClassName: ""
  capacity:
    storage: 1Ti  # REPLACE: match your Filestore instance capacity
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  csi:
    driver: filestore.csi.storage.gke.io
    volumeHandle: "modeInstance/{instance-zone}/{instance-name}/{path}"  # REPLACE: your Filestore instance zone, name, and share name
    volumeAttributes:
      ip: {instance-ip}  # REPLACE: your Filestore instance IP address
      volume: {path}  # REPLACE: your Filestore share name
  claimRef:
    name: agent-cache-pvc
    namespace: scalr-agent  # REPLACE: your target namespace
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: agent-cache-pvc
  namespace: scalr-agent  # REPLACE: your target namespace
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  volumeName: agent-cache-pv
  resources:
    requests:
      storage: 1Ti  # REPLACE: must match the PV capacity above
```

Apply the configuration:

```shell
kubectl apply -f agent-cache-filestore.yaml
```

## Step 2: Verify the PV and PVC

Check that both resources were created successfully. Output columns may vary slightly with your `kubectl` version.

Verify the PersistentVolume:

```shell
kubectl get pv agent-cache-pv
```

Expected output — `STATUS` must be `Bound` and `CLAIM` must point to your PVC:

```text
NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                         STORAGECLASS   REASON   AGE
agent-cache-pv   1Ti        RWX            Retain           Bound    scalr-agent/agent-cache-pvc                           1m
```

Verify the PersistentVolumeClaim (replace `scalr-agent` with your target namespace):

```shell
kubectl get pvc agent-cache-pvc -n scalr-agent
```

Expected output — `STATUS` must be `Bound` and `VOLUME` must be your PV:

```text
NAME              STATUS   VOLUME           CAPACITY   ACCESS MODES   STORAGECLASS   AGE
agent-cache-pvc   Bound    agent-cache-pv   1Ti        RWX                           1m
```

Inspect the PVC details:

```shell
kubectl describe pvc agent-cache-pvc -n scalr-agent
```

Expected output — `Status: Bound` and an empty (`<none>`) events list; any binding problem shows up as warning events here:

```text
Name:          agent-cache-pvc
Namespace:     scalr-agent
StorageClass:
Status:        Bound
Volume:        agent-cache-pv
...
Events:        <none>
```

The PV and the PVC each report their own status, and both must be `Bound` before the cache volume can be used. Statuses you may see instead:

| Resource | Status | What it means | What to do |
|---|---|---|---|
| PVC | `Pending` | The claim cannot find a PV to bind to | Check that the PV exists and that its `storageClassName`, `claimRef`, and capacity match the PVC — see [PVC stuck in Pending state](#pvc-stuck-in-pending-state) |
| PV | `Available` | The PV is not claimed by any PVC | Normally transient (binding takes a few seconds); if it persists, the PVC is missing or its name/namespace does not match the PV's `claimRef` |
| PV | `Released` | The PVC it was bound to has been deleted, and the PV still references it | Clear the stale reference: `kubectl patch pv agent-cache-pv --type json -p '[{"op": "remove", "path": "/spec/claimRef/uid"}]'` |
| PV | `Failed` | Automatic reclamation of the volume failed | Inspect the events with `kubectl describe pv agent-cache-pv` |

## Step 3: Configure the Scalr Agent Helm Chart

You can configure the agent to use the shared cache in any of the ways below. The examples show only the cache-related values — combine them with the rest of your agent configuration (such as the agent token and URL), and replace the `scalr-agent` namespace with your target namespace.

If you haven't already, add the Scalr Agent Helm repository:

```shell
helm repo add scalr-agent https://scalr.github.io/agent-helm/
helm repo update
```

### Option A: Using Helm CLI flags

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --namespace scalr-agent \
  --set persistence.cache.enabled=true \
  --set persistence.cache.persistentVolumeClaim.claimName=agent-cache-pvc \
  --set agent.providerCache.enabled=true \
  --set agent.providerCache.sizeLimit=40Gi  # Adjust based on your needs; must not exceed the PV capacity
  ...
```

### Option B: Using a values file

Create a file named `agent-values.yaml`:

```yaml
persistence:
  cache:
    enabled: true
    persistentVolumeClaim:
      claimName: agent-cache-pvc

agent:
  providerCache:
    enabled: true
    sizeLimit: 40Gi  # Adjust based on your needs; must not exceed the PV capacity
```

Install or upgrade the chart:

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --namespace scalr-agent \
  --values agent-values.yaml
```

## Step 4: Verify the Cache is Functioning

Trigger a run and check the initialization stage output in the Scalr run console. While the cache is still warming up, providers are downloaded and stored in the cache — it may take a few runs before a provider is cached:

```text
Initializing plugins...
Initialized 20 plugins in 79.39s (20 downloaded)
```

Once providers are cached, subsequent runs — including runs on other task pods sharing the volume — pick it up from the cache:

```text
Initializing plugins...
Initialized 20 plugins in 6.09s (20 used from cache)
```

Seeing `used from cache` across runs confirms the shared cache volume is mounted and working end to end.

## Troubleshooting

### PVC stuck in Pending state

- Verify your Filestore instance is in the same VPC and region
- Check that the IP address and volume name are correct
- Ensure the CSI driver is installed: `kubectl get csidrivers`

## Additional Resources

- [GKE Filestore CSI Driver Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/filestore-csi-driver)
- [Filestore Documentation](https://cloud.google.com/filestore/docs)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
