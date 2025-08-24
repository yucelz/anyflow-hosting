# N8N GCP Terraform Project

A complete, production-ready Terraform project for deploying n8n workflow automation platform on Google Cloud Platform (GCP) using Google Kubernetes Engine (GKE).

## 🏗️ Architecture

This project creates a robust, scalable n8n deployment with:

- **GKE Cluster** with auto-scaling node pools
- **PostgreSQL Database** with persistent storage
- **Google Load Balancer** with SSL termination
- **VPC Network** with proper security controls
- **Monitoring & Logging** integration
- **Multi-environment support** (dev/staging/prod)

## 📁 Project Structure

```
n8n-gcp-terraform/
├── README.md                   # This file
├── .gitignore                  # Git ignore rules
├── terraform.tfvars.example   # Example configuration
├── versions.tf                 # Terraform version constraints
├── variables.tf                # Root module variables
├── main.tf                     # Root module configuration
├── outputs.tf                  # Root module outputs
├── modules/                    # Terraform modules
│   ├── gke/                   # GKE cluster module
│   ├── network/               # VPC network module
│   └── n8n/                   # N8N application module
├── environments/              # Environment-specific configs
│   ├── dev/                   # Development environment
│   ├── staging/               # Staging environment
│   └── prod/                  # Production environment
├── scripts/                   # Deployment scripts
│   ├── deploy.sh             # Main deployment script
│   ├── destroy.sh            # Destruction script
│   └── get-credentials.sh    # Get connection info
└── docs/                     # Additional documentation
    ├── DEPLOYMENT.md
    ├── TROUBLESHOOTING.md
    └── ARCHITECTURE.md
```

## 🚀 Quick Start

### Prerequisites

1. **Google Cloud Platform Account** with billing enabled
2. **Terraform** >= 1.0
3. **Google Cloud SDK** (`gcloud`)
4. **kubectl** for cluster management
5. **Domain name** for SSL certificate

### Initial Setup

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd n8n-gcp-terraform
   ```

2. **Authenticate with GCP:**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   gcloud config set project YOUR_PROJECT_ID
   ```

3. **Configure your environment:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

4. **Deploy:**
   ```bash
   # First deploy infrastructure only
./scripts/deploy.sh dev plan-infra
./scripts/deploy.sh dev apply-infra

# Then deploy applications
./scripts/deploy.sh dev plan-apps  
./scripts/deploy.sh dev apply-apps
   ```

### Environment Configuration

Copy the appropriate environment template and customize:

```bash
# For development
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars

# For production  
cp environments/prod/terraform.tfvars.example environments/prod/terraform.tfvars
```

Key variables to configure:
- `project_id` - Your GCP project ID
- `domain_name` - Domain for n8n (e.g., n8n.yourdomain.com)
- `region` and `zone` - GCP region/zone
- Resource sizing based on your needs

## 🛠️ Usage

### Deployment Commands

```bash
#  # First deploy infrastructure only
./scripts/deploy.sh dev plan-infra

# Apply deployment
./scripts/deploy.sh dev apply-infra

# Then deploy applications
./scripts/deploy.sh dev plan-apps  

# Apply deployment
./scripts/deploy.sh dev apply-apps

# Check status
./scripts/get-credentials.sh dev

# Destroy (careful!)
./scripts/destroy.sh dev
```

### Manual Terraform Commands

```bash
# Initialize
terraform init

# Plan with environment config
terraform plan -var-file=environments/dev/terraform.tfvars

# Apply
terraform apply -var-file=environments/dev/terraform.tfvars

# Get outputs
terraform output
```

### Accessing N8N

1. **Get credentials:**
   ```bash
   ./scripts/get-credentials.sh dev
   ```

2. **Configure DNS:**
   Point your domain to the static IP address shown in outputs

3. **Access N8N:**
   - URL: `https://your-domain.com`
   - Username: From terraform outputs
   - Password: From terraform outputs (sensitive)

### Kubectl Commands

```bash
# Configure kubectl
gcloud container clusters get-credentials CLUSTER_NAME --zone ZONE --project PROJECT_ID

# Check pods
kubectl get pods -n n8n

# Check logs
kubectl logs -n n8n deployment/n8n-deployment -f

# Scale N8N
kubectl scale deployment n8n-deployment --replicas=2 -n n8n

# Port forward for local access
kubectl port-forward -n n8n service/n8n-service 8080:80
```

## 🔧 Configuration Options

### Environment Sizes

**Development:**
- 1 node, e2-medium, preemptible
- Minimal resources and storage
- Basic monitoring

**Production:**
- 2+ nodes, e2-standard-2, non-preemptible
- High availability, multiple replicas
- Full monitoring and security

### Key Features

- **Auto-scaling:** Horizontal pod autoscaler and cluster autoscaler
- **High Availability:** Multiple replicas with anti-affinity
- **Security:** Network policies, Workload Identity, Shielded GKE
- **Monitoring:** Prometheus metrics, Google Cloud monitoring
- **Backup:** PostgreSQL persistent volumes with snapshots
- **SSL:** Google-managed certificates with automatic renewal

## 📊 Cost Estimation

Approximate monthly costs (US Central):

| Component | Development | Production |
|-----------|-------------|------------|
| GKE Management | $74 | $74 |
| Compute (nodes) | $25 | $100 |
| Load Balancer | $18 | $18 |
| Storage | $4 | $20 |
| Static IP | $1.50 | $1.50 |
| **Total** | **~$123** | **~$213** |

*Costs vary by region and usage. Use preemptible nodes for 70% savings in dev.*

## 🔒 Security Features

- **Network Isolation:** VPC with private subnets
- **Kubernetes Security:** Network policies, pod security standards
- **Identity Management:** Workload Identity for GCP services
- **Encryption:** Data encrypted at rest and in transit
- **Access Control:** Basic auth + configurable RBAC
- **Monitoring:** Security events and audit logs

## 📚 Documentation

- [Deployment Guide](docs/DEPLOYMENT.md) - Detailed deployment instructions
- [Architecture Overview](docs/ARCHITECTURE.md) - Technical architecture details
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🔍 Monitoring & Troubleshooting

### Health Checks

```bash
# Check N8N health
curl https://your-domain.com/healthz

# Check SSL certificate status
kubectl get managedcertificates -n n8n

# Check pod logs
kubectl logs -n n8n -l app=n8n --tail=100
```

### Common Issues

1. **SSL Certificate Pending:** Can take up to 60 minutes
2. **DNS Not Resolving:** Verify A record points to static IP
3. **Pods Not Starting:** Check resource limits and node capacity
4. **Database Connection:** Verify PostgreSQL service is running

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with development environment
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues:** Create GitHub issues for bugs and feature requests
- **Documentation:** Check the `docs/` directory
- **N8N Support:** Visit [n8n documentation](https://docs.n8n.io/)
- **GCP Support:** Check [GKE documentation](https://cloud.google.com/kubernetes-engine/docs)

---

**⚠️ Important Notes:**

- Always test in development before deploying to production
- Backup your n8n workflows and database regularly
- Monitor costs and set up billing alerts
- Keep Terraform state secure (use remote state for production)
- Update dependencies regularly for security patches