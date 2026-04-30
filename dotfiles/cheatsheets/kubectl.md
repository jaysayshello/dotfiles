# kubectl Cheat Sheet

> **Before running any kubectl commands, assume the IAM role for the target environment.**
> Use `assume --export` (or your equivalent) to set credentials, then verify you're pointed at the right cluster:
>
> ```
> kubectl config current-context          # show active cluster/context
> kubectl config get-contexts             # list all available contexts
> aws sts get-caller-identity             # confirm which AWS account + role is active
> ```

---

## CONTEXT / CLUSTER

```
kubectl config get-contexts                      # list all contexts
kubectl config current-context                   # show active context
kubectl config use-context <name>                # switch context
kubectl config set-context --current --namespace=<ns>  # set default namespace
```

---

## PODS

```
kubectl get pods                                 # list pods in current namespace
kubectl get pods -n <namespace>                  # list pods in a namespace
kubectl get pods -A                              # list pods across all namespaces
kubectl get pod <name> -o yaml                   # full pod spec as YAML
kubectl describe pod <name>                      # detailed pod info + events
kubectl logs <pod>                               # stream pod logs
kubectl logs <pod> -c <container>                # logs for a specific container
kubectl logs <pod> --previous                    # logs from crashed container
kubectl exec -it <pod> -- bash                   # shell into a pod
kubectl delete pod <name>                        # delete a pod (restarts if managed)
kubectl delete pod <name> --force                # force delete stuck pod
```

---

## DEPLOYMENTS

```
kubectl get deployments                          # list deployments
kubectl describe deployment <name>               # deployment details + events
kubectl rollout status deployment/<name>         # watch rollout progress
kubectl rollout history deployment/<name>        # show revision history
kubectl rollout undo deployment/<name>           # roll back to previous version
kubectl scale deployment <name> --replicas=3     # scale a deployment
kubectl set image deployment/<name> <c>=<image>  # update container image
kubectl restart deployment <name>                # rolling restart
```

---

## SERVICES & NETWORKING

```
kubectl get svc                                  # list services
kubectl get svc -n <namespace>                   # services in a namespace
kubectl describe svc <name>                      # service details + endpoints
kubectl port-forward pod/<name> 8080:80          # forward local port to pod
kubectl port-forward svc/<name> 8080:80          # forward local port to service
```

---

## CONFIGMAPS & SECRETS

```
kubectl get configmaps                           # list configmaps
kubectl get configmap <name> -o yaml             # view configmap content
kubectl get secret <name> -o yaml                # view secret (base64 encoded)
kubectl get secret <name> -o jsonpath='{.data.<key>}' | base64 -d  # decode secret value
```

---

## NAMESPACES

```
kubectl get namespaces                           # list all namespaces
kubectl create namespace <name>                  # create a namespace
kubectl delete namespace <name>                  # delete a namespace
```

---

## NODES

```
kubectl get nodes                                # list nodes
kubectl describe node <name>                     # node details + conditions
kubectl top nodes                                # node CPU/memory usage
kubectl top pods                                 # pod CPU/memory usage
kubectl cordon <node>                            # mark node unschedulable
kubectl drain <node> --ignore-daemonsets         # evict pods from node
kubectl uncordon <node>                          # mark node schedulable again
```

---

## APPLY / EDIT

```
kubectl apply -f <file.yaml>                     # apply manifest
kubectl apply -f <dir>/                          # apply all manifests in dir
kubectl delete -f <file.yaml>                    # delete resources in manifest
kubectl edit <resource> <name>                   # edit live resource in $EDITOR
kubectl patch <resource> <name> --patch '{...}'  # patch a resource field
```

---

## EVENTS & DEBUGGING

```
kubectl get events --sort-by=.lastTimestamp      # recent events sorted by time
kubectl get events -n <namespace>                # events in a namespace
kubectl run tmp --image=busybox --rm -it -- sh   # throw-away debug pod
kubectl debug <pod> --image=busybox --copy-to=tmp # debug copy of pod
```
