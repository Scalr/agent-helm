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

## Step 1: Create an EFS Access Point

We recommend mounting the cache volume through an [EFS access point](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html) rather than the file system root, with the following requirements:

- **POSIX user**: uid/gid `1000` — matching the chart's default pod user
- **Root directory**: a dedicated path (e.g. `/agent-cache`) created with owner `1000:1000` and permissions `775`

This matters because the chart's pods run as a non-root user and mount the cache volume with a subPath, so kubelet must create directories at the root of the volume on pod start. Mounting the file system root directly fails when the root directory is not writable by the agent user, or when the file system policy does not grant `elasticfilesystem:ClientRootAccess` (EFS then squashes all clients — including kubelet, which runs as root — to an anonymous user). An access point avoids both problems: EFS maps all file operations to the configured POSIX user and presents a dedicated, correctly-owned root directory.

Create the access point:

```shell
aws efs create-access-point \
  --file-system-id {file-system-id} \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory 'Path=/agent-cache,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=775}'
```

Note the `AccessPointId` (`fsap-...`) in the output — you will need it for the PersistentVolume in the next step.

## Step 2: Create the EFS-backed PersistentVolume and PersistentVolumeClaim

Create a file named `scalr-agent-cache-efs.yaml` with the following content:

> **Important**: Replace these values with your own:
>
> - `volumeHandle`: Your EFS file system ID and the access point ID from Step 1, in the format `{file-system-id}::{access-point-id}` (e.g. `fs-0123456789abcdef0::fsap-0123456789abcdef0`). Mounting the file system root (`fs-0123456789abcdef0` alone) or a subdirectory (`fs-0123456789abcdef0:/agent-cache`) also works, but requires the target directory to be writable by the agent user — see [Troubleshooting](#troubleshooting).
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
    volumeHandle: "{file-system-id}::{access-point-id}"  # REPLACE: your EFS file system and access point IDs from Step 1
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

## Step 3: Verify the PV and PVC

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

## Step 4: Configure the Scalr Agent Helm Chart

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
  --set agent.providerCache.sizeLimit=40Gi  # Adjust based on your needs
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

### Pod fails with "failed to create subPath directory for volumeMount cache-dir"

The chart mounts the cache PVC with a `cache/` subPath, so kubelet must create that directory at the root of the EFS volume when the pod starts. The error means this `mkdir` was denied — most commonly because the EFS file system policy does not grant `elasticfilesystem:ClientRootAccess`, which makes EFS squash all clients (including kubelet, which runs as root) to an anonymous user with no write permission on the root directory.

Check the file system policy:

```shell
aws efs describe-file-system-policy --file-system-id {file-system-id}
```

If the policy only allows `ClientMount`/`ClientWrite`, the recommended fix is to mount through an [EFS access point](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html) whose POSIX user matches the chart's pod user (uid/gid `1000` by default) and whose root directory is owned by that user:

```shell
aws efs create-access-point \
  --file-system-id {file-system-id} \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory 'Path=/agent-cache,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=775}'
```

Then point the PV at the access point and re-create it (the `volumeHandle` field is immutable, so the PV and PVC must be deleted and re-applied):

```yaml
  csi:
    driver: efs.csi.aws.com
    volumeHandle: "{file-system-id}::{access-point-id}"
```

With an access point, EFS maps all file operations to the configured POSIX user regardless of the client uid, so both kubelet's subPath directory creation and the agent's writes succeed. The data on the file system is not affected by re-creating the PV/PVC.

Alternatively, grant `elasticfilesystem:ClientRootAccess` in the file system policy — but note this alone lets kubelet create the directory as `root:root`, so the non-root agent process still needs the directory ownership or permissions adjusted to write into it. The access point approach handles both at once.

### Permission denied errors on the cache volume

- If mounting the file system root, ensure its ownership/permissions allow the agent user (uid `1000` by default) to write
- Alternatively, mount through an EFS access point with an appropriate POSIX user and root directory configuration

## Additional Resources

- [Amazon EFS CSI Driver Documentation](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
- [Amazon EFS Documentation](https://docs.aws.amazon.com/efs/latest/ug/whatisefs.html)
- [Amazon EFS Performance](https://docs.aws.amazon.com/efs/latest/ug/performance.html)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
