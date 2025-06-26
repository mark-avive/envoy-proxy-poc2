# Variables for EKS Cluster Configuration

variable "kubeconfig_path" {
  description = <<-EOF
    Path to the kubeconfig file. 
    
    During deployment, the kubeconfig path is determined by:
    1. This variable (if provided and not empty)
    2. The KUBECONFIG environment variable (if set)
    3. Default: /home/mark/.kube/config-cfndev-envoy-poc
    
    This allows for environment-specific kubeconfig paths.
  EOF
  type        = string
  default     = ""
  
  validation {
    condition = can(regex("^(/[^/]+)+/?$", var.kubeconfig_path)) || var.kubeconfig_path == ""
    error_message = "The kubeconfig_path must be a valid absolute path or empty string."
  }
}
