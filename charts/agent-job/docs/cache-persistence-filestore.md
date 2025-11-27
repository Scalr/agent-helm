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

> **Important**: Replace these values with your own:
>
> - `volumeHandle`: Format is `modeInstance/{zone}/{filestore-instance-name}/{share-name}`
> - `ip`: Your Filestore instance IP address
> - `volume`: Your Filestore share name
> - `namespace`: Your target namespace
> - `storage`: Adjust capacity to match your Filestore instance
>
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
    storage: 1Ti
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
  csi:
    driver: filestore.csi.storage.gke.io
    volumeHandle: "modeInstance/{instance-zone}/{instance-name}/{path}"
    volumeAttributes:
      ip: {instance-ip}
      volume: {path}
  claimRef:
    name: agent-cache-pvc
    namespace: scalr-agent
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: agent-cache-pvc
  namespace: scalr-agent
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: ""
  volumeName: agent-cache-pv
  resources:
    requests:
      storage: 1Ti
```

Apply the configuration:

```shell
kubectl apply -f agent-cache-filestore.yaml
```

## Step 2: Verify the PV and PVC

Check that both resources were created successfully:

```shell
# Verify PersistentVolume
kubectl get pv agent-cache-pv

# Verify PersistentVolumeClaim
kubectl get pvc agent-cache-pvc -n scalr-agent

# Check PVC status (should show "Bound")
kubectl describe pvc agent-cache-pvc -n scalr-agent
```

## Step 3: Configure the Scalr Agent Helm Chart

You can configure the agent to use the shared cache in two ways:

### Option A: Using Helm CLI flags

```shell
helm upgrade --install scalr-agent ./charts/agent-job \
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
helm upgrade --install scalr-agent ./charts/agent-job \
  --namespace scalr-agent \
  --values agent-values.yaml
```

## Troubleshooting

### PVC stuck in Pending state

- Verify your Filestore instance is in the same VPC and region
- Check that the IP address and volume name are correct
- Ensure the CSI driver is installed: `kubectl get csidrivers`

## Additional Resources

- [GKE Filestore CSI Driver Documentation](https://cloud.google.com/kubernetes-engine/docs/how-to/persistent-volumes/filestore-csi-driver)
- [Filestore Documentation](https://cloud.google.com/filestore/docs)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
