openssl genrsa -out ${REQUEST_ID}.key 2048
openssl req -new -key ${REQUEST_ID}.key -out ${REQUEST_ID}.csr -subj "/CN=${REQUEST_ID}/O=system:masters"

cat ${REQUEST_ID}.csr | base64 -w0
openssl req -in ${REQUEST_ID}.csr -noout -text

cat << EOF > signing-request.yaml 
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: ${REQUEST_ID}-csr
spec:
  groups:
  - system:authenticated
  request: $(cat ${REQUEST_ID}.csr | base64 | tr -d '\n')

  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

kubectl create -f signing-request.yaml 
kubectl get csr

kubectl certificate approve ${REQUEST_ID}-csr
kubectl get csr


kubectl get csr ${REQUEST_ID}-csr -o jsonpath='{.status.certificate}' | base64 -d > ${REQUEST_ID}.crt
cat ${REQUEST_ID}.crt 

kubectl -n kube-system exec $(kubectl get pods -n kube-system -l k8s-app=kube-dns  -o jsonpath='{.items[0].metadata.name}') -c kubedns -- /bin/cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt > ca.crt
CURRENT_CONTEXT=$(kubectl config current-context)
CURRENT_CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name == \"${CURRENT_CONTEXT}\"})].context.cluster}")
CURRENT_CLUSTER_ADDR=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"${CURRENT_CLUSTER}\"})].cluster.server}")


cat <<EOF > kubeconfig
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $(cat ca.crt | base64 -w0)
    server: ${CURRENT_CLUSTER_ADDR}
  name: k8s
contexts:
- context:
    cluster: k8s
    user: ${REQUEST_ID}-usr
  name: k8s
current-context: k8s
kind: Config
preferences: {}
users:
- name: ${REQUEST_ID}-usr
  user:
    client-certificate-data: $(cat ${REQUEST_ID}.crt | base64 -w0)
    client-key-data: $(cat ${REQUEST_ID}.key | base64 -w0)
EOF