# Introduction

[Contabo](https://contabo.com) is a Germany hoster with a good product portfolio that can be used through a well designed API. The best point is that all this comes for a very good price. In addition to my [bare metal based Single Server Platform](https://github.com/trayla/ssp) I decided to port this also to Contabo. This script deploys some virtual machines (instances) in a private network mainly as a base for my [Trayla Operations Platform Platform](https://github.com/trayla/top) but it maybe useful in other cases.

# Installation

Currently I rely on a base of previously bought instances. The buying process can also be accomplished by the APU but I found this a bit to dangerous. At the starting point you should buy some [Cloud VPS](https://contabo.com/en/vps/) or [Cloud VDS](https://contabo.com/en/vds/) instances. These are the only instance types, that support private networking, which is necessary in this szenario.

Buy at least the following instances:

- 1 Console: small sized VPS with 8GB RAM
- 1 Kubernetes Control Plane: small or medium sized VPS with 8GB or 16GB RAM
- 1-x Kubernetes Worker Nodes: medium or large sized VPS with 16GB or 60GB RAM based on your desired workload

Order these machines with the private networking option!

Clone this repository on any local Ubuntu 20.04 console machine
```
git clone https://github.com/trayla/ssp-contabo
```

Make changes to the config.json template according to your environment. Put the private IP addresses for each instance along with the [Contabo API credentials])https://my.contabo.com/api/details) into this file!

Start the script:
```
./install.sh
```

The script runs several tasks to provide clean instances all with Ubuntu 20.04 LTS, with firewall enabled and much miore, managable through the console instance. This is the perfect staring point for the [Trayla Operations Platform Platform](https://github.com/trayla/top) to be installed into the console instance.
