# AutoUFW 🔥🛡️

## Automated UFW (Uncomplicated Firewall) Configuration Script

A powerful, flexible bash script to automate UFW firewall configuration for home servers and self-hosted services. Configure your firewall rules using simple CSV files with support for local networks, public ports, and Docker containers.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![UFW](https://img.shields.io/badge/UFW-Compatible-blue.svg)](https://wiki.ubuntu.com/UncomplicatedFirewall)

## ✨ Features

- 🎯 **CSV-Based Configuration** - Define rules in easy-to-edit CSV files
- 🌐 **IPv4 & IPv6 Support** - Full support for both IP protocols
- 🐳 **Docker Auto-Detection** - Automatically detects and configures Docker network rules
- 🔍 **Dry-Run Mode** - Preview changes before applying them
- 🛡️ **Network-Based Access Control** - Restrict services to specific local networks
- 🔄 **Idempotent** - Safe to run multiple times
- 🎨 **Colored Output** - Easy-to-read terminal output with color coding
- ✅ **Prerequisites Validation** - Checks for UFW installation and sudo privileges

## 📋 Requirements

- Ubuntu/Debian-based Linux distribution
- UFW (Uncomplicated Firewall) installed
- Bash 4.0 or later
- sudo privileges

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/luiz-surian/autoufw.git
cd autoufw
```

### 2. Make Script Executable

```bash
chmod +x ufw_rules.sh
```

### 3. Install Command Alias (Optional but Recommended)

```bash
./ufw_rules.sh --install-alias
source ~/.bash_aliases
```

This creates an `autoufw` command that you can use from anywhere:

```bash
autoufw --help
autoufw --show-config
autoufw --dry-run
```

### 4. First Run (Creates Configuration Files)

```bash
./ufw_rules.sh
```

On first run, the script will create configuration files from examples:

- `config/local_networks.csv` - Your local networks
- `config/external_rules.csv` - Public ports accessible from anywhere
- `config/local_services.csv` - Services accessible only from local networks

### 5. Customize Configuration

Edit the CSV files in the `config/` directory to match your setup:

#### config/local_networks.csv

```csv
name,cidr
Home_IPv4,192.168.1.0/24
Home_IPv6,2001:db8::/64
VPN,10.8.0.0/24
```

#### config/external_rules.csv

```csv
port,protocol,description
80,tcp,Public HTTP
443,tcp,Public HTTPS
25565,tcp,Minecraft Server
```

#### config/local_services.csv

```csv
port,protocol,description
22,tcp,SSH
3000,tcp,Web Application
5432,tcp,PostgreSQL
9000,tcp,Portainer
```

### 6. Preview Changes (Dry Run)

```bash
./ufw_rules.sh --dry-run
```

### 7. Apply Configuration

```bash
sudo ./ufw_rules.sh
```

## 📖 Usage

```bash
./ufw_rules.sh [options]
# Or if you installed the alias:
autoufw [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be done without executing |
| `--show-config` | Display current configuration and exit |
| `--reset` | Reset all existing UFW rules (DESTRUCTIVE!) |
| `--force` | Don't ask for confirmation (use with caution) |
| `--docker-cidr CIDR` | Set custom CIDR for Docker (e.g., 172.17.0.0/16) |
| `--no-docker` | Disable Docker rules configuration |
| `--install-alias` | Install 'autoufw' command alias in ~/.bash_aliases |
| `-h, --help` | Show help message |

### Examples

```bash
# Install the command alias (one-time setup)
./ufw_rules.sh --install-alias
source ~/.bash_aliases

# Preview what will be configured
autoufw --dry-run

# Show current configuration
autoufw --show-config

# Apply rules without Docker configuration
sudo autoufw --no-docker

# Reset all rules and apply new configuration
sudo autoufw --reset --force

# Use custom Docker CIDR
sudo autoufw --docker-cidr 172.18.0.0/16
```

## 📁 Project Structure

```ls
autoufw/
├── ufw_rules.sh                      # Main script
├── README.md                         # This file
├── LICENSE                           # GNU GPL v3 License
├── .gitignore                        # Git ignore rules
└── config/                           # Configuration directory
    ├── local_networks.csv.example    # Example local networks
    ├── external_rules.csv.example    # Example external rules
    ├── local_services.csv.example    # Example local services
    ├── local_networks.csv            # Your local networks (git-ignored)
    ├── external_rules.csv            # Your external rules (git-ignored)
    └── local_services.csv            # Your local services (git-ignored)
```

## 🔧 Configuration Guide

### Local Networks

Define which networks can access your local services. The script will apply all local service rules to these networks.

**Format:** `name,cidr`

```csv
name,cidr
Home_IPv4,192.168.1.0/24
Office_IPv4,192.168.2.0/24
Home_IPv6,2001:db8::/64
```

### External Rules (Public Ports)

Services that should be accessible from anywhere on the internet.

**Format:** `port,protocol,description`

```csv
port,protocol,description
80,tcp,HTTP
443,tcp,HTTPS
22,tcp,SSH (if public access needed)
```

### Local Services

Services that should only be accessible from your local networks.

**Format:** `port,protocol,description`

```csv
port,protocol,description
22,tcp,SSH
3000,tcp,Grafana
5432,tcp,PostgreSQL
8080,tcp,Alternative HTTP
9000,tcp,Portainer
```

## 🐳 Docker Support

The script automatically detects your Docker network and applies local service rules to it. This allows containers to access your local services.

- **Auto-detection:** Automatically finds Docker bridge network CIDR
- **Custom CIDR:** Use `--docker-cidr` to specify a custom Docker network
- **Disable:** Use `--no-docker` to skip Docker configuration

## 🔒 Security Considerations

- ⚠️ **Review before applying:** Always use `--dry-run` first
- 🔐 **SSH Access:** Be careful when configuring SSH rules
- 🌐 **External Rules:** Only expose services that need public access
- 📝 **Regular Audits:** Periodically review your firewall rules
- 🔄 **Backup:** Keep backups of your CSV configuration files

## 🛠️ Troubleshooting

### UFW Not Installed

```bash
sudo apt update
sudo apt install ufw
```

### Permission Denied

Run the script with sudo:

```bash
sudo ./ufw_rules.sh
# Or with alias:
autoufw
```

### Command Not Found (after installing alias)

Reload your bash configuration:

```bash
source ~/.bash_aliases
# Or restart your terminal
```

### Windows Line Endings (CRLF) Issues

If you edit CSV files on Windows and see validation errors, the script automatically handles CRLF line endings. However, if issues persist, convert them to Unix format:

```bash
dos2unix config/*.csv
# Or using sed:
sed -i 's/\r$//' config/*.csv
```

### IPv6 Not Working

Check if IPv6 is enabled in UFW:

```bash
sudo nano /etc/default/ufw
# Set IPV6=yes
```

### View Current UFW Status

```bash
sudo ufw status verbose
```

## 📝 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Feel free to:

- Report bugs
- Suggest new features
- Submit pull requests
- Improve documentation

---

**⭐ If you find this project useful, please consider giving it a star!**
