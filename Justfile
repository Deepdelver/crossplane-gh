timeout := "300s"

# List tasks.
default:
  just --list

# Generates package files.
package-generate:
  kcl run kcl/crossplane.k > package/crossplane.yaml
  kcl run kcl/definition.k > package/definition.yaml
  kcl run kcl/compositions.k > package/compositions.yaml

# Applies Compositions and Composite Resource Definition.
package-apply:
  kubectl apply --filename package/definition.yaml && sleep 1
  kubectl apply --filename package/compositions.yaml

# Builds and pushes the package.
package-publish: package-generate
  up login --token $UP_TOKEN
  up xpkg build --package-root package --name github.xpkg
  up xpkg push --package package/github.xpkg xpkg.upbound.io/$UP_ACCOUNT/dot-github:$VERSION
  rm package/github.xpkg
  yq --inplace ".spec.package = \"xpkg.upbound.io/devops-toolkit/dot-github:$VERSION\"" config.yaml

# Combines `package-generate` and `package-apply`.
package-generate-apply: package-generate package-apply

# Create a cluster, runs tests, and destroys the cluster.
test: cluster-create package-generate-apply
  chainsaw test
  just cluster-destroy

# Runs tests once assuming that the cluster is already created and everything is installed.
test-once: package-generate-apply
  chainsaw test

# Runs tests in the watch mode assuming that the cluster is already created and everything is installed.
test-watch:
  watchexec -w kcl -w tests "just test-once"

# Creates a k3s cluster, installs Crossplane, providers, and packages, waits until they are healthy, and runs tests.
cluster-create: package-generate _cluster-create-k3s
  just package-apply
  sleep 60
  kubectl wait --for=condition=healthy provider.pkg.crossplane.io --all --timeout={{timeout}}
  kubectl wait --for=condition=healthy function.pkg.crossplane.io --all --timeout={{timeout}}

# Destroys the cluster
cluster-destroy:
  k3s-uninstall

# Creates a k3s cluster
_cluster-create-k3s:
  -k3s install
  helm upgrade --install crossplane crossplane --repo https://charts.crossplane.io/stable --namespace crossplane-system --create-namespace --wait
  for provider in `ls -1 providers | grep -v config`; do kubectl apply --filename providers/$provider; done
