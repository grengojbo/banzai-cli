## banzai pipeline up

Deploy Banzai Cloud Pipeline

### Synopsis

Deploy or upgrade an instance of Banzai Cloud Pipeline based on a values file in the workspace, or initialize the workspace from an input file or an interactive session.

Depending on the --provider selection, the installer will work in the current Kubernetes context (k8s), deploy a KIND (Kubernetes in Docker) cluster to the local machine (kind), install a single-node PKE cluster (pke), or deploy a PKE cluster in Amazon EC2 (ec2).

The directory specified with --workspace, set in the installer.workspace key of the config, or $BANZAI_INSTALLER_WORKSPACE (default: ~/.banzai/pipeline/default) will be used for storing the applied configuration and deployment status.

The command requires docker or ctr (containerd) to be accessible in the system and able to run containers.

The input file will be copied to the workspace during initialization. Further changes can be done there before re-running the command (without --file).

```
banzai pipeline up [flags]
```

### Options

```
      --auto-approve               Automatically approve the changes to deploy (default true)
      --container-runtime string   Run the terraform command with "docker", "containerd" (crictl) or "exec" (execute locally) (default "auto")
  -f, --file string                Input Banzai Cloud Pipeline instance descriptor file
  -h, --help                       help for up
      --image string               Name of Docker image repository to use (default "docker.io/banzaicloud/pipeline-installer")
      --image-pull                 Pull installer image even if it's present locally (default true)
      --image-tag string           Tag of installer Docker image to use (default "latest")
  -i, --init                       Initialize workspace
      --provider string            Provider of the infrastructure for the deployment (k8s|kind|ec2|pke)
      --terraform-init             Run terraform init before apply (default true)
      --workspace string           Name of directory for storing the applied configuration and deployment status
```

### Options inherited from parent commands

```
      --color                use colors on non-tty outputs
      --config string        config file (default is $BANZAICONFIG or $HOME/.banzai/config.yaml)
      --interactive          ask questions interactively even if stdin or stdout is non-tty
      --no-color             never display color output
      --no-interactive       never ask questions interactively
      --organization int32   organization id
  -o, --output string        output format (default|yaml|json) (default "default")
      --verbose              more verbose output
```

### SEE ALSO

* [banzai pipeline](banzai_pipeline.md)	 - Manage deployment of Banzai Cloud Pipeline instances

