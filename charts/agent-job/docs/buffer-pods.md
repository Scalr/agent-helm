# Buffer Pods: Keeping Nodes Warm for Fast Run Startup

On clusters with autoscaling enabled, the cluster autoscaler only provisions new nodes when unschedulable pods appear. This means the first Scalr Run after a period of inactivity may wait several minutes for a new node to become ready before the task pod can start.

The buffer pod pattern addresses this by deploying a low-priority `Deployment` that pre-occupies resources on existing nodes. When a higher-priority task pod is scheduled, Kubernetes [preempts](https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/) the buffer pods to free capacity immediately. The cluster autoscaler then replaces the evicted buffer pods in the background, keeping nodes warm for the next run.

## Step 1 — Create a low-priority PriorityClass

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: scalr-agent-buffer
value: -10
globalDefault: false
preemptionPolicy: Never
description: "Low-priority buffer pods that reserve node capacity for Scalr task pods."
```

## Step 2 — Deploy buffer pods sized to match your task pods

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: scalr-agent-buffer
  namespace: <agent-namespace>
spec:
  replicas: 2  # keep as many nodes warm as needed
  selector:
    matchLabels:
      app: scalr-agent-buffer
  template:
    metadata:
      labels:
        app: scalr-agent-buffer
    spec:
      priorityClassName: scalr-agent-buffer
      terminationGracePeriodSeconds: 0
      nodeSelector: {}  # match the same node pool as your task pods
      tolerations: []   # match task.tolerations if set
      containers:
        - name: worker
          image: scalr/agent:latest  # pin to the same tag as agent.image.tag
          command: ["sleep", "infinity"]
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
        - name: runner
          image: scalr/runner:0.2.0  # pin to the same tag as task.runner.image.tag
          command: ["sleep", "infinity"]
          resources:
            requests:
              # Size to match task pod total: task.worker + task.runner requests
              cpu: 500m
              memory: 512Mi
```

Using the actual `scalr/agent` and `scalr/runner` images serves a second purpose: the container runtime pulls and caches the images on the node. When a real task pod is scheduled on that node, the images are already present and the pull step is skipped, eliminating a major source of cold-start latency.

## Tuning

- **`replicas`** — set to the number of nodes you want to keep warm.
- **`resources.requests`** — match the requests of the worker and runner containers separately (`task.worker.resources.requests` and `task.runner.resources.requests`). The values above reflect the chart defaults.
- **`image` tags** — pin to the same tags as `agent.image.tag` and `task.runner.image.tag` in your Helm values so the cached image is the one actually used by task pods.
- **`nodeSelector` / `tolerations`** — mirror `task.nodeSelector` and `task.tolerations` so buffer pods land on the same node pool as task pods.

> [!NOTE]
> `terminationGracePeriodSeconds: 0` ensures buffer pods are evicted instantly when preempted, releasing capacity for the incoming task pod without delay.

### Links

- [Understanding and Combining GKE Autoscaling Strategies](https://www.skills.google/focuses/15636?locale=pt_PT&parent=catalog&qlcampaign=5k-dodl-65)
