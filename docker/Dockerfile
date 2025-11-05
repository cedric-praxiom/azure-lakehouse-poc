FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf -y update --allowerasing && \
    dnf -y install --allowerasing \
        unzip tar gzip git jq python3 python3-pip \
        libicu ca-certificates procps-ng which iputils curl && \
    dnf clean all

# Azure CLI
RUN rpm --import https://packages.microsoft.com/keys/microsoft.asc &&     curl -sL https://packages.microsoft.com/config/rhel/9/prod.repo -o /etc/yum.repos.d/microsoft-prod.repo &&     dnf -y install azure-cli && dnf clean all

# Terraform
RUN dnf -y install dnf-plugins-core &&     dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo &&     dnf -y install terraform && dnf clean all

# Optional Databricks CLI + Azure Identity for later scripting
RUN pip3 install --no-cache-dir databricks azure-identity

WORKDIR /work
WORKDIR /work/terraform
COPY ../terraform/ /work/terraform/


COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
