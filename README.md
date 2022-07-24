Terraform AWS VPN
===============

Terraform configurations defining an AWS EC2 deployed proxy forwarding web traffic to an on-premise web server over a VPN connection.

Usage
---------------

Using the Terraform configurations requires that we define some parameters and, possibly, pass some variables to our `terraform` calls.

1.  Define the `terraform.tfvars` variable definitions file.<br>
    e.g.
    ```
    aws_ssh_key = "<ssh_public_key>"
    ```
1.  Run the `terraform` commands, defining any required variables.<br>
    e.g.
    ```
    AWS_PROFILE=<aws_cli_profile> terraform plan
    ```

Variables
--------------

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `tag_environment` | `terraform_aws_vpn` | `Envirnoment` tag added to every resource defined.<br>**Note**: This tag will not be defined on resources that are implicitly created, such as the default route table created for a new VPC. |
| `aws_region` | `us-east-1` | Region where resources should be deployed. |
| `vpn_site_ip` | undefined | IP address of remote site VPN endpoint. |
| `vpn_bgp_asn` | 65000 | ASN for BGP used for the VPN connection.<br>**Note**: This is not relevant to this configuration as static routes are being utilized. |
| `vpn_routes` | `[ "192.168.1.0/24" ]` | List of subnets available on the remote end of the VPN connection. |
| `aws_ssh_key` | undefined | SSH public key associated with EC2 instances. |
