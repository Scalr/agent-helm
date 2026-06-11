# Configuring Shared Agent Cache with Amazon EFS (RWX PVC)

This guide demonstrates how to set up a shared agent cache using a ReadWriteMany (RWX) PersistentVolume backed by Amazon EFS on EKS.

## Overview

A shared cache allows multiple agent worker pods to access the same cached data, improving performance and reducing redundant downloads. This setup uses Amazon EFS's NFS-based storage to provide RWX access across your cluster.

## Prerequisites

- An EKS cluster with the [Amazon EFS CSI driver installed](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- A provisioned [EFS file system](https://docs.aws.amazon.com/efs/latest/ug/creating-using-create-fs.html) with mount targets in the subnets used by your cluster nodes
- A security group on the EFS mount targets that allows inbound NFS traffic (TCP port 2049) from the cluster nodes
- `kubectl` configured to access your cluster
- Helm 3.x installed

## Step 1: Create the EFS-backed PersistentVolume and PersistentVolumeClaim

Create a file named `scalr-agent-cache-efs.yaml` with the following content:

> **Important**: Replace these values with your own:
>
> - `volumeHandle`: Your EFS file system ID (e.g. `fs-0123456789abcdef0`). To mount through an [EFS access point](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html), use the format `{file-system-id}::{access-point-id}` (e.g. `fs-0123456789abcdef0::fsap-0123456789abcdef0`). To mount a subdirectory, use `{file-system-id}:{path}` (e.g. `fs-0123456789abcdef0:/agent-cache`).
> - `namespace`: Your target namespace
> - `storage`: A placeholder value — EFS is elastic, so Kubernetes requires the field but the EFS CSI driver does not enforce it
>
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: agent-cache-pv
  annotations:
    pv.kubernetes.io/provisioned-by: efs.csi.aws.com
spec:
  storageClassName: ""
  capacity:
    storage: 1Ti  # REPLACE: placeholder value, not enforced by EFS
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  mountOptions:
    - acregmin=1
    - acregmax=3
    - acdirmin=1
    - acdirmax=3
  csi:
    driver: efs.csi.aws.com
    volumeHandle: "{file-system-id}"  # REPLACE: your EFS file system ID, e.g. fs-0123456789abcdef0
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
kubectl apply -f scalr-agent-cache-efs.yaml
```

### About the mount options

By default, the NFS client caches file and directory attributes for up to 60 seconds. With multiple agent pods reading and writing the same cache volume concurrently, this can cause pods to observe stale file metadata — for example, a pod may see a partially written provider binary or a directory listing that does not yet include files created by another pod.

The mount options above shorten the attribute cache timeouts (`acregmin`/`acregmax` for files, `acdirmin`/`acdirmax` for directories) to 1–3 seconds so changes made by one pod become visible to others almost immediately. The trade-off is a moderate increase in NFS metadata requests, which is generally negligible for the agent cache workload.

## Step 2: Verify the PV and PVC

Check that both resources were created successfully.

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

If either resource shows `Pending` or the PV shows `Available`/`Released` instead of `Bound`, see [Troubleshooting](#troubleshooting) below.

## Step 3: Configure the Scalr Agent Helm Chart

You can configure the agent to use the shared cache in two ways. The commands below use the `scalr-agent` namespace — replace it with your target namespace.

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
  --set agent.providerCache.sizeLimit=40Gi
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
    sizeLimit: 40Gi  # Adjust based on your needs
```

Install or upgrade the chart:

```shell
helm upgrade --install scalr-agent scalr-agent/agent-job \
  --namespace scalr-agent \
  --values agent-values.yaml
```

## Troubleshooting

### PVC stuck in Pending state

- Verify the EFS file system ID in `volumeHandle` is correct
- Ensure the CSI driver is installed: `kubectl get csidrivers`

### Pod scheduling fails with "pod has unbound immediate PersistentVolumeClaims" or "persistentvolumeclaim not found"

This event appears on agent task pods when the cache PVC either does not exist in the pod's namespace or exists but is not bound to the PV.

1. Check that the PVC exists in the same namespace as the agent pods and that its name matches `persistence.cache.persistentVolumeClaim.claimName`:

   ```shell
   kubectl get pvc -n scalr-agent
   ```

   PVCs are namespaced — a PVC created in a different namespace is reported as "not found". If the `claimName` value is empty, the chart creates its own PVC named `<release-name>-cache` and expects the cluster to provision it dynamically, which fails without a default RWX storage class.

2. If the PVC exists but is Pending, inspect why it is not binding:

   ```shell
   kubectl describe pvc agent-cache-pvc -n scalr-agent
   kubectl get pv agent-cache-pv
   ```

   Common causes:

   - **`storageClassName` mismatch**: both the PV and PVC must set `storageClassName: ""` for static binding. If the PVC omits the field entirely, the cluster's default StorageClass may try to dynamically provision a new volume instead of binding to your PV.
   - **`claimRef` mismatch**: the PV's `claimRef.name` and `claimRef.namespace` must exactly match the PVC's name and namespace.
   - **Capacity mismatch**: the PVC's requested storage must not exceed the PV's declared capacity.

3. If the PV shows `Released` status (for example, after deleting and re-creating the PVC), it still references the old PVC's UID and cannot rebind. Clear the stale reference:

   ```shell
   kubectl patch pv agent-cache-pv --type json -p '[{"op": "remove", "path": "/spec/claimRef/uid"}]'
   ```

   The PV returns to `Available` and binds to the new PVC. The data on the EFS file system is unaffected.

### Pods stuck in ContainerCreating with mount timeouts

- Verify the EFS file system has mount targets in every availability zone where agent pods run
- Check that the mount target security group allows inbound TCP 2049 from the node security group
- Inspect the EFS CSI node driver logs: `kubectl logs -n kube-system -l app=efs-csi-node -c efs-plugin`

### Permission denied errors on the cache volume

- If mounting the file system root, ensure its ownership/permissions allow the agent user to write
- Alternatively, mount through an EFS access point with an appropriate POSIX user and root directory configuration

## Additional Resources

- [Amazon EFS CSI Driver Documentation](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [Amazon EFS Documentation](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html)
- [Amazon EFS Performance](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
