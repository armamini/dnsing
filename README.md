# dns-checker

Multi-region DNS lookup tool powered by the [check-host.net](https://check-host.net) API.
Queries up to 50 global nodes simultaneously and displays A, AAAA records and TTL per location.

## Requirements

```bash
# Debian / Ubuntu
sudo apt install curl jq

# macOS
brew install curl jq
```

## Setup

```bash
chmod +x dns-checker.sh
```

## Usage

```
./dns-checker.sh <domain|ip> [options]
```

| Option     | Default | Description                       |
| ---------- | ------- | --------------------------------- |
| `-n <num>` | `50`    | Max nodes to query (hard cap: 50) |
| `-w <sec>` | `30`    | Seconds to wait for all results   |
| `-h`       | —       | Show help                         |

## Examples

```bash
# Basic domain lookup across 50 nodes
./dns-checker.sh google.com

# Query a specific IP
./dns-checker.sh 1.1.1.1

# Limit to 40 nodes and wait up to 20 seconds
./dns-checker.sh cloudflare.com -n 40 -w 20
```

## Output columns

| Column       | Description                                   |
| ------------ | --------------------------------------------- |
| Location     | Country flag, city, and country name          |
| IPv4 Address | Resolved A records (truncated if multiple)    |
| IPv6 Address | Resolved AAAA records                         |
| TTL          | Time-to-live in seconds returned by that node |

A `—` or `NXDOMAIN` in IP columns means the node could not resolve the target.
